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

cbuffer lighting : register(b1)
{
    float3 light_position;   // view space
    int mode;                // 0 lit with SSAO, 1 SSAO alone, 2 lit without
};

Texture2D positions : register(t0);
Texture2D normals : register(t1);
Texture2D<float> occlusion : register(t2);

float4 ps_main(fullscreen_vertex p) : SV_Target
{
    int3 pixel = int3(p.position.xy, 0);
    float ao = occlusion.Load(pixel);
    if (mode == 1) return float4(ao.xxx, 1.0);
    if (mode == 2) ao = 1.0;

    float4 here = positions.Load(pixel);
    if (here.w == 0.0) return float4(0.0, 0.0, 0.0, 1.0);
    float3 n = normalize(normals.Load(pixel).xyz);
    float3 albedo = 0.95;
    float3 light_color = float3(0.2, 0.2, 0.7);

    // in view space the eye is at the origin
    float3 to_eye = normalize(-here.xyz);
    float3 to_light = light_position - here.xyz;
    float d = length(to_light);
    to_light /= d;
    float3 halfway = normalize(to_light + to_eye);
    float falloff = 1.0 / (1.0 + 0.09 * d + 0.032 * d * d);

    float3 ambient = 0.3 * albedo * ao;
    float3 diffuse = max(dot(n, to_light), 0.0) * albedo * light_color;
    float3 specular = pow(max(dot(n, halfway), 0.0), 8.0) * light_color;
    return float4(ambient + (diffuse + specular) * falloff, 1.0);
}
