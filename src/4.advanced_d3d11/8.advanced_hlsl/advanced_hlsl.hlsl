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

// Shared by all four pixel shaders. Faces whose normal points towards
// the camera are cut away (clip), so the inside of each cube shows.
float4 shade(vs_out p, bool front, float3 color)
{
    float3 n = normalize(p.normal);
    float3 to_eye = normalize(view_position - p.world);
    clip(0.35 - dot(n, to_eye));
    // a little shading per face, so the walls can be told apart
    float3 c = color * (0.55 + 0.45 * abs(dot(n, normalize(float3(0.5, 0.8, 0.3)))));
    // SV_IsFrontFace: the cube's outside is its front, its inside the back
    if (!front)
    {
        float2 cell = floor(p.uv * 4.0);
        c *= fmod(cell.x + cell.y, 2.0) < 1.0 ? 0.25 : 0.45;
    }
    // SV_Position.x is in pixels: darken the left half of the window
    if (p.position.x < 640.0) c *= 0.6;
    return float4(c, 1.0);
}

float4 ps_main(vs_out p, bool front : SV_IsFrontFace) : SV_Target { return shade(p, front, float3(1.0, 0.2, 0.2)); }
float4 ps_green(vs_out p, bool front : SV_IsFrontFace) : SV_Target { return shade(p, front, float3(0.2, 1.0, 0.2)); }
float4 ps_blue(vs_out p, bool front : SV_IsFrontFace) : SV_Target { return shade(p, front, float3(0.2, 0.4, 1.0)); }
float4 ps_yellow(vs_out p, bool front : SV_IsFrontFace) : SV_Target { return shade(p, front, float3(1.0, 0.9, 0.2)); }
