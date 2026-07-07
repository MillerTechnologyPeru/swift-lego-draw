#version 450

layout(location = 0) in vec3 inNormal;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 outColor;

void main() {
    vec3 keyDir  = normalize(vec3( 1.0,  2.0,  1.5));
    vec3 fillDir = normalize(vec3(-1.0, -0.5, -1.0));
    vec3 n = normalize(inNormal);
    float key    = max(dot(n, keyDir),  0.0) * 0.75;
    float fill   = max(dot(n, fillDir), 0.0) * 0.25;
    float ambient = 0.2;
    vec3 rgb = inColor.rgb * (ambient + key + fill);
    outColor = vec4(rgb, inColor.a);
}
