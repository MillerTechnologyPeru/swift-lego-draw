#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec4 inColor;

layout(binding = 0) uniform Uniforms {
    mat4 modelViewProjection;
    mat4 normalMatrix;
} ubo;

layout(location = 0) out vec3 outNormal;
layout(location = 1) out vec4 outColor;

void main() {
    gl_Position = ubo.modelViewProjection * vec4(inPosition, 1.0);
    outNormal = normalize((ubo.normalMatrix * vec4(inNormal, 0.0)).xyz);
    outColor = inColor;
}
