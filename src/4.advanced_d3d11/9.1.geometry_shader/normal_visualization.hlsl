// Read matrices row by row, as rin stores them; mul(M, v) is then M * v.
#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view;
    float4x4 projection;
    float3 view_position;
};

struct vs_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

// Position and normal in world space, where the lighting is done.
struct vs_out
{
    float4 position : SV_Position;
    float3 world : WORLD;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

vs_out vs_main(vs_in v)
{
    vs_out o;
    float4 world = mul(model, float4(v.position, 1.0));
    o.world = world.xyz;
    o.position = mul(projection, mul(view, world));
    o.normal = mul((float3x3)normal_matrix, v.normal);
    o.uv = v.uv;
    return o;
}

struct line_vertex
{
    float4 position : SV_Position;
};

// Triangles in, lines out: for each corner, a line from the surface along
// its normal. Two vertices per line, three lines per triangle.
[maxvertexcount(6)]
void gs_main(triangle vs_out input[3], inout LineStream<line_vertex> output)
{
    for (int i = 0; i < 3; i++)
    {
        line_vertex a;
        line_vertex b;
        a.position = mul(projection, mul(view, float4(input[i].world, 1.0)));
        b.position = mul(projection, mul(view, float4(input[i].world + normalize(input[i].normal) * 0.04, 1.0)));
        output.Append(a);
        output.Append(b);
        output.RestartStrip();
    }
}

float4 ps_main(line_vertex p) : SV_Target
{
    return float4(1.0, 1.0, 0.0, 1.0);
}
