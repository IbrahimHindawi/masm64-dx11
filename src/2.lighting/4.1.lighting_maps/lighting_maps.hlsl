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

cbuffer light : register(b1)
{
    float3 light_position;
    float shininess;
    float3 light_ambient;
    float3 light_diffuse;
    float3 light_specular;
};

Texture2D diffuse_map : register(t0);
Texture2D specular_map : register(t1);
SamplerState linear_wrap : register(s0);

float4 ps_main(vs_out p) : SV_Target
{
    float3 albedo = diffuse_map.Sample(linear_wrap, p.uv).rgb;
    float3 shine = specular_map.Sample(linear_wrap, p.uv).rgb;

    float3 n = normalize(p.normal);
    float3 to_light = normalize(light_position - p.world);
    float3 to_eye = normalize(view_position - p.world);

    float3 ambient = light_ambient * albedo;
    float3 diffuse = light_diffuse * max(dot(n, to_light), 0.0) * albedo;
    float3 specular = light_specular * pow(max(dot(to_eye, reflect(-to_light, n)), 0.0), shininess) * shine;

    return float4(ambient + diffuse + specular, 1.0);
}
