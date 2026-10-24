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

// the average of 4x4 pixels: exactly one tile of the noise, which cancels
Texture2D<float> occlusion : register(t0);

float ps_main(fullscreen_vertex p) : SV_Target
{
    int2 pixel = int2(p.position.xy);
    float sum = 0.0;
    for (int y = -2; y < 2; y++)
    {
        for (int x = -2; x < 2; x++)
        {
            sum += occlusion.Load(int3(pixel + int2(x, y), 0));
        }
    }
    return sum / 16.0;
}
