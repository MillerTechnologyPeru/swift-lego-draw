#!/bin/sh
# Compiles the GLSL shaders in this directory to SPIR-V bytecode.
# Requires `glslc` (from the Vulkan SDK / shaderc) or `glslangValidator` on PATH.
# Run this after editing triangle.vert/triangle.frag; the .spv output is a
# bundled resource loaded at runtime by LDrawVulkanOffscreenRenderer.
set -e
cd "$(dirname "$0")"

if command -v glslc >/dev/null 2>&1; then
    glslc triangle.vert -o triangle.vert.spv
    glslc triangle.frag -o triangle.frag.spv
elif command -v glslangValidator >/dev/null 2>&1; then
    glslangValidator -V triangle.vert -o triangle.vert.spv
    glslangValidator -V triangle.frag -o triangle.frag.spv
else
    echo "error: neither glslc nor glslangValidator found on PATH (install the Vulkan SDK)" >&2
    exit 1
fi

echo "Compiled triangle.vert.spv and triangle.frag.spv"
