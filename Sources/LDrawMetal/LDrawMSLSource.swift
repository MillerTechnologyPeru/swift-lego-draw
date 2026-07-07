#if canImport(Metal)
let LDrawMSLSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float4 color;
};

struct Uniforms {
    float4x4 modelViewProjection;
    float4x4 normalMatrix;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.modelViewProjection * float4(in.position, 1.0);
    out.worldNormal = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float3 keyDir  = normalize(float3( 1.0,  2.0,  1.5));
    float3 fillDir = normalize(float3(-1.0, -0.5, -1.0));

    float3 n = normalize(in.worldNormal);
    float key    = max(dot(n, keyDir),  0.0) * 0.75;
    float fill   = max(dot(n, fillDir), 0.0) * 0.25;
    float ambient = 0.2;

    float3 rgb = in.color.rgb * (ambient + key + fill);
    return float4(rgb, in.color.a);
}
"""
#endif
