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

struct point_light
{
    float3 position;
    float3 color;
};

cbuffer lights : register(b1)
{
    float3 sun_direction;
    float shininess;
    float3 sun_color;
    float3 spot_position;
    float spot_inner_cos;
    float3 spot_direction;
    float spot_outer_cos;
    point_light points[4];
};

Texture2D diffuse_map : register(t0);
Texture2D specular_map : register(t1);
SamplerState linear_wrap : register(s0);

struct surface
{
    float3 position;
    float3 normal;
    float3 to_eye;
    float3 albedo;
    float3 shine;
};

// One light arriving from `to_light` with `color`: ambient, diffuse and
// specular, as in 4.1. Ambient is a twentieth of the colour.
float3 phong(surface s, float3 to_light, float3 color)
{
    float3 ambient = 0.05 * color * s.albedo;
    float3 diffuse = 0.8 * color * max(dot(s.normal, to_light), 0.0) * s.albedo;
    float3 specular = color * pow(max(dot(s.to_eye, reflect(-to_light, s.normal)), 0.0), shininess) * s.shine;
    return ambient + diffuse + specular;
}

float attenuation(float3 from, float3 to)
{
    float d = length(to - from);
    return 1.0 / (1.0 + 0.09 * d + 0.032 * d * d);
}

float4 ps_main(vs_out p) : SV_Target
{
    surface s;
    s.position = p.world;
    s.normal = normalize(p.normal);
    s.to_eye = normalize(view_position - p.world);
    s.albedo = diffuse_map.Sample(linear_wrap, p.uv).rgb;
    s.shine = specular_map.Sample(linear_wrap, p.uv).rgb;

    float3 color = phong(s, normalize(-sun_direction), sun_color);

    for (int i = 0; i < 4; i++)
    {
        float3 to_light = normalize(points[i].position - s.position);
        color += phong(s, to_light, points[i].color) * attenuation(s.position, points[i].position);
    }

    float3 to_spot = normalize(spot_position - s.position);
    float cone = saturate((dot(to_spot, -spot_direction) - spot_outer_cos) / (spot_inner_cos - spot_outer_cos));
    color += phong(s, to_spot, float3(1.0, 1.0, 1.0)) * attenuation(s.position, spot_position) * cone;

    return float4(color, 1.0);
}
