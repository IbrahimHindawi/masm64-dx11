# 2. Lighting

Faking how light reflects, one term at a time. Each lighting lesson declares a
`transforms` constant buffer at `b0` (the model and normal matrices, the view,
the projection and the eye position), rewritten for every draw by its
`draw_cube`, and its own lighting constants at `b1` and up. The small cube
marking the light has a shader file of its own, `light_cube.hlsl`, so
lighting never touches it, as LearnOpenGL's `light_cube.vs/fs` do.

## 1 Colors

`src/2.lighting/1.colors/colors.asm`

The colour you see is the light's colour times what the surface reflects,
channel by channel. Coral under white light is coral; under green light it is
a dark green, because coral reflects little green.

## 2.1 Basic lighting

`src/2.lighting/2.1.basic_lighting/basic_lighting.asm`

Phong, in three parts:

- **ambient**: a small constant, so nothing is fully black
- **diffuse**: `max(dot(n, l), 0)`, brightest where the surface faces the light
- **specular**: `pow(max(dot(v, reflect(-l, n)), 0), shininess)`, the
  highlight where the light bounces towards the eye

They need the normal, the light and the eye in one space; world space here.
Normals are moved there by the *normal matrix*, the inverse transpose of the
model matrix, so a stretched object keeps them perpendicular to its surface.
HLSL has no `inverse()`, so `draw_cube` computes it on the CPU
(`m4_normal_matrix`) and sends it with every draw.

**Try:** scale the cube by (1, 3, 1) and use the model matrix for normals
instead. The lighting goes wrong on the long faces.

## 3.1 Materials

`src/2.lighting/3.1.materials/materials.asm`

Each term gets a colour on both sides: how much ambient, diffuse and specular
light the *light* gives, and how much the *material* reflects. The highlight
takes the light's colour; the body takes the product of both.

## 4.1 Lighting maps

`src/2.lighting/4.1.lighting_maps/lighting_maps.asm`

The material comes from textures, per texel. A *diffuse map* holds the colour
and a *specular map* how strongly each texel shines: the crate's steel rim is
bright, its wood black, so wood never gets a highlight.

## 5.1 Light casters

`src/2.lighting/5.1.light_casters/light_casters.asm`

The kinds of light differ in how each pixel finds the direction to the light
and how much arrives:

- **directional**: one direction for every pixel, no falloff (the sun)
- **point**: a position, fading as `1 / (c + l*d + q*d^2)`
- **spot**: a point light within a cone. Between an inner and an outer angle
  the light ramps from full to none, so the circle's edge is soft. Both angles
  are passed as cosines, so the shader compares dot products without `acos`.

Keys 1, 2 and 3 switch between them; LearnOpenGL has a program for each.

## 6 Multiple lights

`src/2.lighting/6.multiple_lights/multiple_lights.asm`

Light adds up: each source is worked out alone and the results summed. The
point lights travel as an array in a constant buffer; HLSL starts every array
element on a 16-byte boundary, so each `vec3` in the MASM struct is padded.

**Try:** turn the four point lights into an array of any length, with the
length fixed by a `#define` in the shader.
