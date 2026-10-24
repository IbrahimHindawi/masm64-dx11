// Read matrices row by row, as rin stores them; mul(M, v) is then M * v.
#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view;
    float4x4 projection;
    float3 view_position;
};

struct vs_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

// Position and normal in world space, where the lighting is done.
struct vs_out
{
    float4 position : SV_Position;
    float3 world : WORLD;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

vs_out vs_main(vs_in v)
{
    vs_out o;
    float4 world = mul(model, float4(v.position, 1.0));
    o.world = world.xyz;
    o.position = mul(projection, mul(view, world));
    o.normal = mul((float3x3)normal_matrix, v.normal);
    o.uv = v.uv;
    return o;
}

// The Cook-Torrance BRDF used throughout chapter 6.
//
//   f = kd * albedo / pi + D * F * G / (4 (n.v) (n.l))
//
//   D  normal distribution: how many microfacets face along the halfway
//      vector (GGX / Trowbridge-Reitz)
//   F  Fresnel: how much light reflects rather than refracts, more at
//      grazing angles (Schlick's approximation)
//   G  geometry: how much the microfacets shadow and mask each other
//      (Schlick-GGX, combined for light and view by Smith's method)

static const float PI = 3.14159265359;

float distribution_ggx(float3 n, float3 h, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float n_dot_h = max(dot(n, h), 0.0);
    float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

float geometry_schlick_ggx(float n_dot_x, float k)
{
    return n_dot_x / (n_dot_x * (1.0 - k) + k);
}

// k depends on the use: direct light remaps roughness one way, image based
// lighting (the `ibl` path) another.
float geometry_smith(float n_dot_v, float n_dot_l, float roughness, bool ibl)
{
    float r = roughness + 1.0;
    float k = ibl ? roughness * roughness / 2.0 : r * r / 8.0;
    return geometry_schlick_ggx(n_dot_v, k) * geometry_schlick_ggx(n_dot_l, k);
}

float3 fresnel_schlick(float cos_theta, float3 f0)
{
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}

// For image based light, where there is no single halfway vector: rough
// surfaces get less of the grazing-angle boost.
float3 fresnel_schlick_roughness(float cos_theta, float3 f0, float roughness)
{
    return f0 + (max((1.0 - roughness).xxx, f0) - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}

// Light reflected towards `v` from one light arriving along `l` with
// `radiance`, by a surface of the given material.
float3 cook_torrance(float3 n, float3 v, float3 l, float3 radiance, float3 albedo, float metallic, float roughness)
{
    float3 h = normalize(v + l);
    float n_dot_v = max(dot(n, v), 0.0);
    float n_dot_l = max(dot(n, l), 0.0);
    // Dielectrics reflect about 4% head on; metals reflect their own colour.
    float3 f0 = lerp(0.04.xxx, albedo, metallic);
    float3 f = fresnel_schlick(max(dot(h, v), 0.0), f0);
    float3 specular = distribution_ggx(n, h, roughness) * geometry_smith(n_dot_v, n_dot_l, roughness, false) * f
                    / (4.0 * n_dot_v * n_dot_l + 0.0001);
    // What is not reflected is refracted and scattered: diffuse. Metals
    // absorb it, so they have none.
    float3 kd = (1.0 - f) * (1.0 - metallic);
    return (kd * albedo / PI + specular) * radiance * n_dot_l;
}

// A normal map read without stored tangents: the tangent frame is rebuilt
// per pixel from how position and uv change across the screen.
float3 normal_from_map(float3 tangent_normal, float3 world, float3 n, float2 uv)
{
    float3 q1 = ddx(world);
    float3 q2 = ddy(world);
    float2 st1 = ddx(uv);
    float2 st2 = ddy(uv);
    // The direction u grows in; the determinant's sign keeps it right
    // whichever way v runs.
    float det = st1.x * st2.y - st2.x * st1.y;
    float3 t = normalize((q1 * st2.y - q2 * st1.y) * sign(det));
    t = normalize(t - n * dot(n, t));
    // The map's y points down the image, along v: cross(t, n), as in 5.4
    // normal mapping.
    float3 b = cross(t, n);
    return normalize(mul(tangent_normal, float3x3(t, b, n)));
}

cbuffer material : register(b1)
{
    float3 albedo;
    float metallic;
    float roughness;
    float ao;
};

cbuffer lights : register(b2)
{
    float4 light_positions[4];
    float4 light_colors[4];
};

TextureCube irradiance_map : register(t0);
SamplerState linear_clamp : register(s1);

float4 ps_main(vs_out p) : SV_Target
{
    float3 n = normalize(p.normal);
    float3 v = normalize(view_position - p.world);

    float3 lo = 0.0;
    for (int i = 0; i < 4; i++)
    {
        float3 to_light = light_positions[i].xyz - p.world;
        float d = length(to_light);
        lo += cook_torrance(n, v, to_light / d, light_colors[i].rgb / (d * d), albedo, metallic, roughness);
    }

    // ambient lighting from the environment: only the diffuse part so far;
    // the specular share (Fresnel) is what the surface does not scatter
    float3 f0 = lerp(0.04.xxx, albedo, metallic);
    float3 ks = fresnel_schlick_roughness(max(dot(n, v), 0.0), f0, roughness);
    float3 kd = (1.0 - ks) * (1.0 - metallic);
    float3 ambient = kd * irradiance_map.Sample(linear_clamp, n).rgb * albedo * ao;

    float3 color = ambient + lo;
    return float4(color / (color + 1.0), 1.0);
}
