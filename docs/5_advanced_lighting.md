# 5. Advanced lighting

Shadows, surface detail, and the multi-pass techniques renderers are built
from. From 2 on, lighting is done in linear space and written through an sRGB
view of the back buffer.

## 1 Advanced lighting: Blinn-Phong

`src/5.advanced_lighting/1.advanced_lighting/advanced_lighting.asm`

Phong's specular term compares the eye with the reflected light. Past 90
degrees the dot product is clamped to zero, which cuts wide highlights off
with a visible edge. Blinn compares the normal with the halfway vector between
light and eye, which never passes 90 degrees for a visible surface. The lesson
uses low exponents and a grazing view, the case where the edge shows (Tab).

## 2 Gamma correction

`src/5.advanced_lighting/2.gamma_correction/gamma_correction.asm`

Screens show brightness as roughly `value^2.2`, and images are stored with the
inverse curve applied. Light, though, adds up only in linear space. D3D does
both conversions in hardware:

1. the texture is created `_SRGB`, so sampling it returns linear values
2. lighting happens in linear space
3. the back buffer is written through an `_SRGB` render target view, which
   encodes on the way in

With that in place, physically correct `1/d^2` falloff looks right. Tab shows
the uncorrected version, which needs the weaker `1/d` to look anywhere near as
natural.

## 3.1 Shadow mapping

`src/5.advanced_lighting/3.1.shadow_mapping/shadow_mapping.asm`

Render depth from the light; then, for each pixel, ask whether it is farther
from the light than what the light saw. D3D gives three tools here:

- **One texture, two views.** The shadow map is `R32_TYPELESS`: a `D32_FLOAT`
  depth view to draw it, an `R32_FLOAT` view to read it.
- **Rasterizer depth bias.** Shadow acne, a surface shadowing itself, is fixed
  by slope-scaled bias in the shadow pass's rasterizer state rather than a
  constant subtracted in the shader.
- **Comparison samplers.** `SampleCmpLevelZero` compares and filters 2x2
  texels in hardware; nine of them give soft edges. The sampler's border is
  the far plane, so whatever the light never saw is lit.

Tab shows the shadow map (LearnOpenGL's 3.1.1 shadow_mapping_depth).

## 3.2 Point shadows

`src/5.advanced_lighting/3.2.point_shadows/point_shadows.asm`

A point light needs a shadow map in every direction, so it gets a cube of
depth. One pass fills all six faces: the depth cube is bound as a six-slice
array, and a geometry shader emits each triangle six times, steering each copy
to its face with `SV_RenderTargetArrayIndex`. The map stores distance to the
light, written by the pixel shader through `SV_Depth`, which is comparable
across faces. Twenty jittered hardware comparisons soften the edges.

## 4 Normal mapping

`src/5.advanced_lighting/4.normal_mapping/normal_mapping.asm`

A texture of normals, one per texel, so a flat wall lights like bricks. The
map's normals are in tangent space, z out of the surface, so the vertex shader
builds the tangent, bitangent and normal in world space (TBN) and the pixel
shader turns the sampled normal through them. `create_wall` computes the
tangent from position and uv deltas. The map's files are made for GL, which
shows them upside down, so here their +y points down the image, the way v
runs, and the bitangent is `cross(tangent, normal)`.

## 5.1 Parallax mapping

`src/5.advanced_lighting/5.1.parallax_mapping/parallax_mapping.asm`

A depth map moves the texture coordinate to where the eye ray would have hit
the sunken surface. Keys 1 to 4: normal mapping only; one shift by the depth
at the original point; *steep* parallax, stepping along the ray in layers
until it is below the surface; and *occlusion* mapping, which interpolates
between the last two layers (LearnOpenGL's 5.1, 5.2 and 5.3).

## 6 HDR

`src/5.advanced_lighting/6.hdr/hdr.asm`

An 8-bit target clamps everything at 1. A 16-bit float target keeps real
values, here a light two hundred times brighter than the rest, and a final
pass maps them into 0..1 with an exposure curve, `1 - exp(-color * exposure)`.
Tab compares with plain clamping; Up and Down change the exposure.

## 7 Bloom

`src/5.advanced_lighting/7.bloom/bloom.asm`

Bright light seems to spill over its edges. The scene writes two targets at
once (`SV_Target0`, `SV_Target1`): the colour, and only what is brighter than
1. The bright part is blurred by a separable Gaussian, horizontal then
vertical, ten passes ping-ponging between two half-resolution targets, then
added back before tone mapping.

## 8.1 Deferred shading

`src/5.advanced_lighting/8.1.deferred_shading/deferred_shading.asm`

Draw the geometry once, storing position, normal, albedo and specular
strength (the G-buffer, three targets); then light every visible pixel exactly
once in a full-screen pass, here by 32 lights. The light cubes, drawn forward
afterwards, are depth-tested against the G-buffer's depth buffer bound
together with the back buffer, where GL copies the depth across with a blit.
The albedo target is `_SRGB`, so its eight bits are spent where the eye
notices. Tab shows each buffer.

## 9 SSAO

`src/5.advanced_lighting/9.ssao/ssao.asm`

Ambient light reaches creases and corners as fully as open floor, which it
should not. SSAO estimates occlusion from a view-space G-buffer: around each
pixel, 64 points in a hemisphere are projected back to the screen, and each one
the G-buffer has something in front of counts as buried. A 4x4 noise texture
rotates the kernel per pixel, trading banding for noise, and a 4x4 average
removes the noise. The result scales the ambient term (Tab).
