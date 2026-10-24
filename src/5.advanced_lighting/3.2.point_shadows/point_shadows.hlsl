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

cbuffer shadow : register(b1)
{
    float4x4 faces[6];
    float3 light_position;
    float far_plane;
};

cbuffer surface : register(b2)
{
    float flip_normals;
};

Texture2D albedo : register(t0);
TextureCube<float> shadow_map : register(t1);
SamplerState linear_wrap : register(s0);
SamplerComparisonState shadow_compare : register(s1);

struct vs_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

struct vs_out
{
    float4 position : SV_Position;
    float3 world : WORLD;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
};

// directions to spread the shadow samples along
static const float3 disc[20] =
{
    float3(1, 1, 1), float3(1, -1, 1), float3(-1, -1, 1), float3(-1, 1, 1),
    float3(1, 1, -1), float3(1, -1, -1), float3(-1, -1, -1), float3(-1, 1, -1),
    float3(1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0), float3(-1, 1, 0),
    float3(1, 0, 1), float3(-1, 0, 1), float3(1, 0, -1), float3(-1, 0, -1),
    float3(0, 1, 1), float3(0, -1, 1), float3(0, -1, -1), float3(0, 1, -1),
};

vs_out vs_main(vs_in v)
{
    vs_out o;
    float4 world = mul(model, float4(v.position, 1.0));
    o.world = world.xyz;
    o.position = mul(projection, mul(view, world));
    o.normal = mul((float3x3)normal_matrix, v.normal * flip_normals);
    o.uv = v.uv;
    return o;
}

float lit_fraction(float3 world)
{
    float3 from_light = world - light_position;
    float distance = length(from_light) / far_plane;
    float bias = 0.002;
    // farther from the eye, a wider disc: softer where detail is lost anyway
    float radius = (1.0 + length(view_position - world) / far_plane) / 25.0;
    float sum = 0.0;
    for (int i = 0; i < 20; i++)
    {
        sum += shadow_map.SampleCmpLevelZero(shadow_compare, from_light + disc[i] * radius * length(from_light), distance - bias);
    }
    return sum / 20.0;
}

float4 ps_main(vs_out p) : SV_Target
{
    float3 color = albedo.Sample(linear_wrap, p.uv).rgb;
    float3 n = normalize(p.normal);
    float3 to_light = normalize(light_position - p.world);
    float3 to_eye = normalize(view_position - p.world);
    float3 halfway = normalize(to_light + to_eye);

    float diffuse = max(dot(n, to_light), 0.0);
    float spec = pow(max(dot(n, halfway), 0.0), 64.0);
    float lit = lit_fraction(p.world);
    return float4((0.15 + lit * (diffuse + 0.3 * spec)) * color, 1.0);
}
