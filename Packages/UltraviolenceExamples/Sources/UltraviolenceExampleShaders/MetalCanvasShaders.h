#pragma once

#import "Support.h"

typedef UV_ENUM(int, MetalCanvasSegmentType) {
    kMetalCanvasSegmentTypeLine = 0,
    kMetalCanvasSegmentTypeCubicCurve = 1,
};

// Line segment with two 2D endpoints
struct MetalCanvasLineSegment {
    simd_float2 start;
    simd_float2 end;
};

// Cubic bezier curve with 2D control points
struct MetalCanvasCubicCurve {
    simd_float2 start;
    simd_float2 control1;
    simd_float2 control2;
    simd_float2 end;
};

// Draw operation with color and segment index
struct MetalCanvasDrawOperation {
    simd_float4 color;
    float lineWidth;
    uint32_t segmentIndex;
    uint32_t segmentCount;
};

// Placeholder struct for mesh shader payload
struct MetalCanvasMeshPayload {
    uint32_t index;
};
