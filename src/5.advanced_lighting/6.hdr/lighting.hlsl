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

cbuffer lights : register(b1)
{
    float4 light_positions[4];
    float4 light_colors[4];
};

Texture2D albedo : register(t0);
SamplerState linear_wrap : register(s0);

float4 ps_main(vs_out p) : SV_Target
{
    float3 color = albedo.Sample(linear_wrap, p.uv).rgb;
    // seen from inside the tunnel
    float3 n = -normalize(p.normal);
    float3 lit = 0.0;
    for (int i = 0; i < 4; i++)
    {
        float3 to_light = light_positions[i].xyz - p.world;
        float d = length(to_light);
        lit += max(dot(n, to_light / d), 0.0) * color * light_colors[i].rgb / (d * d);
    }
    // no clamping: values far above 1 are kept, which is the point
    return float4(lit, 1.0);
}
