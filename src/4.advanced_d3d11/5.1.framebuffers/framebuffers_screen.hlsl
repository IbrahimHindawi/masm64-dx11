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

cbuffer post : register(b1)
{
    int mode;
};

Texture2D scene_color : register(t0);
SamplerState linear_clamp : register(s0);

// Weighted sum of the 3x3 pixels around uv.
float3 kernel3x3(float2 uv, float k[9])
{
    float w, h;
    scene_color.GetDimensions(w, h);
    float2 texel = 1.0 / float2(w, h);
    float3 sum = 0.0;
    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            sum += k[(y + 1) * 3 + (x + 1)] * scene_color.Sample(linear_clamp, uv + float2(x, y) * texel).rgb;
        }
    }
    return sum;
}

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    float3 color = scene_color.Sample(linear_clamp, p.uv).rgb;
    if (mode == 2) color = 1.0 - color;
    if (mode == 3) color = dot(color, float3(0.2126, 0.7152, 0.0722));
    if (mode == 4)
    {
        float k[9] = { -1, -1, -1, -1, 9, -1, -1, -1, -1 };
        color = kernel3x3(p.uv, k);
    }
    if (mode == 5)
    {
        float k[9] = { 1, 2, 1, 2, 4, 2, 1, 2, 1 };
        color = kernel3x3(p.uv, k) / 16.0;
    }
    if (mode == 6)
    {
        float k[9] = { 1, 1, 1, 1, -8, 1, 1, 1, 1 };
        color = kernel3x3(p.uv, k);
    }
    return float4(color, 1.0);
}
