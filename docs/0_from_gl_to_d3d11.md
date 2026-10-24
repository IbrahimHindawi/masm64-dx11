# From GL to D3D11

LearnOpenGL's maths and techniques carry over unchanged. What changes is a
handful of conventions, and each one bites exactly once. They are all here,
with the lesson where each first matters.

## The same

- **The world is right-handed.** +x right, +y up, and the camera looks down
  -z, as in GLM. The matrices in `includes/math.asm` are built for that, so
  every position, light and camera in LearnOpenGL works as written.
- **Matrices multiply in the same order.** A point is transformed as
  `projection * view * model * p`, and `T * R * S` scales first.
- **Cubemap faces are the same.** +x, -x, +y, -y, +z, -z, with the same
  direction-to-texel rules, so the skybox images load as they are.

## Different

### The window and the context

GLFW gives LearnOpenGL a window and a GL context in a few calls. Here Win32
and D3D11 do it directly, written out in 1.1 and 2.1 and kept in
`includes/learn/window.asm` from then on: `RegisterClassExA` and
`CreateWindowExA` for the window, `D3D11CreateDeviceAndSwapChain` for the
device (which creates resources), the immediate context (which records
drawing) and the swap chain (the images that take turns on screen). The
window is a fixed size, so no render target ever needs rebuilding on resize.

Input is polled the way `glfwGetKey` is, with `GetAsyncKeyState`, but that
reads the whole keyboard, so the lessons ignore it while another window has
the focus. Events that arrive once (a key press for a toggle, the mouse
wheel) come through the window procedure instead, like GLFW's callbacks.

### Depth runs 0..1

GL's clip-space depth runs from -1 (near) to 1 (far); D3D's from 0 to 1. Only
the projection matrices change (`m4_perspective`, `m4_ortho`), plus the one
formula that undoes a projection: linearizing depth in 4.1.1.

### Matrices are stored row by row

`mat4` stores `m[row * 4 + col]`. HLSL would read a constant buffer's matrices
column by column, so every shader that reads one says

    #pragma pack_matrix(row_major)

after which `mul(M, v)` in HLSL is `M * v`, exactly as in GLSL. Forgetting the
pragma transposes every matrix silently; any shader declaring a matrix
constant buffer carries it.

### Texture coordinate (0, 0) is the top-left

D3D puts the first row of an image at v = 0; GL puts it at the bottom. GL code
flips images on load (`stbi_set_flip_vertically_on_load`) to compensate, and
D3D code simply does not. Where it matters:

- vertex data written here has v growing downwards
- `.obj` files usually assume v up, so `model_load` can flip v; the backpack's
  textures happen to suit top-down v already, the planet and rock need the
  flip
- normal maps store "up the image" as +y, which is the direction v
  *decreases*: the bitangent is `cross(normal, tangent)` (5.4)
- the equirectangular panorama maps latitude as `0.5 - asin(y) / pi` (6.2.1)

### Winding

Both APIs decide front and back from the order a triangle's corners appear on
screen. GL calls counter-clockwise the front by default, D3D clockwise. Every
vertex array here is counter-clockwise from outside, and each lesson's
rasterizer state says so (`FrontCounterClockwise`), so LearnOpenGL's winding
holds. D3D culls back faces by default and GL culls nothing; the lessons keep
GL's behaviour until 4.4 face culling turns it on.

### Drawing into cubemap faces

A cubemap's faces are laid out left-handed, and no right-handed look-at can
produce that frame: it gets the face's right or its up correct, never both.
GL's bottom-up framebuffer flips every rendered image, which happens to fix
that for free. D3D's framebuffer is top-down, so the lessons that draw into
cube faces (5.3.2, 6.2) flip the face projection's y instead. That flip
reverses winding, so those passes draw with culling off.

### Uniforms are constant buffers

There is no `glUniform`. Shader inputs that are the same for a whole draw live
in constant buffers: a struct on the CPU, copied whole with `Map`, bound to a
register (`b0`, `b1`, ...) that the shader names. Two rules come with that:

- **HLSL packs a cbuffer into 16-byte registers.** A `float3` and a following
  `float` share one; a `float3` followed by another `float3` does not. The MASM
  structs that mirror cbuffers pad to match (`pad real4 ?`), and array elements
  always start on a new register.
- **A register is shared by every shader that names it.** The lessons bind
  their `transforms` buffer to `b0` once a frame and every shader reads it:
  GL's uniform buffer object, without the extra step (4.8).

### Samplers are separate from textures

GL stores filtering and wrapping on the texture object. D3D has sampler
objects of their own, bound to sampler registers (`s0`, ...). A lesson that
wants clamp for some draws binds a different sampler for them (4.3.1).

### Framebuffers are views

GL attaches textures to a framebuffer object. D3D creates *views* of a
resource: a render target view to draw into it, a shader resource view to read
it, a depth-stencil view for depth. One texture can have several. A depth
texture created as `R32_TYPELESS` is seen as `D32_FLOAT` while drawing shadows
and as `R32_FLOAT` while reading them (5.3.1). A texture cannot be read and
written at once, so the lessons unbind textures before drawing into one.

### The swap chain cannot be multisampled

Flip-model swap chains, the modern kind, are never multisampled. MSAA renders
into a multisampled texture and `ResolveSubresource` averages it into the back
buffer (4.11.1).

### sRGB is a format, not a switch

GL has `GL_FRAMEBUFFER_SRGB`. D3D has `_SRGB` formats: a texture created as
`R8G8B8A8_UNORM_SRGB` decodes to linear when sampled, and a render target
view with that format encodes when written. The back buffer stays
`R8G8B8A8_UNORM` and gets an sRGB view; lessons from 5.2 on draw through it.

### Shaders are compiled from text at startup

Each shader file holds a vertex and a pixel shader (`vs_main`, `ps_main`) and
sometimes a geometry shader (`gs_main`). `learn/shader.asm` compiles them with
`D3DCompile`, as LearnOpenGL's Shader class compiles GLSL. A compile error
prints the file, line and message, and the lesson exits.
