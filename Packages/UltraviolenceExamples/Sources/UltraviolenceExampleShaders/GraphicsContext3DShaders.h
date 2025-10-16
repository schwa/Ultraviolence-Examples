#pragma once

#include <simd/simd.h>

struct GraphicsContext3DVertex {
    simd_float3 position;
    simd_float4 color;
};
