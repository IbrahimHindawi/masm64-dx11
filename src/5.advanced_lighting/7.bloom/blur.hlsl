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

// one direction of a Gaussian blur: nine taps along `direction`
cbuffer blur : register(b1)
{
    float2 direction;
};

Texture2D source : register(t0);
SamplerState linear_clamp : register(s1);

static const float weights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    float3 sum = source.Sample(linear_clamp, p.uv).rgb * weights[0];
    for (int i = 1; i < 5; i++)
    {
        sum += source.Sample(linear_clamp, p.uv + direction * i).rgb * weights[i];
        sum += source.Sample(linear_clamp, p.uv - direction * i).rgb * weights[i];
    }
    return float4(sum, 1.0);
}
