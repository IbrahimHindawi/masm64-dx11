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

cbuffer tone : register(b1)
{
    float exposure;
    int enabled;
};

Texture2D hdr_buffer : register(t0);
SamplerState linear_wrap : register(s0);

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    float3 color = hdr_buffer.Sample(linear_wrap, p.uv).rgb;
    // The back buffer view is sRGB, so the result is gamma encoded on the
    // way out; no pow(1/2.2) here.
    if (enabled) color = 1.0 - exp(-color * exposure);
    return float4(saturate(color), 1.0);
}
