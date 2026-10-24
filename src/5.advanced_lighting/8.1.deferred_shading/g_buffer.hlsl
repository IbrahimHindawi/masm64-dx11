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

// the geometry pass: no lighting, only what the lighting pass will need
Texture2D diffuse_map : register(t0);
Texture2D specular_map : register(t1);
SamplerState linear_wrap : register(s0);

struct g_buffer
{
    float4 position : SV_Target0;   // world space; w = 1 where something was drawn
    float4 normal : SV_Target1;     // world space
    float4 albedo : SV_Target2;     // rgb colour, a specular strength
};

g_buffer ps_main(vs_out p)
{
    g_buffer g;
    g.position = float4(p.world, 1.0);
    g.normal = float4(normalize(p.normal), 0.0);
    g.albedo = float4(diffuse_map.Sample(linear_wrap, p.uv).rgb, specular_map.Sample(linear_wrap, p.uv).r);
    return g;
}
