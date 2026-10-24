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
    int gamma;
};

Texture2D albedo : register(t0);
SamplerState linear_wrap : register(s0);

float4 ps_main(vs_out p) : SV_Target
{
    // An _SRGB texture is already linear here; the plain one is not, which
    // is exactly the uncorrected mistake being shown.
    float3 color = albedo.Sample(linear_wrap, p.uv).rgb;
    float3 n = normalize(p.normal);
    float3 to_eye = normalize(view_position - p.world);

    float3 lit = 0.0;
    for (int i = 0; i < 4; i++)
    {
        float3 to_light = light_positions[i].xyz - p.world;
        float d = length(to_light);
        to_light /= d;
        float3 halfway = normalize(to_light + to_eye);
        float diffuse = max(dot(n, to_light), 0.0);
        float spec = pow(max(dot(n, halfway), 0.0), 64.0);
        float falloff = gamma ? 1.0 / (d * d) : 1.0 / d;
        lit += (diffuse * color + spec * 0.3) * light_colors[i].rgb * falloff;
    }
    return float4(lit, 1.0);
}
