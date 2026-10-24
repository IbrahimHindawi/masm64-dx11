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

cbuffer shadow : register(b1)
{
    float4x4 faces[6];
    float3 light_position;
    float far_plane;
};

struct face_vertex
{
    float4 position : SV_Position;
    float3 world : WORLD;
    uint face : SV_RenderTargetArrayIndex;   // which slice of the cubemap
};

float4 vs_main(float3 position : POSITION) : WORLD
{
    return mul(model, float4(position, 1.0));
}

// every triangle, six times: once into each face, through that face's view
[maxvertexcount(18)]
void gs_main(triangle float4 world[3] : WORLD, inout TriangleStream<face_vertex> output)
{
    for (uint face = 0; face < 6; face++)
    {
        for (int i = 0; i < 3; i++)
        {
            face_vertex v;
            v.world = world[i].xyz;
            v.position = mul(faces[face], world[i]);
            v.face = face;
            output.Append(v);
        }
        output.RestartStrip();
    }
}

// distance to the light, 0..1 over the far plane, written as the depth
float ps_main(face_vertex p) : SV_Depth
{
    return length(p.world - light_position) / far_plane;
}
