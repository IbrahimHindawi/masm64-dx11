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

struct tangent_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
    float3 tangent : TANGENT;
};

struct tangent_out
{
    float4 position : SV_Position;
    float3 world : WORLD;
    float2 uv : TEXCOORD;
    float3 t : TANGENT;
    float3 b : BITANGENT;
    float3 n : NORMAL;
};

tangent_out vs_main(tangent_in v)
{
    tangent_out o;
    float4 world = mul(model, float4(v.position, 1.0));
    o.world = world.xyz;
    o.position = mul(projection, mul(view, world));
    o.uv = v.uv;
    o.n = normalize(mul((float3x3)normal_matrix, v.normal));
    // Gram-Schmidt: make the tangent exactly perpendicular to the normal
    float3 t = normalize(mul((float3x3)model, v.tangent));
    o.t = normalize(t - dot(t, o.n) * o.n);
    // The map's y points up the image, the way v decreases. For a surface
    // facing the viewer that is cross(normal, tangent). (GL's v runs up,
    // which is why LearnOpenGL's bitangent comes out the other way.)
    o.b = cross(o.n, o.t);
    return o;
}

cbuffer light : register(b1)
{
    float3 light_position;
    int use_map;
};

Texture2D albedo : register(t0);
Texture2D normal_map : register(t1);
SamplerState linear_wrap : register(s0);

float4 ps_main(tangent_out p) : SV_Target
{
    float3 color = albedo.Sample(linear_wrap, p.uv).rgb;
    float3 n = normalize(p.n);
    if (use_map)
    {
        float3 tangent_normal = normal_map.Sample(linear_wrap, p.uv).rgb * 2.0 - 1.0;
        float3x3 tbn = float3x3(normalize(p.t), normalize(p.b), n);
        // tbn's rows are the axes, so this is t * x + b * y + n * z
        n = normalize(mul(tangent_normal, tbn));
    }
    float3 to_light = normalize(light_position - p.world);
    float3 to_eye = normalize(view_position - p.world);
    float3 halfway = normalize(to_light + to_eye);
    float diffuse = max(dot(n, to_light), 0.0);
    float spec = pow(max(dot(n, halfway), 0.0), 32.0);
    return float4((0.1 + diffuse) * color + 0.2 * spec, 1.0);
}
