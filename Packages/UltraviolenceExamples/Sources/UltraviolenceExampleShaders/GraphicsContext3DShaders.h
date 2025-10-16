#pragma once

#include <simd/simd.h>

struct GraphicsContext3DVertex {
    simd_float3 position;
    simd_float4 color;
};

struct LineJoinGPUData {
    simd_float3 prevPoint;      // Start of half-segment-A
    simd_float3 joinPoint;      // Center join point
    simd_float3 nextPoint;      // End of half-segment-B
    float lineWidth;
    uint32_t joinStyle;         // 0=miter, 1=round, 2=bevel
    uint32_t capStyle;          // 0=none, 1=butt, 2=round, 3=square
    uint32_t isStartCap;        // 1 if start cap needed
    uint32_t isEndCap;          // 1 if end cap needed
    simd_float4 color;
    float miterLimit;
    float _padding[3];          // Align to 16 bytes
};

struct LineJoinUniforms {
    simd_float4x4 viewProjection;
    simd_float2 viewport;
    float _padding[2];          // Align to 16 bytes
};
