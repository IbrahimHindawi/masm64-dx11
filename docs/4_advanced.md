# 4. Advanced D3D11

LearnOpenGL's "advanced OpenGL": the fixed-function stages and the less
common resource types. 1.1 to 5.1 share one unlit scene, two marble cubes on a
metal floor, so each is about one piece of state.

## 1.1 Depth testing

`src/4.advanced_d3d11/1.1.depth_testing/depth_testing.asm`

The depth buffer and its test: keep a pixel if it is nearer than what is
stored. Tab shows the raw depth, which is nearly all white because perspective
spends most of the 0..1 range just in front of the camera, and then the depth
with the projection undone, the real distance:

    linear = near * far / (far - depth * (far - near))

That is D3D's form of the formula; GL's first remaps -1..1 to 0..1.

## 2 Stencil testing

`src/4.advanced_d3d11/2.stencil_testing/stencil_testing.asm`

Eight bits per pixel beside the depth, which draws can write and be masked by.
The cubes write 1 where they land; then slightly larger copies are drawn only
where the stencil is *not* 1, which is the rim around each. Depth is off for
the rim, so it shows through everything. In D3D each configuration is one
immutable depth-stencil state object, and the reference value is given when
binding it.

## 3.1 Blending

`src/4.advanced_d3d11/3.1.blending/blending.asm`

Grass texels are either there or not: the pixel shader `clip`s the transparent
ones, and the rest is ordinary opaque geometry. The windows are partly
transparent, so the blend state mixes each pixel with what is behind it,
which means drawing them after everything opaque and from farthest to
nearest. The grass and windows are sampled with clamp so their edges do not
wrap; since D3D's samplers are separate objects, that means binding a clamp
sampler into `s0` for those draws.

## 4 Face culling

`src/4.advanced_d3d11/4.face_culling/face_culling.asm`

Back faces of a closed mesh are never seen, so the rasterizer can skip them.
Front and back come from winding (see `0_from_gl_to_d3d11.md`). Tab cycles
none, back and front culling; culling front faces shows the cubes' insides.

## 5.1 Framebuffers

`src/4.advanced_d3d11/5.1.framebuffers/framebuffers.asm`

Render the scene into a texture, then draw one full-screen triangle that reads
it and writes the screen: post-processing. The triangle is built in the vertex
shader from `SV_VertexID`, with no vertex buffer. Keys 1 to 6: inversion,
greyscale, and three 3x3 kernels (sharpen, blur, edge detection).

GL's framebuffer object is, in D3D, views of one texture: a render target view
to draw into it and a shader resource view to read it.

## 6.1 Cubemaps

`src/4.advanced_d3d11/6.1.cubemaps/cubemaps.asm`, `skybox.hlsl`

Six images as one texture, sampled by direction. `load_cubemap` builds it as a
six-slice texture array with the `TEXTURECUBE` flag. A **skybox** is a cube
around the camera drawn with the view's translation removed and its depth
forced to the far plane (`position.xyww`), so it fills only what nothing else
covered. **Reflection** looks the sky up along the eye ray bounced off the
surface; **refraction** bends the ray instead (Tab).

## 7 Advanced data

`src/4.advanced_d3d11/7.advanced_data/advanced_data.asm`

GL's `glBufferSubData` and `glMapBuffer` are D3D's dynamic buffers with `Map`.
The water's heights are computed on the CPU and rewritten every frame into a
dynamic vertex buffer. Its colours never change, so they live in a second
buffer, uploaded once; the input layout reads `POSITION` from slot 0 and
`COLOR` from slot 1. LearnOpenGL's chapter on this has no program.

## 8 Advanced HLSL

`src/4.advanced_d3d11/8.advanced_hlsl/advanced_hlsl.asm`

- **One constant buffer, many shaders.** Four pixel shaders, compiled from one
  file by entry name, all read the camera at `b0` without being given it.
- **System values.** `SV_Position` in a pixel shader is the pixel's
  coordinates (GL's `gl_FragCoord`), so the left half of the window is
  darkened. `SV_IsFrontFace` (`gl_FrontFacing`) shades the cubes' insides as a
  checker, visible because their near faces are clipped away.

## 9.1 Geometry shader

`src/4.advanced_d3d11/9.1.geometry_shader/geometry_shader.asm`

A stage that sees whole triangles and can emit other primitives. One pushes
each triangle out along its face normal: the backpack explodes. The other
emits three lines per triangle along the vertex normals, a quick check that a
model's normals are right. The shader class compiles `gs_main` when a file has
one, and `shader_use` binds it, or unbinds it when there is none.

## 10.1 Instancing

`src/4.advanced_d3d11/10.1.instancing/instancing.asm`

Twenty thousand rocks in one draw call. Their model matrices go into a second
vertex buffer whose elements are marked per instance; each matrix is four
`float4` inputs, since one input element holds at most four floats, and
`DrawInstanced` makes the copies.

## 11.1 Anti-aliasing

`src/4.advanced_d3d11/11.1.anti_aliasing/anti_aliasing.asm`

MSAA tests coverage at four points per pixel and keeps a colour per sample;
resolving averages them, softening the edges. The swap chain cannot be
multisampled, so the cube is drawn into a 4x target with a 4x depth buffer and
`ResolveSubresource` averages it into the back buffer (LearnOpenGL's 11.2
anti_aliasing_offscreen). Tab compares.
