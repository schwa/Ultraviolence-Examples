import DemoKit
import SwiftUI
import UltraviolenceExamples

@MainActor let allDemos: [any DemoView.Type] = {
    var demos: [any DemoView.Type] = [
        EmptyDemoView.self,
        BlinnPhongDemoView.self,
        HitTestDemoView.self,
        SkyboxDemoView.self,
        TriangleDemoView.self,
        ComputeDemoView.self,
        DepthDemoView.self,
        MixedDemoView.self,
        BouncingTeapotsDemoView.self,
        StencilDemoView.self,
        LUTDemoView.self,
        GameOfLifeDemoView.self,
        AppleEventLogoDemoView.self,
        ColorAdjustDemoView.self,
        DebugShadersDemoView.self,
        PBRDemoView.self,
        SDFDemoView.self,
        PointCloudDemoView.self,
        ParticleEffectsDemoView.self,
        VideoPlaybackDemoView.self,
        PanoramaDemoView.self,
        WireframeDemoView.self,
        TrivialMeshDemoView.self,
        SceneGraphDemoView.self,
        GLTFDemoView.self,
        VoxelDemoView.self,
        GrassDemoView.self,
        GraphicsContext3DDemoView.self,
        EdgeRenderingDemoView.self
    ]

    #if os(macOS)
    demos += [
        OffscreenDemoView.self
    ]
    #endif

    #if os(iOS)
    demos += [
        ARKitDemoView.self
    ]
    #endif

    #if canImport(MetalFX)
    demos += [
        MetalFXDemoView.self
    ]
    #endif

    return demos
}()

struct EmptyDemoView: DemoView {
    static var metadata: DemoMetadata {
        DemoMetadata(name: "Empty", description: "An empty view.")
    }

    init() {
        // Empty initializer
    }

    var body: some View {
        Text("This view intentionally left blank")
    }
}

extension TriangleDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Triangle",
            description: "Basic triangle rendering with animated colors and performance metrics",
            group: "Basic",
            keywords: ["animated"]
        )
    }
}

extension GameOfLifeDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Game of Life",
            description: "Conway's Game of Life cellular automaton simulation using GPU compute shaders",
            group: "Basic",
            keywords: ["animated"]
        )
    }
}

extension StencilDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Stencil Buffer",
            description: "Stencil buffer masking demonstration with checkerboard pattern clipping",
            group: "Basic",
            keywords: []
        )
    }
}

extension ComputeDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Compute",
            description: "Simple compute shader that copies data between GPU buffers",
            group: "Basic",
            keywords: ["needs-work"]
        )
    }
}

extension DepthDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Depth Buffer",
            description: """
            Demonstrates rendering depth buffer to texture. It also shows how to use customisable private functions.
            """,
            group: "Complex",
            keywords: []
        )
    }
}

#if canImport(MetalFX)
extension MetalFXDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "MetalFX Upscaling",
            description: "Image upscaling using MetalFX spatial upsampling for enhanced image quality",
            group: "Basic",
            keywords: ["metalfx", "needs-work"]
        )
    }
}
#endif

extension BouncingTeapotsDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Bouncing Teapots",
            description: """
            Physics simulation of animated teapots with MetalFX upscaling and instanced rendering
            """,
            group: "Complex",
            keywords: ["metalfx", "animated", "multipass"]
        )
    }
}

extension BlinnPhongDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Blinn-Phong Lighting",
            description: "3D lighting demonstration using the Blinn-Phong shading model with animated lights",
            group: "Basic",
            keywords: ["lighting", "multipass", "animated"]
        )
    }
}

extension HitTestDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Hit Test Demo",
            description: """
            Teapot rendering with hit test pipeline that outputs geometry ID,
            instance ID, triangle ID, depth, and barycentric coordinates
            """,
            group: "Complex",
            keywords: ["hit-test", "picking", "multipass"]
        )
    }
}

extension SkyboxDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Skybox",
            description: "Environment mapping demonstration using cube textures for 360-degree backgrounds",
            group: "Basic",
            keywords: []
        )
    }
}

extension AppleEventLogoDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(name: "Apple Event Logo", group: "Complex", keywords: ["needs-work", "animated", "video"])
    }
}

extension LUTDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "LUT Color Grading",
            description: "Color grading and correction using Look-Up Tables (LUTs) for cinematic effects",
            group: "Basic",
            keywords: ["post-processing"]
        )
    }
}

#if os(macOS)
extension OffscreenDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Offscreen Rendering",
            description: """
            Render-to-texture demonstration showing offscreen rendering capabilities
            """,
            group: "Basic",
            keywords: ["needs-work"]
        )
    }
}
#endif

extension MixedDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Mixed Techniques",
            description: "Combination of multiple rendering techniques including lighting and animation",
            group: "Complex",
            keywords: ["multipass", "animated"]
        )
    }
}

extension ColorAdjustDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "ColorAdjustDemoView",
            description: "TODO",
            group: "In-progress",
            keywords: []
        )
    }
}

extension DebugShadersDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Debug Shaders",
            description: """
            Shader debugging visualization with various modes including normals,
            UV coordinates, depth, wireframe, and distance fields
            """,
            group: "Basic",
            keywords: []
        )
    }
}

extension PBRDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "PBR Rendering",
            description: """
            Physically Based Rendering with multiple material presets, environment reflections, and animated lighting
            """,
            group: "* Broken",
            keywords: []
        )
    }
}

extension SDFDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "SDF Raymarching",
            description: """
            Real-time signed distance field raymarching with animated shapes, smooth blending, and dynamic lighting
            """,
            group: "Complex",
            keywords: ["animated", "raymarching"]
        )
    }
}

extension PointCloudDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Point Cloud",
            description: """
            Interactive point cloud visualization with thousands of colored points arranged in a torus shape
            """,
            group: "Basic",
            keywords: ["points", "interactive"]
        )
    }
}

extension ParticleEffectsDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Particle Effects",
            description: """
            GPU-accelerated particle system with compute shaders featuring various
            emitter types like fountains, explosions, and fireworks
            """,
            group: "Complex",
            keywords: ["compute", "animated"]
        )
    }
}

extension VideoPlaybackDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Video Playback",
            description: "Full screen video playback with streaming textures rendered through billboard pipeline",
            group: "Basic",
            keywords: ["video", "billboard"]
        )
    }
}

extension PanoramaDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "360° Panorama",
            description: """
            Interactive 360-degree panoramic photo viewer with spherical projection and WorldView rotation
            """,
            group: "Basic",
            keywords: []
        )
    }
}

extension WireframeDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Wireframe Teapot",
            description: "Wireframe demo",
            group: "Basic",
            keywords: []
        )
    }
}

#if os(iOS)
extension ARKitDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(name: "ARKit Demo", description: "TODO", group: "WIP", keywords: [])
    }
}
#endif

extension TrivialMeshDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Trivial Mesh",
            description: """
            Demonstration of procedurally generated geometric primitives
            (box, tetrahedron, octahedron) with Blinn-Phong lighting
            """,
            group: "Basic",
            keywords: ["mesh", "procedural", "lighting", "animated"]
        )
    }
}

extension SceneGraphDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Scene Graph",
            description: "Scene graph traversal demo showing stacked row/column transforms rendered as a 4×4 grid",
            group: "Basic",
            keywords: ["scene", "graph", "lighting"]
        )
    }
}

extension GLTFDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "glTF Model Viewer",
            description: "TODO",
            group: "Complex",
            keywords: []
        )
    }
}

extension VoxelDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Voxel Renderer"
        )
    }
}

extension GrassDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Grass Sphere",
            description: "Procedural grass rendering on a sphere using Object and Mesh shaders with uniform point distribution",
            group: "Complex",
            keywords: ["mesh-shaders", "procedural", "animated"]
        )
    }
}
extension GraphicsContext3DDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "GraphicsContext3D",
            description: "SwiftUI.Canvas-style API for rendering 3D geometry with Path3D and stroke/fill operations",
            group: "Basic",
            keywords: ["3d", "path", "canvas"]
        )
    }
}

extension EdgeLinesDemoView: @retroactive DemoView {
    public static var metadata: DemoMetadata {
        DemoMetadata(
            name: "Edge Rendering",
            description: "Screen-space edge rendering with rounded endcaps using mesh shaders. Each mesh edge is rendered as a screen-aligned line with adaptive tessellation.",
            group: "Complex",
            keywords: ["mesh-shaders", "wireframe", "edges", "animated"]
        )
    }
}
