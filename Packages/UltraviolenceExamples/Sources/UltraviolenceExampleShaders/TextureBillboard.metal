#import "UltraviolenceExampleShaders.h"
#import <metal_stdlib>

using namespace metal;

namespace TextureBillboard {

    [[visible]] float4
    colorTransform(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters);

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 textureCoordinate [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 textureCoordinate;
    };

    // MARK: -

    [[vertex]] VertexOut vertex_main(const VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 0.0, 1.0);
        out.textureCoordinate = in.textureCoordinate;
        return out;
    }

    [[fragment]] float4 fragment_main(
        VertexOut in [[stage_in]],
        constant ColorSourceArgumentBuffer &specifierA [[buffer(0)]],
        constant ColorSourceArgumentBuffer &specifierB [[buffer(2)]],
        constant void *transformColorParameters [[buffer(4)]]

    ) {
        float4 colorA = specifierA.resolve(in.textureCoordinate);
        float4 colorB = specifierB.resolve(in.textureCoordinate);
        return colorTransform(colorA, colorB, in.textureCoordinate, transformColorParameters);
    }

    // MARK: -

    [[stitchable]] float4
    colorTransformIdentity(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        return colorA;
    }

    [[stitchable]] float4
    colorTransformDebug(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        return float4(1, 0, 1, 1);
    }

    [[stitchable]] float4
    colorTransformYCbCrToRGB(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        // From: https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal
        // ARKit provides Y in colorA (r8Unorm) and CbCr in colorB (rg8Unorm)
        // colorA.r contains Y (luminance)
        // colorB.rg contains Cb and Cr (chrominance)

        const float4x4 ycbcrToRGBTransform = float4x4(
            float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f), float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
            float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f), float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
        );

        // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate.
        float4 ycbcr = float4(colorA.r, colorB.rg, 1.0);

        // Return the converted RGB color.
        return ycbcrToRGBTransform * ycbcr;
    }

    [[stitchable]] float4
    colorTransformBGRAToRGBA(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        // Simple BGRA to RGBA swizzle
        return colorA.bgra;
    }

    [[stitchable]] float4
    colorTransformHitTestVisualize(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        // For integer IDs (geometry, instance, triangle), multiply by a large factor to make visible
        // Assuming IDs are in the red channel as int32 values normalized to [0,1]
        float value = colorA.r;

        // If the value is negative (no hit), show as black
        if (value < 0) {
            return float4(0, 0, 0, 1);
        }

        // For small integer values, create a color gradient
        // Multiply by a large factor and use different color channels
        float scaled = value * 1000.0; // Scale up small values

        // Create a color based on the scaled value
        float3 color = float3(
            fract(scaled * 1.0),        // Red channel
            fract(scaled * 7.0),         // Green channel
            fract(scaled * 13.0)         // Blue channel
        );

        return float4(color, 1.0);
    }

    [[stitchable]] float4
    colorTransformDepthVisualize(float4 colorA, float4 colorB, float2 textureCoordinate, constant void *parameters) {
        // For depth values, invert and scale for better visualization
        float depth = colorA.r;

        // Invert depth (near = white, far = black) and apply gamma for better visualization
        float visualized = pow(1.0 - depth, 2.2);

        return float4(visualized, visualized, visualized, 1.0);
    }

} // namespace TextureBillboard
