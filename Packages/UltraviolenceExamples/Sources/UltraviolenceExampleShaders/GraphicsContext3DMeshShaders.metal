#include <metal_stdlib>
#include <metal_logging>
#include "GraphicsContext3DShaders.h"

using namespace metal;

// MARK: - Helper Functions

int segmentCountForRadius(float radius) {
    if (radius < 2.0) return 3;
    if (radius < 5.0) return 4;
    if (radius < 10.0) return 6;
    if (radius < 20.0) return 8;
    if (radius < 40.0) return 12;
    return 16;
}

float2 toScreen(float3 point3D, float4x4 viewProjection, float2 viewport) {
    float4 clipPos = viewProjection * float4(point3D, 1.0);
    if (abs(clipPos.w) < 1e-6) return float2(0, 0);
    float2 ndc = clipPos.xy / clipPos.w;
    return (ndc * 0.5 + 0.5) * viewport;
}

float3 toClip(float2 screenPos, float depth, float w, float2 viewport) {
    float2 ndc = (screenPos / viewport) * 2.0 - 1.0;
    return float3(ndc * w, depth * w);
}

// MARK: - Object Shader

struct ObjectPayload {
    uint joinIndex;
};

[[object, max_total_threads_per_threadgroup(1)]]
void lineJoinObjectShader(
    uint objectID [[thread_position_in_grid]],
    object_data ObjectPayload& payload [[payload]],
    mesh_grid_properties mgp
) {
    payload.joinIndex = objectID;
    mgp.set_threadgroups_per_grid(uint3(1, 1, 1));
}

// MARK: - Mesh Shader

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

using MeshType = mesh<VertexOut, void, 256, 512, topology::triangle>;

[[mesh, max_total_threads_per_threadgroup(1)]]
void lineJoinMeshShader(
    MeshType mesh_out,
    const device LineJoinGPUData* joinData [[buffer(0)]],
    const device LineJoinUniforms& uniforms [[buffer(1)]],
    object_data const ObjectPayload& payload [[payload]]
) {
    uint joinIndex = payload.joinIndex;
    LineJoinGPUData data = joinData[joinIndex];

    float2 prevScreen = toScreen(data.prevPoint, uniforms.viewProjection, uniforms.viewport);
    float2 joinScreen = toScreen(data.joinPoint, uniforms.viewProjection, uniforms.viewport);
    float2 nextScreen = toScreen(data.nextPoint, uniforms.viewProjection, uniforms.viewport);

    float radius = data.lineWidth / 2.0;

    uint vertexCount = 0;
    uint primitiveCount = 0;

    // Transform points to clip space for depth
    float4 prevClip = uniforms.viewProjection * float4(data.prevPoint, 1.0);
    float4 joinClip = uniforms.viewProjection * float4(data.joinPoint, 1.0);
    float4 nextClip = uniforms.viewProjection * float4(data.nextPoint, 1.0);

    float prevDepth = prevClip.z / prevClip.w;
    float joinDepth = joinClip.z / joinClip.w;
    float nextDepth = nextClip.z / nextClip.w;

    // Half-segment A: prevPoint to joinPoint
    if (data.isStartCap == 0) {
        float2 dirPrev = normalize(joinScreen - prevScreen);
        float2 perpPrev = float2(-dirPrev.y, dirPrev.x);

        float2 p0 = prevScreen - perpPrev * radius;
        float2 p1 = prevScreen + perpPrev * radius;
        float2 p2 = joinScreen + perpPrev * radius;
        float2 p3 = joinScreen - perpPrev * radius;

        mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, prevDepth, prevClip.w, uniforms.viewport), prevClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, prevDepth, prevClip.w, uniforms.viewport), prevClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
        primitiveCount++;

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
        primitiveCount++;

        vertexCount += 4;
    }

    // Half-segment B: joinPoint to nextPoint
    if (data.isEndCap == 0) {
        float2 dirNext = normalize(nextScreen - joinScreen);
        float2 perpNext = float2(-dirNext.y, dirNext.x);

        float2 p0 = joinScreen - perpNext * radius;
        float2 p1 = joinScreen + perpNext * radius;
        float2 p2 = nextScreen + perpNext * radius;
        float2 p3 = nextScreen - perpNext * radius;

        mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, nextDepth, nextClip.w, uniforms.viewport), nextClip.w), data.color});
        mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, nextDepth, nextClip.w, uniforms.viewport), nextClip.w), data.color});

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
        primitiveCount++;

        mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
        mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
        mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
        primitiveCount++;

        vertexCount += 4;
    }

    // Join at center point
    if (data.isStartCap == 0 && data.isEndCap == 0) {
        float2 dirPrev = normalize(joinScreen - prevScreen);
        float2 dirNext = normalize(nextScreen - joinScreen);

        float crossProd = dirPrev.x * dirNext.y - dirPrev.y * dirNext.x;

        // Choose perpendicular direction based on turn direction to ensure it points outside
        // Left turn (cross > 0): rotate clockwise, Right turn (cross < 0): rotate counter-clockwise
        float2 perpPrev = crossProd > 0 ? float2(dirPrev.y, -dirPrev.x) : float2(-dirPrev.y, dirPrev.x);
        float2 perpNext = crossProd > 0 ? float2(dirNext.y, -dirNext.x) : float2(-dirNext.y, dirNext.x);

        if (data.joinStyle == 1) {  // Round join
            int segments = segmentCountForRadius(radius);
            segments = min(segments, 16);  // Cap for vertex budget

            float startAngle = atan2(perpPrev.y, perpPrev.x);
            float endAngle = atan2(perpNext.y, perpNext.x);
            float angleDelta = endAngle - startAngle;

            if (crossProd > 0) {
                if (angleDelta < 0) angleDelta += 2.0 * M_PI_F;
            } else {
                if (angleDelta > 0) angleDelta -= 2.0 * M_PI_F;
            }

            uint centerVertex = vertexCount++;
            mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            for (int i = 0; i <= segments; i++) {
                float t = float(i) / float(segments);
                float angle = startAngle + angleDelta * t;
                float2 offset = float2(cos(angle), sin(angle)) * radius;
                float2 p = joinScreen + offset;

                mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

                if (i > 0) {
                    mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                    primitiveCount++;
                }
                vertexCount++;
            }
        } else if (data.joinStyle == 0) {  // Miter
            float2 prevOuter = joinScreen + perpPrev * radius;
            float2 nextOuter = joinScreen + perpNext * radius;

            // Find intersection of two offset lines:
            // Line 1: prevOuter + t * dirPrev
            // Line 2: nextOuter + s * dirNext
            float denom = dirPrev.x * dirNext.y - dirPrev.y * dirNext.x;

            bool useBevel = false;
            float2 miterPoint;

            if (abs(denom) < 1e-6) {
                // Lines are parallel, use bevel
                useBevel = true;
            } else {
                float2 diff = nextOuter - prevOuter;
                float t = (diff.x * dirNext.y - diff.y * dirNext.x) / denom;
                miterPoint = prevOuter + t * dirPrev;

                // Check miter limit
                float miterDist = distance(miterPoint, joinScreen);
                float miterRatio = miterDist / radius;

                if (miterRatio > data.miterLimit) {
                    useBevel = true;
                }
            }

            if (useBevel) {
                // Bevel: simple triangle from center to both outer points
                mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
                mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
                mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                primitiveCount++;
                vertexCount += 3;
            } else {
                // Miter: two triangles using the miter point
                mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
                mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
                mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(miterPoint, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
                mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
                primitiveCount++;

                mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
                mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
                primitiveCount++;

                vertexCount += 4;
            }
        } else {  // Bevel (joinStyle == 2)
            float2 prevOuter = joinScreen + perpPrev * radius;
            float2 nextOuter = joinScreen + perpNext * radius;

            mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(prevOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(nextOuter, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
            primitiveCount++;
            vertexCount += 3;
        }
    }

    // Start cap
    if (data.isStartCap == 1) {
        float2 dir = normalize(joinScreen - nextScreen);
        float2 perp = float2(-dir.y, dir.x);

        if (data.capStyle == 2) {  // Round cap
            int segments = segmentCountForRadius(radius);
            segments = min(segments, 16);

            float dirAngle = atan2(dir.y, dir.x);
            float startAngle = dirAngle - M_PI_F / 2.0;

            uint centerVertex = vertexCount++;
            mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            for (int i = 0; i <= segments; i++) {
                float t = float(i) / float(segments);
                float angle = startAngle + M_PI_F * t;
                float2 offset = float2(cos(angle), sin(angle)) * radius;
                float2 p = joinScreen + offset;

                mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

                if (i > 0) {
                    mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                    primitiveCount++;
                }
                vertexCount++;
            }
        } else if (data.capStyle == 3) {  // Square cap
            float2 p0 = joinScreen - perp * radius + dir * radius;
            float2 p1 = joinScreen + perp * radius + dir * radius;
            float2 p2 = joinScreen + perp * radius;
            float2 p3 = joinScreen - perp * radius;

            mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
            primitiveCount++;

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
            primitiveCount++;
            vertexCount += 4;
        }
    }

    // End cap
    if (data.isEndCap == 1) {
        float2 dir = normalize(joinScreen - prevScreen);
        float2 perp = float2(-dir.y, dir.x);

        if (data.capStyle == 2) {  // Round cap
            int segments = segmentCountForRadius(radius);
            segments = min(segments, 16);

            float dirAngle = atan2(dir.y, dir.x);
            float startAngle = dirAngle - M_PI_F / 2.0;

            uint centerVertex = vertexCount++;
            mesh_out.set_vertex(centerVertex, VertexOut{float4(toClip(joinScreen, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            for (int i = 0; i <= segments; i++) {
                float t = float(i) / float(segments);
                float angle = startAngle + M_PI_F * t;
                float2 offset = float2(cos(angle), sin(angle)) * radius;
                float2 p = joinScreen + offset;

                mesh_out.set_vertex(vertexCount, VertexOut{float4(toClip(p, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

                if (i > 0) {
                    mesh_out.set_index(primitiveCount * 3 + 0, centerVertex);
                    mesh_out.set_index(primitiveCount * 3 + 1, vertexCount - 1);
                    mesh_out.set_index(primitiveCount * 3 + 2, vertexCount);
                    primitiveCount++;
                }
                vertexCount++;
            }
        } else if (data.capStyle == 3) {  // Square cap
            float2 p0 = joinScreen - perp * radius;
            float2 p1 = joinScreen + perp * radius;
            float2 p2 = joinScreen + perp * radius + dir * radius;
            float2 p3 = joinScreen - perp * radius + dir * radius;

            mesh_out.set_vertex(vertexCount + 0, VertexOut{float4(toClip(p0, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 1, VertexOut{float4(toClip(p1, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 2, VertexOut{float4(toClip(p2, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});
            mesh_out.set_vertex(vertexCount + 3, VertexOut{float4(toClip(p3, joinDepth, joinClip.w, uniforms.viewport), joinClip.w), data.color});

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 1);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 2);
            primitiveCount++;

            mesh_out.set_index(primitiveCount * 3 + 0, vertexCount + 0);
            mesh_out.set_index(primitiveCount * 3 + 1, vertexCount + 2);
            mesh_out.set_index(primitiveCount * 3 + 2, vertexCount + 3);
            primitiveCount++;
            vertexCount += 4;
        }
    }

    mesh_out.set_primitive_count(primitiveCount);
}

// MARK: - Fragment Shader

fragment float4 lineJoinFragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
}
