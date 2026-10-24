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

cbuffer ssao : register(b1)
{
    float4 kernel[64];
};

Texture2D positions : register(t0);
Texture2D normals : register(t1);
Texture2D noise : register(t2);
SamplerState point_clamp : register(s0);

static const float radius = 0.5;
static const float bias = 0.025;

float ps_main(fullscreen_vertex p) : SV_Target
{
    int3 pixel = int3(p.position.xy, 0);
    float4 here = positions.Load(pixel);
    if (here.w == 0.0) return 1.0;
    float3 n = normalize(normals.Load(pixel).xyz);

    // Load reads one texel by integer coordinates: the noise repeats every
    // four pixels, no sampler involved
    float3 random = noise.Load(int3(pixel.xy % 4, 0)).xyz;
    // a tangent frame around the normal, turned by the random vector
    float3 tangent = normalize(random - n * dot(random, n));
    float3 bitangent = cross(n, tangent);
    float3x3 tbn = float3x3(tangent, bitangent, n);

    float occluded = 0.0;
    for (int i = 0; i < 64; i++)
    {
        float3 sample_pos = here.xyz + mul(kernel[i].xyz, tbn) * radius;
        // where on screen that point is, and what the g-buffer has there
        float4 clip = mul(projection, float4(sample_pos, 1.0));
        float2 uv = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        float stored_z = positions.SampleLevel(point_clamp, uv, 0).z;
        // view space looks down -z, so nearer means a larger z; surfaces
        // far outside the radius should not count, hence the range falloff
        float in_range = smoothstep(0.0, 1.0, radius / abs(here.z - stored_z));
        occluded += (stored_z >= sample_pos.z + bias ? 1.0 : 0.0) * in_range;
    }
    return 1.0 - occluded / 64.0;
}
