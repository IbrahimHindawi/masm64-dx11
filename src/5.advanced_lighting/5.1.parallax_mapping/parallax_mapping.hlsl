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

struct tangent_in
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD;
    float3 tangent : TANGENT;
};

struct tangent_out
{
    float4 position : SV_Position;
    float3 world : WORLD;
    float2 uv : TEXCOORD;
    float3 t : TANGENT;
    float3 b : BITANGENT;
    float3 n : NORMAL;
};

tangent_out vs_main(tangent_in v)
{
    tangent_out o;
    float4 world = mul(model, float4(v.position, 1.0));
    o.world = world.xyz;
    o.position = mul(projection, mul(view, world));
    o.uv = v.uv;
    o.n = normalize(mul((float3x3)normal_matrix, v.normal));
    // Gram-Schmidt: make the tangent exactly perpendicular to the normal
    float3 t = normalize(mul((float3x3)model, v.tangent));
    o.t = normalize(t - dot(t, o.n) * o.n);
    // The map's y points down the image, the way v increases: the files are
    // made for GL, which shows images upside down, so seen the right way up
    // their +y is down. For a surface facing the viewer that is
    // cross(tangent, normal).
    o.b = cross(o.t, o.n);
    return o;
}

cbuffer light : register(b1)
{
    float3 light_position;
    int mode;
};

Texture2D albedo : register(t0);
Texture2D normal_map : register(t1);
Texture2D depth_map : register(t2);
SamplerState linear_wrap : register(s0);

static const float depth_scale = 0.1;

// `to_eye` is in tangent space: z out of the surface
float2 parallax(float2 uv, float3 to_eye)
{
    if (mode == 1) return uv;
    // the whole shift that the deepest point (depth 1) would cause
    // tangent space x and y run the way u and v do
    float2 full_shift = to_eye.xy / to_eye.z * depth_scale;
    if (mode == 2)
    {
        return uv - full_shift * depth_map.Sample(linear_wrap, uv).r;
    }

    // seen head on, few layers are needed; at a grazing angle, many
    float layers = lerp(32.0, 8.0, abs(to_eye.z));
    float layer_depth = 1.0 / layers;
    float2 step = full_shift / layers;
    float2 current_uv = uv;
    float surface = depth_map.SampleLevel(linear_wrap, current_uv, 0).r;
    float ray = 0.0;
    [loop]
    while (ray < surface)
    {
        current_uv -= step;
        surface = depth_map.SampleLevel(linear_wrap, current_uv, 0).r;
        ray += layer_depth;
    }
    if (mode == 3) return current_uv;

    // the ray crossed the surface between the last two layers: find where
    float2 previous_uv = current_uv + step;
    float after = surface - ray;
    float before = depth_map.SampleLevel(linear_wrap, previous_uv, 0).r - (ray - layer_depth);
    float weight = after / (after - before);
    return lerp(current_uv, previous_uv, weight);
}

float4 ps_main(tangent_out p) : SV_Target
{
    float3x3 tbn = float3x3(normalize(p.t), normalize(p.b), normalize(p.n));
    // tbn's rows are the axes, so mul(tbn, v) projects onto them: world -> tangent
    float3 to_eye = normalize(mul(tbn, view_position - p.world));
    float2 uv = parallax(p.uv, to_eye);
    // shifted off the edge of the wall: nothing there
    if (mode != 1 && (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)) discard;

    float3 color = albedo.Sample(linear_wrap, uv).rgb;
    float3 n = normalize(mul(normal_map.Sample(linear_wrap, uv).rgb * 2.0 - 1.0, tbn));
    float3 to_light = normalize(light_position - p.world);
    float3 halfway = normalize(to_light + normalize(view_position - p.world));
    float diffuse = max(dot(n, to_light), 0.0);
    float spec = pow(max(dot(n, halfway), 0.0), 32.0);
    return float4((0.1 + diffuse) * color + 0.2 * spec, 1.0);
}
