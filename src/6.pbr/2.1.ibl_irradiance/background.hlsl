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

// the environment behind everything, tone mapped like the spheres
TextureCube env : register(t0);
SamplerState linear_clamp : register(s1);

struct sky_vertex
{
    float4 position : SV_Position;
    float3 direction : DIRECTION;
};

sky_vertex vs_main(float3 position : POSITION)
{
    sky_vertex o;
    o.direction = position;
    // the view without its translation, and z = w: the far plane, as in 4.6.1
    float4x4 rotation = view;
    rotation[0][3] = 0.0;
    rotation[1][3] = 0.0;
    rotation[2][3] = 0.0;
    o.position = mul(projection, mul(rotation, float4(position, 1.0))).xyww;
    return o;
}

float4 ps_main(sky_vertex p) : SV_Target
{
    float3 color = env.SampleLevel(linear_clamp, p.direction, 0).rgb;
    return float4(color / (color + 1.0), 1.0);
}
