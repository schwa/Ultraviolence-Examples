#include <metal_stdlib>
#include "GrassShaders.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
};

using MeshType = mesh<VertexOut, void, 256, 384, topology::triangle>;

[[object, max_total_threads_per_threadgroup(1)]]
void grassObjectShader(uint objectID [[thread_position_in_grid]], object_data GrassObjectPayload& payload [[payload]], mesh_grid_properties mgp) {
    payload.pointIndex = objectID;
    mgp.set_threadgroups_per_grid(uint3(1, 1, 1));
}

[[mesh, max_total_threads_per_threadgroup(1)]]
void grassMeshShader(MeshType mesh_out, const device GrassPointData* pointData [[buffer(0)]], const device GrassUniforms& uniforms [[buffer(1)]], object_data const GrassObjectPayload& payload [[payload]]) {
    uint pointIndex = payload.pointIndex;
    GrassPointData data = pointData[pointIndex];

    float3 basePosition = data.position;
    float3 normal = data.normal;
    float3 tangent = data.tangent;
    float3 bitangent = data.bitangent;
    float bladeLength = data.bladeLength;

    uint vertexCount = 0;
    uint primitiveCount = 0;

    int bladesPerPoint = data.bladesPerPoint;
    float bladeWidth = 0.015 * data.bladeWidthMultiplier;
    int segmentsPerBlade = 4;

    for (int bladeIdx = 0; bladeIdx < bladesPerPoint; bladeIdx++) {
        float angle = float(bladeIdx) * 2.0 * M_PI_F / float(bladesPerPoint);
        float randomAngleOffset = sin(float(pointIndex) * 12.9898 + float(bladeIdx) * 78.233) * 0.5;
        float randomHeightOffset = sin(float(pointIndex) * 43.758 + float(bladeIdx) * 91.627) * 0.03;
        float randomCurve = sin(float(pointIndex) * 27.183 + float(bladeIdx) * 63.491) * 0.3;

        float3 tangentDir = normalize(tangent * cos(angle + randomAngleOffset) + bitangent * sin(angle + randomAngleOffset));
        float3 bladeDirection = normalize(normal * 0.9 + tangentDir * 0.3);

        float3 bladeRight = normalize(cross(bladeDirection, normal)) * bladeWidth;

        for (int seg = 0; seg <= segmentsPerBlade; seg++) {
            float t = float(seg) / float(segmentsPerBlade);
            float tSquared = t * t;
            float tCubed = t * t * t;

            float3 offset = bladeDirection * (bladeLength * t);
            offset += normal * randomHeightOffset;

            float curve = tSquared * randomCurve * bladeLength;
            offset += tangentDir * curve;

            if (data.droopEnabled != 0) {
                float droopAmount = tSquared * bladeLength * 0.8;
                offset -= normal * droopAmount;
            }

            float widthScale = (1.0 - tCubed) * (1.0 - tSquared * 0.3);

            float3 p0 = basePosition + offset - bladeRight * widthScale;
            float3 p1 = basePosition + offset + bladeRight * widthScale;

            float4 pos0 = uniforms.modelViewProjection * float4(p0, 1.0);
            float4 pos1 = uniforms.modelViewProjection * float4(p1, 1.0);

            float tipFade = 1.0 - t;
            float greenIntensity = 0.35 + 0.35 * tipFade;
            float4 color = float4(0.1 * greenIntensity, greenIntensity, 0.15 * greenIntensity, 1.0);

            mesh_out.set_vertex(vertexCount++, VertexOut{pos0, normal, color});
            mesh_out.set_vertex(vertexCount++, VertexOut{pos1, normal, color});

            if (seg > 0) {
                uint base = vertexCount - 4;
                mesh_out.set_index(primitiveCount * 3 + 0, base + 0);
                mesh_out.set_index(primitiveCount * 3 + 1, base + 2);
                mesh_out.set_index(primitiveCount * 3 + 2, base + 1);
                primitiveCount++;

                mesh_out.set_index(primitiveCount * 3 + 0, base + 1);
                mesh_out.set_index(primitiveCount * 3 + 1, base + 2);
                mesh_out.set_index(primitiveCount * 3 + 2, base + 3);
                primitiveCount++;
            }
        }
    }

    mesh_out.set_primitive_count(primitiveCount);
}

[[fragment]] float4 grassFragmentShader(VertexOut in [[stage_in]]) {
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(in.normal);

    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    float3 grassColor = float3(0.2, 0.6, 0.25);
    float3 finalColor = grassColor * lighting;

    return float4(finalColor, 1.0);
}
