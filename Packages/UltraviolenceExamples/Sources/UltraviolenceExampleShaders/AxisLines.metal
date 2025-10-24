#include "UltraviolenceExampleShaders.h"
#include <metal_stdlib>
using namespace metal;

namespace AxisLines {

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    // Generate infinite axis lines in screen space
    // Each axis uses 6 vertices (2 triangles) to create a thick line quad
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant AxisLinesUniforms &uniforms [[buffer(0)]]) {
        VertexOut out;

        // Determine which axis (0=X, 1=Y, 2=Z) and which vertex in the quad (0-5)
        uint axisID = vertexID / 6;
        uint quadVertexID = vertexID % 6;

        // Define axis directions in world space
        float3 axisDir;
        float4 color;

        switch (axisID) {
        case 0: // X axis
            axisDir = float3(1, 0, 0);
            color = uniforms.xAxisColor;
            break;
        case 1: // Y axis
            axisDir = float3(0, 1, 0);
            color = uniforms.yAxisColor;
            break;
        case 2: // Z axis
            axisDir = float3(0, 0, 1);
            color = uniforms.zAxisColor;
            break;
        }

        // Origin in world space (with nudge)
        float3 origin = uniforms.nudge;

        // Transform origin to clip space
        float4 originClip = uniforms.mvpMatrix * float4(origin, 1.0);

        // Transform to clip space for direction
        float4 axisDirClip = uniforms.mvpMatrix * float4(origin + axisDir, 1.0);

        // Calculate screen-space direction
        float2 originNDC = originClip.xy / originClip.w;
        float2 axisDirNDC = axisDirClip.xy / axisDirClip.w;
        float2 lineDir = normalize(axisDirNDC - originNDC);

        // Perpendicular direction in screen space
        float2 perpDir = float2(-lineDir.y, lineDir.x);

        // Convert line width from pixels to NDC
        float2 lineWidthNDC = (uniforms.lineWidth / uniforms.viewportSize) * 2.0;
        float2 offset = perpDir * lineWidthNDC * 0.5;

        // Extend line to screen edges (use large value for "infinite")
        float extensionFactor = 1000.0;

        // Generate quad vertices (2 triangles)
        float2 positionNDC;
        float alongAxis; // -1 to +1 along axis

        switch (quadVertexID) {
        case 0: // Bottom-left
            positionNDC = originNDC - lineDir * extensionFactor - offset;
            alongAxis = -1.0;
            break;
        case 1: // Bottom-right
            positionNDC = originNDC - lineDir * extensionFactor + offset;
            alongAxis = -1.0;
            break;
        case 2: // Top-right
            positionNDC = originNDC + lineDir * extensionFactor + offset;
            alongAxis = 1.0;
            break;
        case 3: // Top-left (for second triangle)
            positionNDC = originNDC - lineDir * extensionFactor - offset;
            alongAxis = -1.0;
            break;
        case 4: // Top-right (for second triangle)
            positionNDC = originNDC + lineDir * extensionFactor + offset;
            alongAxis = 1.0;
            break;
        case 5: // Top-left far
            positionNDC = originNDC + lineDir * extensionFactor - offset;
            alongAxis = 1.0;
            break;
        }

        // Use origin's depth for all vertices
        out.position = float4(positionNDC * originClip.w, originClip.z, originClip.w);
        out.color = color;

        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        return in.color;
    }

} // namespace AxisLines
