#pragma once

#include <simd/simd.h>

struct GrassPointData {
    simd_float3 position;
    simd_float3 normal;
    simd_float3 tangent;
    simd_float3 bitangent;
    float bladeLength;
    int droopEnabled;
    float bladeWidthMultiplier;
    int bladesPerPoint;
};

struct GrassUniforms {
    simd_float4x4 modelViewProjection;
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
};

struct GrassObjectPayload {
    uint32_t pointIndex;
};
