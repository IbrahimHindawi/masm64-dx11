#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;          // the whole ring's slow turn
    float4x4 normal_matrix;
    float4x4 view;
    float4x4 projection;
    float3 view_position;
};

Texture2D diffuse_map : register(t0);
SamplerState linear_wrap : register(s0);

struct rock_in
{
    float3 position : POSITION;     // per vertex, slot 0
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
    float4 row0 : INSTANCE0;        // per instance, slot 1
    float4 row1 : INSTANCE1;
    float4 row2 : INSTANCE2;
    float4 row3 : INSTANCE3;
};

struct vs_out
{
    float4 position : SV_Position;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

vs_out vs_main(rock_in v)
{
    float4x4 placement = float4x4(v.row0, v.row1, v.row2, v.row3);
    float4x4 m = mul(model, placement);
    vs_out o;
    o.position = mul(projection, mul(view, mul(m, float4(v.position, 1.0))));
    // only rotations and uniform scales here, so the model matrix itself
    // keeps normals pointing the right way
    o.normal = mul((float3x3)m, v.normal);
    o.uv = v.uv;
    return o;
}

float4 ps_main(vs_out p) : SV_Target
{
    float3 n = normalize(p.normal);
    float light = 0.25 + 0.75 * max(dot(n, normalize(float3(0.4, 0.8, 0.6))), 0.0);
    return float4(diffuse_map.Sample(linear_wrap, p.uv).rgb * light, 1.0);
}
