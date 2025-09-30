#import <metal_stdlib>
#import <simd/simd.h>

#import "Support.h"

using namespace metal;

namespace HitTest {

    struct Vertex {
        simd_float3 position ATTRIBUTE(0);
        simd_float3 normal ATTRIBUTE(1);
        simd_float2 textureCoordinate ATTRIBUTE(2);
    };

    struct Fragment {
        float4 position [[position]]; // in projection space
        float3 worldPosition;
        float3 barycentric;
        uint primitiveID;
        uint instanceID;
    };

    struct FragmentOutput {
        int geometryID [[color(0)]];
        int instanceID [[color(1)]];
        int triangleID [[color(2)]];
        float depth [[color(3)]];
        float4 triangleCoordinates [[color(4)]];
    };

    // Vertex shader - similar to BlinnPhong but with barycentric coordinates
    [[vertex]] Fragment vertex_main(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        Vertex in [[stage_in]],
        constant Transforms *transforms [[buffer(1)]]
    ) {
        Fragment out;

        const float4 position = float4(in.position, 1.0);
        const float4 modelVertex = transforms[instanceID].modelViewMatrix * position;
        out.position = transforms[instanceID].modelViewProjectionMatrix * position;
        out.worldPosition = float3(modelVertex) / modelVertex.w;

        // Calculate barycentric coordinates based on vertex ID within the triangle
        // Each triangle has 3 vertices, so vertexID % 3 gives us the vertex index within the triangle
        uint vertexInTriangle = vertexID % 3;
        out.barycentric = float3(
            vertexInTriangle == 0 ? 1.0 : 0.0,
            vertexInTriangle == 1 ? 1.0 : 0.0,
            vertexInTriangle == 2 ? 1.0 : 0.0
        );

        // Calculate primitive ID from vertex ID (each triangle has 3 vertices)
        out.primitiveID = vertexID / 3;
        out.instanceID = instanceID;

        return out;
    }

    // Fragment shader - outputs geometry metadata
    [[fragment]] FragmentOutput fragment_main(
        Fragment in [[stage_in]],
        constant int32_t &geometryID [[buffer(1)]]
    ) {
        FragmentOutput out;

        out.geometryID = geometryID;
        out.instanceID = int(in.instanceID);
        out.triangleID = int(in.primitiveID);

        // Normalized depth (0 to 1)
        out.depth = in.position.z;

        // Store barycentric coordinates with padding
        out.triangleCoordinates = float4(in.barycentric, 0.0);

        return out;
    }

} // namespace HitTest