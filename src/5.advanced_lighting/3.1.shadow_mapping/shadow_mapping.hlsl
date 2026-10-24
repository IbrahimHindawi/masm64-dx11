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

cbuffer shadow : register(b1)
{
    float4x4 light_space;
    float3 light_direction;  // where the sunlight travels
};

Texture2D albedo : register(t0);
Texture2D<float> shadow_map : register(t1);
SamplerState linear_wrap : register(s0);
SamplerComparisonState shadow_compare : register(s1);

// 1 lit, 0 shadowed, and between at the edges.
float lit_fraction(float3 world)
{
    float4 clip = mul(light_space, float4(world, 1.0));
    float3 ndc = clip.xyz / clip.w;
    // past the far end of the light's box: nothing there to cast a shadow
    if (ndc.z > 1.0) return 1.0;
    // clip space y is up, texture v is down
    float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

    float w, h;
    shadow_map.GetDimensions(w, h);
    float2 texel = 1.0 / float2(w, h);
    float sum = 0.0;
    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            sum += shadow_map.SampleCmpLevelZero(shadow_compare, uv + float2(x, y) * texel, ndc.z);
        }
    }
    return sum / 9.0;
}

float4 ps_main(vs_out p) : SV_Target
{
    float3 color = albedo.Sample(linear_wrap, p.uv).rgb;
    float3 n = normalize(p.normal);
    float3 to_light = -light_direction;
    float3 to_eye = normalize(view_position - p.world);
    float3 halfway = normalize(to_light + to_eye);

    float diffuse = max(dot(n, to_light), 0.0);
    float spec = pow(max(dot(n, halfway), 0.0), 64.0);
    float lit = lit_fraction(p.world);
    return float4((0.15 + lit * (diffuse + 0.3 * spec)) * color, 1.0);
}
