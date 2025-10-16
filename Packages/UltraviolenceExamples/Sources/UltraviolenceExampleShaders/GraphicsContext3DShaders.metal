#include <metal_stdlib>
#include "GraphicsContext3DShaders.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

[[vertex]] VertexOut graphicsContext3D_vertex(const device GraphicsContext3DVertex* vertices [[buffer(0)]], uint vertexID [[vertex_id]]) {
    GraphicsContext3DVertex in = vertices[vertexID];
    VertexOut out;
    out.position = float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

[[fragment]] float4 graphicsContext3D_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
