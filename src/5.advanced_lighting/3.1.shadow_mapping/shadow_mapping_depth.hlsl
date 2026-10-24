// The shadow pass: positions into the light's clip space, and nothing
// else. The pixel shader writes no colour; only the depth buffer is bound.
#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view;         // the light's
    float4x4 projection;   // the light's
    float3 view_position;
};

float4 vs_main(float3 position : POSITION) : SV_Position
{
    return mul(projection, mul(view, mul(model, float4(position, 1.0))));
}

void ps_main()
{
}
