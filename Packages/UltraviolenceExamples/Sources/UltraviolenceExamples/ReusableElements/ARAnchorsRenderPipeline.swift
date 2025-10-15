#if os(iOS)
import ARKit
import Ultraviolence

struct ARAnchorsRenderPipeline: Element {
    var viewProjectionMatrix: float4x4
    var anchors: [ARAnchor]
    var showMeshes: Bool
    var showPlanes: Bool
    var limitAnchors: Bool

    var body: some Element {
        get throws {
            let allMeshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            let allPlaneAnchors = anchors.compactMap { $0 as? ARPlaneAnchor }

            let meshAnchors = limitAnchors ? Array(allMeshAnchors.prefix(1)) : allMeshAnchors
            let planeAnchors = limitAnchors ? Array(allPlaneAnchors.prefix(1)) : allPlaneAnchors

            try Group {
                if showMeshes {
                    ForEach(Array(meshAnchors.enumerated()), id: \.offset) { _, meshAnchor in
                        let localToWorld = meshAnchor.transform
                        let mvp = viewProjectionMatrix * localToWorld
                        try ARMeshRenderPipeline(mvpMatrix: mvp, meshGeometry: meshAnchor.geometry, color: [0, 1, 1, 0.3])
                    }
                }

                if showPlanes {
                    ForEach(Array(planeAnchors.enumerated()), id: \.offset) { _, planeAnchor in
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
