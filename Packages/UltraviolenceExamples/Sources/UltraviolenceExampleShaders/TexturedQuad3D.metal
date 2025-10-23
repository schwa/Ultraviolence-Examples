#import "UltraviolenceExampleShaders.h"
#import <metal_stdlib>

using namespace metal;

namespace TexturedQuad3D {

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    [[vertex]] VertexOut vertex_main(
        uint vertexID [[vertex_id]],
        constant float3* positions [[buffer(0)]],
        constant float2* texCoords [[buffer(1)]],
        constant float4x4& mvpMatrix [[buffer(2)]]
    ) {
        VertexOut out;
        float3 pos = positions[vertexID];
        out.position = mvpMatrix * float4(pos, 1.0);
        out.texCoord = texCoords[vertexID];
        return out;
    }

    [[fragment]] float4 fragment_main(
        VertexOut in [[stage_in]],
        constant ColorSourceArgumentBuffer& specifierA [[buffer(0)]],
        constant ColorSourceArgumentBuffer& specifierB [[buffer(1)]],
        constant int& transformColorParameters [[buffer(2)]]
    ) {
        // Sample Y and CbCr textures using the argument buffer's sampler
        float4 colorA = specifierA.texture2D.sample(specifierA.sampler, in.texCoord);
        float4 colorB = specifierB.texture2D.sample(specifierB.sampler, in.texCoord);

        // YCbCr to RGB conversion (same as in TextureBillboard.metal)
        const float4x4 ycbcrToRGBTransform = float4x4(
            float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
            float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
            float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
            float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
        );

        float4 ycbcr = float4(colorA.r, colorB.rg, 1.0);
        return ycbcrToRGBTransform * ycbcr;
    }

} // namespace TexturedQuad3D
