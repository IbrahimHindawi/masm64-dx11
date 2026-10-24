cbuffer frame : register(b0)
{
    float4 tint;
};

struct vs_in
{
    float3 position : POSITION;
    float3 color : COLOR;
};

// What the vertex shader hands on. Anything beyond SV_Position is
// interpolated across the triangle on its way to the pixel shader.
struct vs_out
{
    float4 position : SV_Position;
    float3 color : COLOR;
};

vs_out vs_main(vs_in v)
{
    vs_out o;
    o.position = float4(v.position, 1.0);
    o.color = v.color;
    return o;
}

float4 ps_main(vs_out p) : SV_Target
{
    return float4(p.color * tint.rgb, 1.0);
}
