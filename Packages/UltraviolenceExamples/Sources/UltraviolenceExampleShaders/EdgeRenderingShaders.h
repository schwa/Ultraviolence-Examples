#pragma once

#include <simd/simd.h>

struct EdgeRenderingUniforms {
    simd_float4x4 viewProjection;
    simd_float2 viewport;
    float lineWidth;
    int colorizeByTriangle;
    simd_float4 edgeColor;
};
