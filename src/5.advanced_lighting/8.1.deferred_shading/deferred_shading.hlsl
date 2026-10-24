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

// One triangle covering the screen, made from SV_VertexID alone: no
// vertex buffer, no input layout. uv runs 0..1 across and down the screen,
// and the parts of the triangle past the edges are clipped away.
struct fullscreen_vertex
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD;
};

fullscreen_vertex vs_main(uint id : SV_VertexID)
{
    fullscreen_vertex o;
    o.uv = float2((id << 1) & 2, id & 2);
    o.position = float4(o.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

struct point_light
{
    float4 position;
    float4 color;
};

cbuffer lights : register(b1)
{
    point_light lights[32];
    int view_mode;
};

Texture2D positions : register(t0);
Texture2D normals : register(t1);
Texture2D albedo_spec : register(t2);

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    // one texel per pixel, so read it directly by its coordinates
    int3 pixel = int3(p.position.xy, 0);
    float4 position = positions.Load(pixel);
    float3 n = normals.Load(pixel).xyz;
    float4 surface = albedo_spec.Load(pixel);
    if (view_mode == 1) return float4(frac(abs(position.xyz)), 1.0);
    if (view_mode == 2) return float4(n * 0.5 + 0.5, 1.0);
    if (view_mode == 3) return float4(surface.rgb, 1.0);
    if (view_mode == 4) return float4(surface.aaa, 1.0);
    // nothing was drawn here: the background
    if (position.w == 0.0) return float4(0.0, 0.0, 0.0, 1.0);

    float3 to_eye = normalize(view_position - position.xyz);
    float3 color = 0.1 * surface.rgb;
    for (int i = 0; i < 32; i++)
    {
        float3 to_light = lights[i].position.xyz - position.xyz;
        float d = length(to_light);
        to_light /= d;
        float3 halfway = normalize(to_light + to_eye);
        float falloff = 1.0 / (1.0 + 0.7 * d + 1.8 * d * d);
        float3 diffuse = max(dot(n, to_light), 0.0) * surface.rgb;
        float3 specular = pow(max(dot(n, halfway), 0.0), 16.0) * surface.a;
        color += (diffuse + specular) * lights[i].color.rgb * falloff;
    }
    return float4(color, 1.0);
}
