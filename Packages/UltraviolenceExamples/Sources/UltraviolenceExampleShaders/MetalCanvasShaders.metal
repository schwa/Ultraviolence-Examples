#include <metal_stdlib>
#include "MetalCanvasShaders.h"

using namespace metal;

namespace MetalCanvas {

using LineSegment = MetalCanvasLineSegment;
using CubicCurve = MetalCanvasCubicCurve;
using DrawOperation = MetalCanvasDrawOperation;
using MeshPayload = MetalCanvasMeshPayload;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

// Convert from pixel coordinates to clip space
float2 pixelToClip(float2 pixel, float2 viewport) {
    return (pixel / viewport) * 2.0 - 1.0;
}

[[object]]
void metalCanvasObjectShader(uint objectID [[thread_position_in_grid]], object_data MetalCanvasMeshPayload& payload [[payload]], mesh_grid_properties mgp, constant DrawOperation* drawOperations [[buffer(0)]], constant uint32_t* segmentOffsets [[buffer(1)]]) {
    DrawOperation op = drawOperations[objectID];
    payload.index = objectID;

    // Dispatch one mesh threadgroup per segment
    mgp.set_threadgroups_per_grid(uint3(op.segmentCount, 1, 1));
}

[[mesh]]
void metalCanvasMeshShader(
    mesh<MetalCanvas::VertexOut, void, 4, 2, topology::triangle> output,
    const object_data MetalCanvasMeshPayload& payload [[payload]],
    uint meshID [[threadgroup_position_in_grid]],
    uint threadID [[thread_position_in_threadgroup]],
    constant DrawOperation *drawOperations [[buffer(0)]],
    constant uint32_t *segmentOffsets [[buffer(1)]],
    constant void *segments [[buffer(2)]],
    constant float2 &viewport [[buffer(3)]]
) {

    DrawOperation op = drawOperations[payload.index];
    uint32_t segmentIndex = op.segmentIndex + meshID;
    uint32_t segmentType = segmentOffsets[segmentIndex];

    // For now, only handle line segments
    if (segmentType != kMetalCanvasSegmentTypeLine) {
        if (threadID == 0) {
            output.set_primitive_count(0);
        }
        return;
    }

    // Read the line segment (all threads read the same data)
    constant LineSegment* lineSegments = (constant LineSegment*)segments;
    LineSegment line = lineSegments[segmentIndex];

    float2 start = line.start;
    float2 end = line.end;
    float2 dir = normalize(end - start);
    float2 normal = float2(-dir.y, dir.x);
    float halfWidth = op.lineWidth * 0.5;

    // Each thread computes one vertex (4 threads total)
    if (threadID < 4) {
        float2 v;
        switch (threadID) {
            case 0: v = start - normal * halfWidth; break;
            case 1: v = start + normal * halfWidth; break;
            case 2: v = end - normal * halfWidth; break;
            case 3: v = end + normal * halfWidth; break;
        }

        // Convert to clip space
        v = pixelToClip(v, viewport);
        v.y = -v.y;  // Flip Y coordinate

        output.set_vertex(threadID, VertexOut{float4(v, 0.0, 1.0), op.color});
    }

    // Thread 0 sets up indices and primitive count
    if (threadID == 0) {
        output.set_index(0, 0);
        output.set_index(1, 1);
        output.set_index(2, 2);
        output.set_index(3, 2);
        output.set_index(4, 1);
        output.set_index(5, 3);
        output.set_primitive_count(2);
    }
}

[[fragment]]
float4 metalCanvasFragmentShader(MetalCanvas::VertexOut in [[stage_in]]) {
    return in.color;
}
}
