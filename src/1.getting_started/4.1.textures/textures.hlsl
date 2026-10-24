Texture2D crate : register(t0);
Texture2D face : register(t1);
SamplerState linear_wrap : register(s0);

struct vs_out
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD;
};

vs_out vs_main(float3 position : POSITION, float2 uv : TEXCOORD)
{
    vs_out o;
    o.position = float4(position, 1.0);
    o.uv = uv;
    return o;
}

float4 ps_main(vs_out p) : SV_Target
{
    return lerp(crate.Sample(linear_wrap, p.uv), face.Sample(linear_wrap, p.uv), 0.2);
}
