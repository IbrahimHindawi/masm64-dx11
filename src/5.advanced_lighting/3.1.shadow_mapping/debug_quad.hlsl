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

// the shadow map on screen: near is black, far is white
Texture2D<float> depth_map : register(t0);
SamplerState linear_wrap : register(s0);

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    return float4(depth_map.Sample(linear_wrap, p.uv).xxx, 1.0);
}
