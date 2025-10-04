#import "UltraviolenceExampleShaders.h"
#import "VoxelShaders.h"
#import <metal_stdlib>
#import <metal_logging>

using namespace metal;

// https://www.youtube.com/watch?v=ztkh1r1ioZo

template <typename T>
struct Optional {
    bool has;
    T    value;
};

template <typename T>
struct Range {
    T min;
    T max;
};

struct Ray {
    float3 origin;
    float3 direction;
    float3 inverseDirection;
};

struct AABB {
    float3 min;
    float3 max;
};

struct IntersectionResult {
    float tmin;
    float tmax;
    bool hit;
};


// MARK: -

Optional<Range<float>> rayAABBIntersection(const Ray ray, const AABB aabb) {
    float tmin = 0.0;
    float tmax = INFINITY;
    constexpr float epsilon = 1e-6;
    for (int i = 0; i < 3; i++) {
        const float originComponent = ray.origin[i];
        const float directionComponent = ray.direction[i];

        if (fabs(directionComponent) < epsilon) {
            if (originComponent < aabb.min[i] || originComponent > aabb.max[i]) {
                return { false, { 0.0, 0.0 } };
            }
            continue;
        }

        const float invDirectionComponent = ray.inverseDirection[i];
        const float t1 = (aabb.min[i] - originComponent) * invDirectionComponent;
        const float t2 = (aabb.max[i] - originComponent) * invDirectionComponent;
        const float tNear = fmin(t1, t2);
        const float tFar = fmax(t1, t2);
        tmin = fmax(tmin, tNear);
        tmax = fmin(tmax, tFar);
        if (tmax < tmin) {
            return { false, { 0.0, 0.0 } };
        }
    }
    return { true, { tmin, tmax } };
}

Optional<float3> coord_checked(const float3 p, const int3 size) {
    if (p.x < 0.0 || p.y < 0.0 || p.z < 0.0) {
        return { false, float3(0) };
    }
    int3 coord = int3(p);
    if (coord.x >= size.x || coord.y >= size.y || coord.z >= size.z) {
        return { false, float3(0) };
    }
    return { true, float3(coord) };
}

float3 coord_clamped(const float3 p, const int3 size) {
    return float3(
        clamp(p.x, 0.0, float(size.x - 1)),
        clamp(p.y, 0.0, float(size.y - 1)),
        clamp(p.z, 0.0, float(size.z - 1))
    );
}

// MARK: -


namespace VoxelShaders {
    [[kernel]] void voxel_generateSphere(
        uint3 thread_position_in_grid [[thread_position_in_grid]],
        uint3 threads_per_grid [[threads_per_grid]],
        texture3d<float, access::write> voxelTexture [[texture(0)]]
    ) {

        const uint width = voxelTexture.get_width();
        const uint height = voxelTexture.get_height();
        const uint depth = voxelTexture.get_depth();

        if (thread_position_in_grid.x >= width || thread_position_in_grid.y >= height || thread_position_in_grid.z >= depth) {
            return;
        }

        const float3 dimensions = float3(width, height, depth);
        const float3 center = 0.5 * (dimensions - float3(1.0));
        const float minDimension = fmin(dimensions.x, fmin(dimensions.y, dimensions.z));
        const float radius = fmax(0.0, 0.5 * (minDimension - 1.0));

        const float3 position = float3(thread_position_in_grid);
        const float distance = length(position - center);

        float4 color = float4(0.0);
        if (distance <= radius) {
            const float xr = position.x / fmax(dimensions.x - 1.0, 1.0);
            const float yr = position.y / fmax(dimensions.y - 1.0, 1.0);
            const float zr = position.z / fmax(dimensions.z - 1.0, 1.0);
            color = float4(xr, yr, zr, 1.0);
        }

        voxelTexture.write(color, thread_position_in_grid);
    }

    [[kernel]] void voxel_main(
        uint2 thread_position_in_grid [[thread_position_in_grid]],
        uint2 threads_per_grid [[threads_per_grid]],
        texture3d<float, access::read> voxelTexture [[texture(0)]],
        texture2d<float, access::write> outputTexture [[texture(1)]],
        constant float4x4 &projectionMatrix [[buffer(0)]],
        constant float4x4 &inverseProjectionMatrix [[buffer(1)]],
        constant float &near [[buffer(2)]],
        constant float &far [[buffer(3)]],
        constant float4x4 &cameraMatrix [[buffer(4)]],
        constant float4x4 &viewMatrix [[buffer(5)]],
        constant float4x4 &invViewProj [[buffer(6)]],
        constant float3 &cameraPosition [[buffer(7)]],
        constant float4x4 &voxelModelMatrix [[buffer(8)]],
        constant float3 &voxelScale [[buffer(9)]]
    ) {

        const uint2 centerThread = threads_per_grid / 2;
//        /const bool isLogging = thread_position_in_grid.x == centerThread.x && thread_position_in_grid.y == centerThread.y;
        const bool isLogging = false;

        if (isLogging) {
            os_log_default.log("#################");
            os_log_default.log("thread_per_grid: (%d,%d), gid: (%d,%d", threads_per_grid.x, threads_per_grid.y, thread_position_in_grid.x, thread_position_in_grid.y);
        }

        uint width = outputTexture.get_width();
        uint height = outputTexture.get_height();
        if (thread_position_in_grid.x >= width || thread_position_in_grid.y >= height) {
            return;
        }

        // NDC in [-1, +1]. Flip Y for Metal (framebuffer origin top-left).
        float2 ndc = (float2(thread_position_in_grid) / float2(threads_per_grid)) * 2.0 - 1.0;
        ndc.y = -ndc.y;

        // Unproject points on near (z=0) and far (z=1) planes.
        float4 nearH = invViewProj * float4(ndc, 0.0, 1.0);
        float4 farH  = invViewProj * float4(ndc, 1.0, 1.0);
        float3 nearP = nearH.xyz / nearH.w;
        float3 farP  = farH.xyz / farH.w;

            // Build the ray in world space
        float3 origin    = cameraPosition;
        float3 direction = normalize(farP - nearP);
        float3 inverseDirection = float3(
            direction.x == 0.0 ? INFINITY : 1.0 / direction.x,
            direction.y == 0.0 ? INFINITY : 1.0 / direction.y,
            direction.z == 0.0 ? INFINITY : 1.0 / direction.z
        );
        const Ray ray = { origin, direction, inverseDirection };

        //

        // Transform ray to voxel local space
        float4 localOriginH = voxelModelMatrix * float4(ray.origin, 1.0);
        float3 localDirection = (voxelModelMatrix * float4(ray.direction, 0.0)).xyz;
        localDirection = normalize(localDirection);
        float3 localInverseDirection = float3(
            localDirection.x == 0.0 ? INFINITY : 1.0 / localDirection.x,
            localDirection.y == 0.0 ? INFINITY : 1.0 / localDirection.y,
            localDirection.z == 0.0 ? INFINITY : 1.0 / localDirection.z
        );
        const Ray localRay = { localOriginH.xyz, localDirection, localInverseDirection };

        // 3d texture size
        int3 voxelTextureSize = int3(
            voxelTexture.get_width(),
            voxelTexture.get_height(),
            voxelTexture.get_depth()
        );

        const float3 voxelExtent = voxelScale * float3(voxelTextureSize);
        const float3 halfExtent = 0.5 * voxelExtent;
        const AABB aabb = { -halfExtent, halfExtent };

        const auto intersection = rayAABBIntersection(localRay, aabb);

        if (isLogging) {
            os_log_default.log(
                "localRay origin:(%f,%f,%f) direction:(%f,%f,%f) hasIntersection:%d",
                localRay.origin.x, localRay.origin.y, localRay.origin.z,
                localRay.direction.x, localRay.direction.y, localRay.direction.z,
                intersection.has ? 1 : 0
            );
            if (intersection.has) {
                os_log_default.log("tRange:(%f,%f)", intersection.value.min, intersection.value.max);
            }
        }

        const float4 clearColor = float4(0, 0, 0, 1);
        outputTexture.write(clearColor, thread_position_in_grid);

        if (!intersection.has) {
            return;
        }

        const float4 fallbackColor = float4(0.0, 0.2, 0.0, 1.0);
        outputTexture.write(fallbackColor, thread_position_in_grid);

        const float entryOffset = 1e-4;
        const float tEntry = intersection.value.min + entryOffset;
        const float3 entryPosition = localRay.origin + tEntry * localRay.direction;

        const float3 gridOrigin = (entryPosition - aabb.min) / voxelScale;
        const float3 gridDirection = localRay.direction / voxelScale;

        float3 tDelta = float3(INFINITY);
        float3 tMax = float3(INFINITY);
        int3 step = int3(0);

        int3 voxelCoord = int3(floor(gridOrigin));

        for (int axis = 0; axis < 3; ++axis) {
            const float dir = gridDirection[axis];
            if (dir > 0.0) {
                step[axis] = 1;
                tDelta[axis] = 1.0 / dir;
                const float nextBoundary = float(voxelCoord[axis] + 1);
                tMax[axis] = (nextBoundary - gridOrigin[axis]) * tDelta[axis];
            } else if (dir < 0.0) {
                step[axis] = -1;
                tDelta[axis] = -1.0 / dir;
                const float nextBoundary = float(voxelCoord[axis]);
                tMax[axis] = (gridOrigin[axis] - nextBoundary) * tDelta[axis];
            }
        }

        const int3 gridBounds = voxelTextureSize;
        const int maxSteps = gridBounds.x + gridBounds.y + gridBounds.z; // 3D DDA upper bound

        for (int n = 0; n < maxSteps; ++n) {
            if (voxelCoord.x < 0 || voxelCoord.y < 0 || voxelCoord.z < 0 ||
                voxelCoord.x >= gridBounds.x || voxelCoord.y >= gridBounds.y || voxelCoord.z >= gridBounds.z) {
                break;
            }

            if (isLogging && n < 8) {
                const float3 voxelCenter = (float3(voxelCoord) + 0.5) * voxelScale + aabb.min;
                os_log_default.log("step:%d voxel:(%d,%d,%d) world:(%f,%f,%f)",
                                   n,
                                   voxelCoord.x, voxelCoord.y, voxelCoord.z,
                                   voxelCenter.x, voxelCenter.y, voxelCenter.z);
            }

            const float4 color = voxelTexture.read(uint3(voxelCoord));
            if (color.a > 0.0) {
                outputTexture.write(color, thread_position_in_grid);
                return;
            }

            if (tMax.x < tMax.y) {
                if (tMax.x < tMax.z) {
                    voxelCoord.x += step.x;
                    tMax.x += tDelta.x;
                } else {
                    voxelCoord.z += step.z;
                    tMax.z += tDelta.z;
                }
            } else {
                if (tMax.y < tMax.z) {
                    voxelCoord.y += step.y;
                    tMax.y += tDelta.y;
                } else {
                    voxelCoord.z += step.z;
                    tMax.z += tDelta.z;
                }
            }
        }
    }
}
