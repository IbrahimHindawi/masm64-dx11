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

cbuffer combine : register(b1)
{
    float exposure;
    int bloom;
};

Texture2D scene_color : register(t0);
Texture2D blurred : register(t1);
SamplerState linear_clamp : register(s1);

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    float3 color = scene_color.Sample(linear_clamp, p.uv).rgb;
    if (bloom) color += blurred.Sample(linear_clamp, p.uv).rgb;
    return float4(1.0 - exp(-color * exposure), 1.0);
}
