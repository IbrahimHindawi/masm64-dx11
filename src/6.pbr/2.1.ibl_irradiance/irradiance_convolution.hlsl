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

// The unit cube's corners are the directions to look up, drawn through
// one face's view.
struct sky_vertex
{
    float4 position : SV_Position;
    float3 direction : DIRECTION;
};

sky_vertex vs_main(float3 position : POSITION)
{
    sky_vertex o;
    o.direction = position;
    o.position = mul(projection, mul(view, float4(position, 1.0)));
    return o;
}

// Diffuse irradiance: for the normal `n` (this pixel's direction), the
// average of the environment over the hemisphere around it, each direction
// weighted by cos(theta), the way a matte surface receives it.
TextureCube env : register(t0);
SamplerState linear_clamp : register(s1);

static const float PI = 3.14159265359;

float4 ps_main(sky_vertex p) : SV_Target
{
    float3 n = normalize(p.direction);
    // any two directions perpendicular to n and to each other
    float3 up = abs(n.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    float3 right = normalize(cross(up, n));
    up = cross(n, right);

    float3 sum = 0.0;
    float count = 0.0;
    float step = 0.025;
    for (float phi = 0.0; phi < 2.0 * PI; phi += step)
    {
        for (float theta = 0.0; theta < 0.5 * PI; theta += step)
        {
            float3 local = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
            float3 d = local.x * right + local.y * up + local.z * n;
            // cos(theta) for the angle of incidence, sin(theta) because the
            // rings of the hemisphere shrink towards the pole
            sum += env.SampleLevel(linear_clamp, d, 0).rgb * cos(theta) * sin(theta);
            count += 1.0;
        }
    }
    return float4(PI * sum / count, 1.0);
}
