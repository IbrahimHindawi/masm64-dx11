// The light source itself, as a small cube in one flat colour, so
// nothing done to the lighting ever darkens it.
#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view;
    float4x4 projection;
    float3 view_position;
};

cbuffer lamp : register(b1)
{
    float4 lamp_color;
};

float4 vs_main(float3 position : POSITION) : SV_Position
{
    return mul(projection, mul(view, mul(model, float4(position, 1.0))));
}

float4 ps_main() : SV_Target
{
    return lamp_color;
}
