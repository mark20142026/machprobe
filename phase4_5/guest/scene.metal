#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position; float4 normal; float4 uv; };
struct Uniforms { float4x4 mvp; float4x4 model; float4 tint; };
struct Raster { float4 position [[position]]; float3 normal; float2 uv; float4 tint; };
vertex Raster scene_vertex(const device Vertex *v [[buffer(0)]],constant Uniforms &u [[buffer(1)]],uint i [[vertex_id]]) {
    Raster r; r.position=u.mvp*v[i].position;
    r.normal=(u.model*float4(v[i].normal.xyz,0)).xyz;r.uv=v[i].uv.xy;r.tint=u.tint;return r;
}
fragment float4 scene_fragment(Raster r [[stage_in]],texture2d<float> tex [[texture(0)]]) {
    constexpr sampler sample(filter::nearest,address::repeat);
    float light=.25+.75*max(dot(normalize(r.normal),normalize(float3(.4,.8,1))),0.0);
    return float4(tex.sample(sample,r.uv).rgb*r.tint.rgb*light,1);
}
