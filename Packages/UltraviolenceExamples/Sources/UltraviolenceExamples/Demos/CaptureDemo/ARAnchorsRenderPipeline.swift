#if os(iOS)
import ARKit
import simd
import SwiftUI
import Ultraviolence

struct ARAnchorsRenderPipeline: Element {
    var cameraMatrix: float4x4
    var projectionMatrix: float4x4
    var viewport: SIMD2<Float>
    var meshAnchors: [(anchor: ARMeshAnchor, meshWithEdges: MeshWithEdges)]
    var planeAnchors: [ARPlaneAnchor]
    var showMeshes: Bool
    var showPlanes: Bool
    var limitAnchors: Bool

    var body: some Element {
        get throws {
            let limitedMeshAnchors = limitAnchors ? Array(meshAnchors.prefix(1)) : meshAnchors
            let limitedPlaneAnchors = limitAnchors ? Array(planeAnchors.prefix(1)) : planeAnchors
            let viewProjectionMatrix = projectionMatrix * cameraMatrix

            try Group {
                if showMeshes {
                    ForEach(Array(limitedMeshAnchors.enumerated()), id: \.offset) { _, element in
                        let (anchor, meshWithEdges) = element
                        let transforms = Transforms(
                            modelMatrix: anchor.transform,
                            cameraMatrix: cameraMatrix,
                            projectionMatrix: projectionMatrix
                        )
                        try EdgeLinesRenderPass(
                            meshWithEdges: meshWithEdges,
                            transforms: transforms,
                            lineWidth: 2.0,
                            viewport: viewport,
                            colorizeByTriangle: false,
                            edgeColor: [0, 1, 1, 1],  // Cyan
                            debugMode: false
                        )
                    }
                }

                if showPlanes {
                    ForEach(Array(limitedPlaneAnchors.enumerated()), id: \.offset) { _, planeAnchor in
                        let localToWorld = planeAnchor.transform
                        let mvp = viewProjectionMatrix * localToWorld
                        try ARPlaneRenderPipeline(mvpMatrix: mvp, planeAnchor: planeAnchor, color: [0, 1, 0, 1])
                    }
                }
            }
        }
    }
}
#endif
