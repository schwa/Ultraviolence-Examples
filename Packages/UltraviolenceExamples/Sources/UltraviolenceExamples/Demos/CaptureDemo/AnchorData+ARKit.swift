#if os(iOS)
import ARKit
import Foundation

extension AnchorData {
    init(anchor: ARAnchor) throws {
        self.identifier = anchor.identifier.uuidString
        let transform = anchor.transform
        self.transform = [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w, transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w, transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w, transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
        if let planeAnchor = anchor as? ARPlaneAnchor {
            self.anchorType = "plane"
            let geometry = planeAnchor.geometry
            var vertexArray: [[Float]] = []
            for i in 0..<geometry.boundaryVertices.count {
                let vertex = geometry.boundaryVertices[i]
                vertexArray.append([vertex.x, vertex.y, vertex.z])
            }
            self.planeGeometry = AnchorData.PlaneGeometry(vertices: vertexArray)
            self.meshGeometry = nil
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            self.anchorType = "mesh"
            self.planeGeometry = nil
            let vertices = meshAnchor.geometry.vertices
            let faces = meshAnchor.geometry.faces
            // swiftlint:disable:next empty_count
            guard vertices.count > 0, faces.count > 0 else {
                self.meshGeometry = nil
                return
            }
            let vertexBuffer = vertices.buffer
            let faceBuffer = faces.buffer
            guard vertexBuffer.length > 0, faceBuffer.length > 0 else {
                self.meshGeometry = nil
                return
            }
            let vertexByteCount = vertices.count * vertices.stride
            let faceByteCount = faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex
            guard vertexByteCount > 0, faceByteCount > 0, vertexByteCount <= vertexBuffer.length, faceByteCount <= faceBuffer.length else {
                self.meshGeometry = nil
                return
            }
            let vertexBufferPointer = vertexBuffer.contents().advanced(by: vertices.offset)
            let vertexData = Data(bytes: vertexBufferPointer, count: vertexByteCount)
            let faceBufferPointer = faceBuffer.contents()
            let faceData = Data(bytes: faceBufferPointer, count: faceByteCount)
            self.meshGeometry = AnchorData.MeshGeometry(vertexData: vertexData, vertexCount: vertices.count, vertexStride: vertices.stride, faceData: faceData, faceCount: faces.count)
        } else {
            self.anchorType = "generic"
            self.planeGeometry = nil
            self.meshGeometry = nil
        }
    }
}

#endif
