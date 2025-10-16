# GraphicsContext3D Mesh Shader Implementation

## Overview

GraphicsContext3D uses Metal mesh shaders to render 3D strokes with proper line caps and joins. The system uses a hybrid CPU/GPU approach:
- **CPU**: Flatten Bezier curves to line segments, package segment data
- **GPU**: Generate geometry for line segments, joins, and caps

## Architecture

### Data Flow

1. User creates `Path3D` with lines and curves
2. `GraphicsContext3D` records stroke/fill commands
3. `GeometryGenerator.generateLineJoinGPUData()` processes each path:
   - Flattens curves to line segments
   - Packages segments as join data (prevPoint, joinPoint, nextPoint)
4. Data uploaded to GPU buffers
5. **Object Shader**: One invocation per join, passes join index to mesh shader
6. **Mesh Shader**: Generates geometry for line segments, joins, and caps
7. **Fragment Shader**: Simple passthrough for color

### Join Data Structure

Each join represents a connection point between line segments. The mesh shader receives:
- `prevPoint`: Start of incoming segment
- `joinPoint`: The join location
- `nextPoint`: End of outgoing segment
- Flags: `isStartCap`, `isEndCap`
- Style: `lineWidth`, `joinStyle`, `capStyle`, `color`

For a path with N segments:
- **Open path**: N+1 join entries (start cap + N-1 joins + end cap)
- **Closed path**: N join entries (all joins, wrapping around)

## Data Structures

### Metal Header: `GraphicsContext3DShaders.h`

```c
struct LineJoinGPUData {
    simd_float3 prevPoint;      // Start of half-segment-A (12 bytes)
    simd_float3 joinPoint;      // Center join point (12 bytes)
    simd_float3 nextPoint;      // End of half-segment-B (12 bytes)
    float lineWidth;            // 4 bytes
    uint32_t joinStyle;         // 0=miter, 1=round, 2=bevel (4 bytes)
    uint32_t capStyle;          // 0=none, 1=butt, 2=round, 3=square (4 bytes)
    uint32_t isStartCap;        // 1 if start cap needed (4 bytes)
    uint32_t isEndCap;          // 1 if end cap needed (4 bytes)
    simd_float4 color;          // 16 bytes
    float miterLimit;           // 4 bytes
    float _padding[3];          // 12 bytes - Align to 16 bytes
};                              // Total: 88 bytes

struct LineJoinUniforms {
    simd_float4x4 viewProjection;  // 64 bytes
    simd_float2 viewport;          // 8 bytes
    float _padding[2];             // 8 bytes - Align to 16 bytes
};                                 // Total: 80 bytes
```

### Swift Side: `GraphicsContext3DGeometry.swift`

Swift imports these structures from the Metal header via the C bridge:
```swift
import UltraviolenceExampleShaders

// LineJoinGPUData is directly available from the Metal header
// LineJoinUniforms is directly available from the Metal header
```

**CRITICAL**: Swift and Metal must have **identical struct layouts**. Any mismatch causes garbage/NaN values.

## Mesh Shader Pipeline

### Object Shader (`lineJoinObjectShader`)

- One thread per join
- Receives: `objectID` (join index)
- Outputs: `ObjectPayload` with `joinIndex`
- Sets mesh grid size to (1, 1, 1)

**Location**: `GraphicsContext3DMeshShaders.metal:36-43`

### Mesh Shader (`lineJoinMeshShader`)

Generates geometry for:
1. **Half-segment A**: `prevPoint` → `joinPoint` (if not start cap)
2. **Half-segment B**: `joinPoint` → `nextPoint` (if not end cap)
3. **Join**: Connection at `joinPoint` (if not a cap)
4. **Start Cap**: At `joinPoint` (if `isStartCap == 1`)
5. **End Cap**: At `nextPoint` (if `isEndCap == 1`)

**Vertex Budget**: Max 256 vertices per invocation
- Each half-segment: 4 vertices (quad)
- Round join: 2 + segments vertices (segments adaptive based on radius)
- Miter/bevel join: 3 vertices
- Round cap: 1 + segments vertices
- Square cap: 4 vertices

**Location**: `GraphicsContext3DMeshShaders.metal:55-308`

### Fragment Shader (`lineJoinFragmentShader`)

Simple passthrough for color.

**Location**: `GraphicsContext3DMeshShaders.metal:312-314`

## Current Status

### Completed
- ✅ GPU data structures defined in Metal header
- ✅ CPU geometry generation (`generateLineJoinGPUData`)
- ✅ Object shader implementation
- ✅ Mesh shader implementation (segments, joins, caps)
- ✅ Fragment shader
- ✅ Pipeline setup in `GraphicsContext3DRenderPipeline`
- ✅ Debug labels and groups added
- ✅ Fixed missing mesh buffer binding (was reading all zeros)
- ✅ Fixed end cap positioning (use joinScreen not nextScreen)
- ✅ Refactored to use `.parameter()` API instead of manual encoder.setBuffer() calls
- ✅ **Rendering works!** Mesh shaders are generating geometry correctly

### Known Issues
None currently! The implementation is working as expected.

### Next Steps
1. Test with various camera angles to ensure end caps render correctly
2. Performance testing and optimization if needed
3. Consider removing debug logging once fully validated

## Buffer Setup

### Join Data Buffer
- Size: 16 MB
- Contains: Array of `LineJoinGPUData`
- Binding: Mesh shader parameter `joinData`

### Uniforms Buffer
- Size: `MemoryLayout<LineJoinUniforms>.stride` (80 bytes)
- Contains: Single `LineJoinUniforms` struct
- Binding: Mesh shader parameter `uniforms`

### Fill Vertex Buffer
- Size: 64 MB
- Contains: Array of `Vertex` (CPU-generated via earcut)
- Binding: Vertex shader parameter `vertices`

## Rendering

Both pipelines are always created, conditionals are inside Draw closures:

```swift
return try Group {
    try MeshRenderPipeline(objectShader:meshShader:fragmentShader:) {
        Draw { encoder in
            guard joinCount > 0 else { return }
            // ... configure and draw
        }
        .parameter("joinData", functionType: .mesh, buffer: joinDataBuffer!, offset: 0)
        .parameter("uniforms", functionType: .mesh, buffer: uniformsBuffer!, offset: 0)
    }

    try RenderPipeline(vertexShader:fragmentShader:) {
        Draw { encoder in
            guard fillVertexCount > 0 else { return }
            // ... configure and draw
        }
        .parameter("vertices", functionType: .vertex, buffer: fillVertexBuffer!, offset: 0)
    }
}
```

Parameters are bound using the `.parameter()` API, which uses shader reflection to automatically find the correct buffer indices.

## Debug Output

Console prints on buffer regeneration:
```
Uniforms: viewport=SIMD2<Float>(2694.0, 1942.0)
ViewProjection matrix columns: ...
Regenerating buffers: 6 joins, 0 fill vertices
First join: prev=..., join=..., next=..., isStart=1, isEnd=0
```

Metal frame capture shows:
- "GraphicsContext3D Stroke Mesh Shader (joinCount: N)" debug group
- "GraphicsContext3D Fill Geometry (fillVertexCount: N)" debug group

## References

- Mesh shader pipeline: `GraphicsContext3DRenderPipeline.swift:141-159`
- Geometry generation: `GraphicsContext3DGeometry.swift:664-782`
- Metal shaders: `GraphicsContext3DMeshShaders.metal`
- Data structures: `GraphicsContext3DShaders.h`
