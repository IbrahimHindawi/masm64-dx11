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

// SSAO's geometry pass works in view space: the camera at the origin,
// looking down -z, which is where the occlusion test is done.
cbuffer surface : register(b1)
{
    float flip_normals;   // -1 inside the room
};

struct view_vertex
{
    float4 position : SV_Position;
    float3 view_pos : VIEWPOS;
    float3 normal : NORMAL;
};

struct g_buffer
{
    float4 position : SV_Target0;   // w = 1 where something was drawn
    float4 normal : SV_Target1;
};

view_vertex vs_main(float3 position : POSITION, float3 normal : NORMAL)
{
    view_vertex o;
    float4 view_pos = mul(view, mul(model, float4(position, 1.0)));
    o.view_pos = view_pos.xyz;
    o.position = mul(projection, view_pos);
    o.normal = mul((float3x3)view, mul((float3x3)normal_matrix, normal * flip_normals));
    return o;
}

g_buffer ps_main(view_vertex p)
{
    g_buffer g;
    g.position = float4(p.view_pos, 1.0);
    g.normal = float4(normalize(p.normal), 0.0);
    return g;
}
