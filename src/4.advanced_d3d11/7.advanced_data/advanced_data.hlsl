#pragma pack_matrix(row_major)

cbuffer transforms : register(b0)
{
    float4x4 view;
    float4x4 projection;
};

struct water_vertex
{
    float4 position : SV_Position;
    float3 color : COLOR;
};

// POSITION comes from vertex buffer slot 0 and COLOR from slot 1; the
// shader cannot tell, the input layout joins them.
water_vertex vs_main(float3 position : POSITION, float3 color : COLOR)
{
    water_vertex o;
    o.position = mul(projection, mul(view, float4(position, 1.0)));
    // Crests a little brighter, so the motion reads even in wireframe.
    o.color = color * (0.8 + position.y);
    return o;
}

float4 ps_main(water_vertex p) : SV_Target
{
    return float4(p.color, 1.0);
}
