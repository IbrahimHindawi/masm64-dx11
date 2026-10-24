# 6. PBR

Physically based rendering: one lighting model, based on how light actually
reflects off rough surfaces, in place of chapter 2's hand-tuned terms. Each
lesson carries the BRDF functions in its shaders and builds its image based
lighting itself, as LearnOpenGL's do.

## The theory

A surface, seen closely enough, is many tiny flat mirrors (*microfacets*)
facing every which way; *roughness* says how widely their directions spread.
Light arriving at a point is either reflected at the surface, which is
specular, or refracted in, scattered, and re-emitted, which is diffuse. The
reflected share is given by *Fresnel*: little head on, nearly everything at a
grazing angle. Whatever is reflected cannot also be scattered, so the two
always sum to at most the incoming light: energy conservation.

**Metals** absorb what they refract, so they have no diffuse at all, and their
reflection is tinted by their colour. **Dielectrics** (plastic, wood, stone)
reflect about 4% head on, uncoloured, and scatter the rest in their colour.
That is why a PBR material is only four numbers: albedo, metallic, roughness
and ambient occlusion.

The reflectance equation sums, over every incoming direction l, the light
arriving times the BRDF times the cosine of the angle. Cook-Torrance's BRDF is

    f = kd * albedo / pi + D * F * G / (4 (n.v) (n.l))

- **D**, normal distribution (GGX): how many microfacets face along the
  halfway vector, and so reflect l towards v
- **F**, Fresnel (Schlick): how much is reflected at this angle, starting from
  F0, which is 0.04 for dielectrics and the albedo for metals
- **G**, geometry (Smith with Schlick-GGX): how much microfacets shadow and
  mask each other, more on rough surfaces and at grazing angles
- **kd = (1 - F)(1 - metallic)**: what is left for diffuse

With a few point lights the sum over directions becomes a sum over lights
(1.1). With an environment it is an integral over the whole sphere, which is
what 2.1 and 2.2 precompute.

Lights are given in real radiance, far above 1, so the result is tone mapped
(Reinhard, `c / (c + 1)`) and gamma encoded by the sRGB back buffer.

## 1.1 Lighting

`src/6.pbr/1.1.lighting/lighting.asm`, `pbr.hlsl`

Forty-nine spheres, metallic from 0 at the bottom to 1 at the top, roughness
from smooth on the left to matte on the right, under four lights. Dielectrics
keep their red body under white highlights; metals turn dark with red
highlights; roughness spreads each highlight out.

Tab swaps in a textured material, rusted iron, where all four numbers come
from maps per texel (LearnOpenGL's 1.2 lighting_textured). The normal map is
read without stored tangents: `normal_from_map` rebuilds the tangent frame per
pixel from screen-space derivatives of position and uv (`ddx`, `ddy`), with
the sign of the uv determinant keeping it right whichever way v runs.

## 2.1 IBL: diffuse irradiance

`src/6.pbr/2.1.ibl_irradiance/ibl_irradiance.asm`

Lighting by the surroundings: an HDR photograph of a room
(`newport_loft.hdr`, read by `includes/image.asm`). For diffuse light, each
normal needs the cosine-weighted average of the hemisphere it faces. That
depends only on the normal, so it is computed once at startup:

1. the equirectangular photo is projected onto a cubemap by drawing each face
   (`render_to_cube`) with a shader that turns direction into panorama uv
2. the cube is convolved into a small 32x32 *irradiance map*

The shader then needs one lookup by normal for the environment's diffuse
contribution, weighted by `kd`.

## 2.2 IBL: specular

`src/6.pbr/2.2.ibl_specular/ibl_specular.asm`

Reflections depend on the view as well as the surface, which is too much to
tabulate directly. Epic's *split sum* approximation separates it into two
precomputed parts:

- the **prefiltered environment**: the environment convolved by the GGX lobe,
  roughness rising one step per mip level (five here), built by importance
  sampling: 1024 directions per texel, concentrated where the lobe is,
  generated from the Hammersley sequence. Each sample reads a blurrier mip of
  the environment where samples are sparse, which avoids bright speckles.
- the **BRDF table**: a 2D texture over (n.v, roughness) holding a scale and a
  bias for F0, the rest of the integral, drawn once with a full-screen
  triangle.

    specular = prefiltered(R, roughness) * (F * scale + bias)

With 2.1's irradiance that is the full model. Smooth metals mirror the room,
rough ones blur it, and plastics catch a faint reflection at grazing angles.
Tab shows five textured materials: rusted iron, gold, grass, plastic, wall
(LearnOpenGL's 2.2.2 ibl_specular_textured).

**Try:** draw the background from a mip of the prefiltered map instead of the
environment, to see what each roughness sees.
