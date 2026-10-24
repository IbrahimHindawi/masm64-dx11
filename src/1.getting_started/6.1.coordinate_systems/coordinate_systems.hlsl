#pragma pack_matrix(row_major)

cbuffer object : register(b0)
{
    float4x4 model;
    float4x4 view;
    float4x4 projection;
};

Texture2D crate : register(t0);
Texture2D face : register(t1);
SamplerState linear_wrap : register(s0);

struct vs_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

struct vs_out
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD;
};

vs_out vs_main(vs_in v)
{
    vs_out o;
    o.position = mul(projection, mul(view, mul(model, float4(v.position, 1.0))));
    o.uv = v.uv;
    return o;
}

float4 ps_main(vs_out p) : SV_Target
{
    return lerp(crate.Sample(linear_wrap, p.uv), face.Sample(linear_wrap, p.uv), 0.2);
}
