#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view;
    float4x4 projection;
    float3 view_position;
};

TextureCube sky : register(t0);
SamplerState linear_wrap : register(s0);

struct sky_vertex
{
    float4 position : SV_Position;
    float3 direction : DIRECTION;
};

sky_vertex vs_main(float3 position : POSITION)
{
    sky_vertex o;
    // The cube's corners double as the directions to look up.
    o.direction = position;
    float4 clip = mul(projection, mul(view, float4(position, 1.0)));
    // z = w: after the divide, depth is exactly 1, the far plane.
    o.position = clip.xyww;
    return o;
}

float4 ps_main(sky_vertex p) : SV_Target
{
    return float4(sky.Sample(linear_wrap, p.direction).rgb, 1.0);
}
