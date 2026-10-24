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

Texture2D equirect : register(t0);
SamplerState linear_wrap : register(s0);

static const float PI = 3.14159265359;

// a direction to a point on the panorama: longitude across, latitude down
// (D3D's v runs down the image, so the top row is straight up)
float2 equirect_uv(float3 d)
{
    return float2(atan2(d.z, d.x) / (2.0 * PI) + 0.5, 0.5 - asin(d.y) / PI);
}

float4 ps_main(sky_vertex p) : SV_Target
{
    return float4(equirect.SampleLevel(linear_wrap, equirect_uv(normalize(p.direction)), 0).rgb, 1.0);
}
