#pragma once

#import <simd/simd.h>

#if defined(__METAL_VERSION__)
#import <metal_stdlib>
#define ATTRIBUTE(INDEX) [[attribute(INDEX)]]
#define TEXTURE2D(TYPE, ACCESS) texture2d<TYPE, ACCESS>
#define DEPTH2D(TYPE, ACCESS) depth2d<TYPE, ACCESS>
#define TEXTURECUBE(TYPE, ACCESS) texturecube<TYPE, ACCESS>
#define SAMPLER sampler
#define BUFFER(ADDRESS_SPACE, TYPE) ADDRESS_SPACE TYPE
using namespace metal;
#else
#import <Metal/Metal.h>
#define ATTRIBUTE(INDEX)
#define TEXTURE2D(TYPE, ACCESS) MTLResourceID
#define DEPTH2D(TYPE, ACCESS) MTLResourceID
#define TEXTURECUBE(TYPE, ACCESS) MTLResourceID
#define SAMPLER MTLResourceID
#define BUFFER(ADDRESS_SPACE, TYPE) TYPE
#endif

typedef simd_float4x4 float4x4;
typedef simd_float3x3 float3x3;
typedef simd_float4 float4;
typedef simd_float3 float3;

// Copied from <CoreFoundation/CFAvailability.h>
#define __UV_ENUM_ATTRIBUTES __attribute__((enum_extensibility(open)))
#define __UV_ANON_ENUM(_type) enum __UV_ENUM_ATTRIBUTES : _type
#define __UV_NAMED_ENUM(_type, _name)                                                                                  \
    enum __UV_ENUM_ATTRIBUTES _name : _type _name;                                                                     \
    enum _name : _type
#define __UV_ENUM_GET_MACRO(_1, _2, NAME, ...) NAME
#define UV_ENUM(...) __UV_ENUM_GET_MACRO(__VA_ARGS__, __UV_NAMED_ENUM, __UV_ANON_ENUM, )(__VA_ARGS__)

struct FrameUniforms {
    uint index;
    float time;
    float deltaTime;
    simd_int2 viewportSize;
};
typedef struct FrameUniforms FrameUniforms;

/// Universal transforms.
/// TODO: Deprecate
struct Transforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 cameraMatrix;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 modelViewMatrix;
    simd_float4x4 modelViewProjectionMatrix;
};

#if defined(__METAL_VERSION__)
inline float square(float x) {
    return x * x;
}

inline float3x3 extractNormalMatrix(float4x4 modelMatrix) {
    return float3x3(modelMatrix[0].xyz, modelMatrix[1].xyz, modelMatrix[2].xyz);
}
#endif

struct BufferDescriptor {
    uint count;        // elements in the buffer
    uint stride;       // bytes per element
    uint valueOffset;  // byte offset of the value within each element
};

#if defined(__METAL_VERSION__)
// Generic unaligned load: works for any T
template <typename T>
inline T load_at(device const uchar* base, constant BufferDescriptor& d, uint i) {
    T out;
    device const uchar* src = base + i * d.stride + d.valueOffset;
    thread uchar* dst = reinterpret_cast<thread uchar*>(&out);
    // tiny copy (no std::memcpy in MSL)
    for (uint b = 0; b < sizeof(T); ++b) { dst[b] = src[b]; }
    return out;
}

// Special-case float3 via packed_float3 to avoid alignment traps
template <>
inline float3 load_at<float3>(device const uchar* base, constant BufferDescriptor& d, uint i) {
    packed_float3 p = load_at<packed_float3>(base, d, i);
    return float3(p);
}

// Optional bounds-checked variant
template <typename T>
inline bool try_load(device const uchar* base, constant BufferDescriptor& d, uint i, thread T& out) {
    if (i >= d.count) return false;
    out = load_at<T>(base, d, i);
    return true;
}

#endif
