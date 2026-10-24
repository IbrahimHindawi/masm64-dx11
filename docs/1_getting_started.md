# 1. Getting started

From an empty window to a scene you can fly through. Everything in later
chapters builds on these seven programs, so they show the most D3D11 by hand.

## 1.1 Hello window

`src/1.getting_started/1.1.hello_window/hello_window.asm`

LearnOpenGL starts with GLFW, which hides the window and the GL context. On
Windows both are short enough to write. 1.1 and 2.1 write them out; from 3.1
on `includes/learn/window.asm` does it, playing GLFW's part:

1. **A window.** `RegisterClassExA` names a window procedure, the callback
   Windows sends the window's events to (key presses, the mouse wheel,
   closing), and `CreateWindowExA` makes the window.
2. **A device and a swap chain.** `D3D11CreateDeviceAndSwapChain` returns three
   things: the *device*, which creates resources; the *context*, which records
   drawing; and the *swap chain*, the images that take turns being shown and
   drawn into.
3. **A render target view** of the swap chain's back buffer, so it can be
   cleared and drawn into.
4. **The loop**: hand waiting events to the window procedure (`PeekMessageA`,
   `DispatchMessageA`), read input, draw, `Present`.

The window is a fixed size, which keeps every render target in every later
lesson the size of the window.

**Try:** change the clear colour over time.

## 2.1 Hello triangle

`src/1.getting_started/2.1.hello_triangle/hello_triangle.asm`, `.hlsl`

The whole pipeline, once, with every call written out:

- **Vertices go into a buffer** on the GPU: `CreateBuffer` with
  `BIND_VERTEX_BUFFER`. GL needs a VBO and a VAO; D3D needs the buffer and,
  separately,
- **an input layout**, which says how to read one vertex: here a single
  `POSITION` of three floats. It is checked against the vertex shader's inputs
  when created, which is why it is created from the compiled vertex shader.
- **Two shaders**, compiled from HLSL with `D3DCompile`. The vertex shader runs
  once per vertex and returns its position in clip space (x and y from -1 to
  1). The pixel shader runs once per covered pixel and returns its colour.
- **An index buffer** lets the rectangle reuse vertices: four corners, six
  indices, two triangles (LearnOpenGL's 2.2 hello_triangle_indexed).

**Try:** press Tab for wireframe, and see the diagonal the two triangles share.

## 3.1 Shaders

`src/1.getting_started/3.1.shaders/shaders.asm`, `.hlsl`

Two ways to get data into a shader. **Per vertex**: each vertex carries a
colour, and the rasterizer interpolates it across the triangle, which is the
rainbow on the right. **Per draw**: a *constant buffer*, D3D's uniform. The
CPU fills a struct and copies it in with `Map(WRITE_DISCARD)`, which hands
back fresh memory each time so the GPU never waits on the CPU.

From here on `includes/learn/shader.asm` compiles shaders, doing what 2.1
wrote out, as LearnOpenGL's 3.3 shaders_class introduces its Shader class.

**Try:** add a `float offset` to the buffer and move the triangle with it.
Mind the 16-byte packing (see `0_from_gl_to_d3d11.md`).

## 4.1 Textures

`src/1.getting_started/4.1.textures/textures.asm`, `.hlsl`

An image is decoded by `includes/image.asm` (WIC, Windows' own codecs) into
RGBA8 pixels, and the lesson's `load_texture`, its counterpart of
LearnOpenGL's `loadTexture`, uploads them and has the GPU generate the
mipmaps. Each vertex says where in the image it sits, and the pixel shader
samples the image there. A *sampler*, a separate object in D3D, decides how:
filtering between texels and mips, wrapping at the edges.

D3D's texture coordinate (0, 0) is the image's top-left. LearnOpenGL flips
images on load because GL's is the bottom-left; here nothing is flipped.

**Try:** use coordinates above 1 and watch the wrap; then change the sampler's
filter to `MIN_MAG_MIP_POINT` and look at the texels.

## 5.1 Transformations

`src/1.getting_started/5.1.transformations/transformations.asm`, `.hlsl`

Moving vertices with a 4x4 matrix rather than editing them. Translation,
rotation and scale are each a matrix, and they combine by multiplication, read
right to left: in `translate * rotate` the rotation applies first, so the
square spins in place and then moves. Swap them and it orbits instead.

`includes/math.asm` is all of the maths the lessons need, about eight hundred
lines of SSE: vectors, `mat4`, rotations, projections, `look_at`, and an inverse for
normal matrices.

## 6.1 Coordinate systems

`src/1.getting_started/6.1.coordinate_systems/coordinate_systems.asm`, `.hlsl`

Three spaces, three matrices:

    clip = projection * view * model * position

*Model* places the cube in the world, *view* moves the world in front of the
camera, and *projection* applies perspective. D3D's depth range is 0..1, so
`m4_perspective` differs from GLM's in two entries.

With depth, triangles drawn later must not cover nearer ones drawn earlier. A
depth buffer keeps the nearest distance per pixel and discards anything
behind it. D3D starts with the depth test on, where GL starts with it off.

**Try:** stop clearing the depth buffer, and see the cubes break apart.

## 7.1 Camera

`src/1.getting_started/7.1.camera/camera.asm`, `includes/learn/camera.asm`

A camera is a view matrix built by `look_at` from a position, a direction and
an up vector. The direction comes from two angles, yaw and pitch, changed by
the mouse. Movement is scaled by the frame's duration, so the speed is the
same at any frame rate. Pitch is clamped short of straight up, where the up
vector would become parallel to the direction.

Every later lesson uses this camera. Hold the right mouse button to look.
