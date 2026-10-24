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

cbuffer emit : register(b2)
{
    float4 emit_color;   // w = 1: draw this colour unlit (a light cube)
};

Texture2D albedo : register(t0);
SamplerState linear_wrap : register(s0);

// two outputs: SV_Target0 goes to the first bound target, SV_Target1 to the second
struct bloom_out
{
    float4 color : SV_Target0;
    float4 bright : SV_Target1;
};

bloom_out ps_main(vs_out p)
{
    float3 color = emit_color.rgb;
    if (emit_color.w == 0.0)
    {
        float3 base = albedo.Sample(linear_wrap, p.uv).rgb;
        float3 n = normalize(p.normal);
        color = 0.02 * base;
        for (int i = 0; i < 4; i++)
        {
            float3 to_light = light_positions[i].xyz - p.world;
            float d = length(to_light);
            color += max(dot(n, to_light / d), 0.0) * base * light_colors[i].rgb / (d * d);
        }
    }
    bloom_out o;
    o.color = float4(color, 1.0);
    // perceived brightness; anything above 1 goes to the blur
    float brightness = dot(color, float3(0.2126, 0.7152, 0.0722));
    o.bright = float4(brightness > 1.0 ? color : 0.0, 1.0);
    return o;
}
