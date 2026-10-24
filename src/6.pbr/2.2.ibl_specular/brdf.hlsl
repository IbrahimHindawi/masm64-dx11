// One triangle covering the screen, made from SV_VertexID alone: no
// vertex buffer, no input layout. uv runs 0..1 across and down the screen,
// and the parts of the triangle past the edges are clipped away.
struct fullscreen_vertex
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD;
};

fullscreen_vertex vs_main(uint id : SV_VertexID)
{
    fullscreen_vertex o;
    o.uv = float2((id << 1) & 2, id & 2);
    o.position = float4(o.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
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
    // The map's y is up the image, against v: cross(n, t), as in 5.4 normal mapping.
    float3 b = cross(n, t);
    return normalize(mul(tangent_normal, float3x3(t, b, n)));
}

// Importance sampling the GGX lobe, shared by the prefilter and the BRDF
// table: instead of sampling every direction evenly, put the samples where
// the lobe is, so 1024 of them are enough.

// The Hammersley sequence: well spread points in the unit square.
float2 hammersley(uint i, uint count)
{
    return float2(float(i) / float(count), float(reversebits(i)) * 2.3283064365386963e-10);
}

// A halfway vector around `n`, distributed as GGX of `roughness` prefers.
float3 importance_sample_ggx(float2 xi, float3 n, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi.x;
    float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
    float sin_theta = sqrt(1.0 - cos_theta * cos_theta);
    float3 h = float3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
    float3 up = abs(n.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, n));
    float3 bitangent = cross(n, tangent);
    return normalize(tangent * h.x + bitangent * h.y + n * h.z);
}

// The BRDF table: for n.v across and roughness down, how much of F0 the
// specular integral keeps (r) and how much it adds regardless of F0 (g).
float2 integrate_brdf(float n_dot_v, float roughness)
{
    float3 v = float3(sqrt(1.0 - n_dot_v * n_dot_v), 0.0, n_dot_v);
    float3 n = float3(0.0, 0.0, 1.0);
    float scale = 0.0;
    float bias = 0.0;
    const uint count = 1024;
    for (uint i = 0; i < count; i++)
    {
        float3 h = importance_sample_ggx(hammersley(i, count), n, roughness);
        float3 l = normalize(2.0 * dot(v, h) * h - v);
        float n_dot_l = max(l.z, 0.0);
        float n_dot_h = max(h.z, 0.0);
        float v_dot_h = max(dot(v, h), 0.0);
        if (n_dot_l > 0.0)
        {
            float g = geometry_smith(n_dot_v, n_dot_l, roughness, true);
            float g_vis = g * v_dot_h / (n_dot_h * n_dot_v);
            float fc = pow(1.0 - v_dot_h, 5.0);
            scale += (1.0 - fc) * g_vis;
            bias += fc * g_vis;
        }
    }
    return float2(scale, bias) / float(count);
}

float2 ps_main(fullscreen_vertex p) : SV_Target
{
    // the same mapping the lookup uses: u = n.v, v = roughness
    return integrate_brdf(max(p.uv.x, 0.001), p.uv.y);
}
