#include <metal_stdlib>
#include "EdgeRenderingShaders.h"
#include "Support.h"

using namespace metal;

namespace EdgeRendering {

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    using MeshType = mesh<VertexOut, void, 256, 512, topology::triangle>;

    struct EdgeData {
        uint32_t startIndex;
        uint32_t endIndex;
    };

    // Helper functions

    float2 toScreen(float3 point3D, float4x4 viewProjection, float2 viewport) {
        float4 clipPos = viewProjection * float4(point3D, 1.0);
        if (abs(clipPos.w) < 1e-6) return float2(0, 0);
        float2 ndc = clipPos.xy / clipPos.w;
        return (ndc * 0.5 + 0.5) * viewport;
    }

    float3 toClip(float2 screenPos, float depth, float w, float2 viewport) {
        float2 ndc = (screenPos / viewport) * 2.0 - 1.0;
        return float3(ndc, depth);
    }

    int segmentCountForRadius(float radius) {
        if (radius < 2.0) return 3;
        if (radius < 5.0) return 4;
        if (radius < 10.0) return 6;
        if (radius < 20.0) return 8;
        return 12;
    }

    // Mesh Shader

    [[mesh, max_total_threads_per_threadgroup(1)]]
    void edgeRenderingMeshShader(
        MeshType mesh_out,
        uint edgeID [[thread_position_in_grid]],
        const device uchar* vertices [[buffer(0)]],
        const device EdgeData* edgeData [[buffer(1)]],
        constant BufferDescriptor& vertexDescriptor [[buffer(2)]],
        const device EdgeRenderingUniforms& uniforms [[buffer(3)]]
    ) {
        EdgeData edge = edgeData[edgeID];
        uint startIdx = edge.startIndex;
        uint endIdx = edge.endIndex;

        float3 startPoint = load_at<float3>(vertices, vertexDescriptor, startIdx);
        float3 endPoint = load_at<float3>(vertices, vertexDescriptor, endIdx);

        // Determine edge color based on colorization mode
        float4 edgeColor;
        if (uniforms.colorizeByTriangle) {
            // Color based on edge index
            const float4 colors[8] = {
                float4(1, 0, 0, 1),  // Red
                float4(0, 1, 0, 1),  // Green
                float4(0, 0, 1, 1),  // Blue
                float4(1, 1, 0, 1),  // Yellow
                float4(1, 0, 1, 1),  // Magenta
                float4(0, 1, 1, 1),  // Cyan
                float4(1, 0.5, 0, 1), // Orange
                float4(0.5, 0, 1, 1)  // Purple
            };
            edgeColor = colors[edgeID % 8];
        } else {
            edgeColor = uniforms.edgeColor;
        }

        // Get clip space coordinates for depth
        float4 startClip = uniforms.viewProjection * float4(startPoint, 1.0);
        float4 endClip = uniforms.viewProjection * float4(endPoint, 1.0);

        // Cull edges behind the camera or with invalid w
        if (startClip.w <= 0.0 || endClip.w <= 0.0) {
            mesh_out.set_primitive_count(0);
            return;
        }

        // Transform to screen space
        float2 startScreen = toScreen(startPoint, uniforms.viewProjection, uniforms.viewport);
        float2 endScreen = toScreen(endPoint, uniforms.viewProjection, uniforms.viewport);

        // Cull degenerate edges (too short in screen space)
        float screenLength = distance(startScreen, endScreen);
        if (screenLength < 0.5) {
            mesh_out.set_primitive_count(0);
            return;
        }

        float startDepth = startClip.z / startClip.w;
        float endDepth = endClip.z / endClip.w;

        // Calculate line direction and perpendicular
        float2 dir = normalize(endScreen - startScreen);
        float2 perp = float2(-dir.y, dir.x);

        float radius = uniforms.lineWidth / 2.0;

        uint vertexCount = 0;
        uint primitiveCount = 0;

        // Main line segment (quad)
        float2 p0 = startScreen - perp * radius;
        float2 p1 = startScreen + perp * radius;
        float2 p2 = endScreen + perp * radius;
        float2 p3 = endScreen - perp * radius;

        mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, startDepth, startClip.w, uniforms.viewport), 1.0), edgeColor});
        mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, startDepth, startClip.w, uniforms.viewport), 1.0), edgeColor});
        mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, endDepth, endClip.w, uniforms.viewport), 1.0), edgeColor});
        mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, endDepth, endClip.w, uniforms.viewport), 1.0), edgeColor});

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
        primitiveCount++;

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
        primitiveCount++;

        vertexCount += 4;

        // Start cap (round)
        int segments = segmentCountForRadius(radius);
        segments = min(segments, 16);

        float startAngle = atan2(dir.y, dir.x) + M_PI_F / 2.0;

        uint startCenterVertex = vertexCount++;
        mesh_out.set_vertex(startCenterVertex, VertexOut{float4(toClip(startScreen, startDepth, startClip.w, uniforms.viewport), 1.0), edgeColor});

        for (int i = 0; i <= segments; i++) {
            float t = float(i) / float(segments);
            float angle = startAngle + M_PI_F * t;
            float2 offset = float2(cos(angle), sin(angle)) * radius;
            float2 p = startScreen + offset;

            mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, startDepth, startClip.w, uniforms.viewport), 1.0), edgeColor});

            if (i > 0) {
                mesh_out.set_index(primitiveCount * 3 + 0, startCenterVertex);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                primitiveCount++;
            }
            vertexCount++;
        }

        // End cap (round)
        float endAngle = atan2(dir.y, dir.x) - M_PI_F / 2.0;

        uint endCenterVertex = vertexCount++;
        mesh_out.set_vertex(endCenterVertex, VertexOut{float4(toClip(endScreen, endDepth, endClip.w, uniforms.viewport), 1.0), edgeColor});

        for (int i = 0; i <= segments; i++) {
            float t = float(i) / float(segments);
            float angle = endAngle + M_PI_F * t;
            float2 offset = float2(cos(angle), sin(angle)) * radius;
            float2 p = endScreen + offset;

            mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, endDepth, endClip.w, uniforms.viewport), 1.0), edgeColor});

            if (i > 0) {
                mesh_out.set_index(primitiveCount * 3 + 0, endCenterVertex);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                primitiveCount++;
            }
            vertexCount++;
        }

        mesh_out.set_primitive_count(primitiveCount);
    }

    // Fragment Shader

    [[fragment]] float4 edgeRenderingFragmentShader(
        VertexOut in [[stage_in]]
    ) {
        return in.color;
    }
}
