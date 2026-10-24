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

cbuffer explode : register(b1)
{
    float amount;   // 0: whole, 1: every triangle pushed out
};

Texture2D diffuse_map : register(t0);
SamplerState linear_wrap : register(s0);

// vs_main only moves to world space; the geometry shader projects, once
// it has moved the triangle.
[maxvertexcount(3)]
void gs_main(triangle vs_out input[3], inout TriangleStream<vs_out> output)
{
    float3 face_normal = normalize(cross(input[1].world - input[0].world, input[2].world - input[0].world));
    float3 offset = face_normal * amount * 0.5;
    for (int i = 0; i < 3; i++)
    {
        vs_out v = input[i];
        v.world += offset;
        v.position = mul(projection, mul(view, float4(v.world, 1.0)));
        output.Append(v);
    }
}

float4 ps_main(vs_out p) : SV_Target
{
    float3 n = normalize(p.normal);
    float light = 0.35 + 0.65 * max(dot(n, normalize(float3(0.4, 0.8, 0.6))), 0.0);
    return float4(diffuse_map.Sample(linear_wrap, p.uv).rgb * light, 1.0);
}
