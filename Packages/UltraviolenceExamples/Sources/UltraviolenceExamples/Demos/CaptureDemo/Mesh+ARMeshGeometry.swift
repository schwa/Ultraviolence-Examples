#if os(iOS)
import ARKit
import Ultraviolence

extension Mesh {
    init?(arMeshGeometry: ARMeshGeometry) {
        let vertices = arMeshGeometry.vertices
        let faces = arMeshGeometry.faces

        // swiftlint:disable:next empty_count
        guard vertices.count != 0, faces.count != 0 else {
            return nil
        }

        // Use ARKit's buffers directly (no need to copy)
        let vertexBuffer = vertices.buffer
        let indexBuffer = faces.buffer

        // Create vertex descriptor (position only for AR mesh - SIMD3<Float>)
        let vertexDescriptor = VertexDescriptor(
            label: "AR Mesh",
            attributes: [
                .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0)
            ],
            layouts: [
                .init(bufferIndex: 0, stride: vertices.stride, stepFunction: .perVertex, stepRate: 1)
            ]
        )

        // Create mesh
        self.init(
            label: "AR Mesh",
            submeshes: [
                Mesh.Submesh(
                    label: nil,
                    primitiveType: .triangle,
                    indices: Mesh.Buffer(
                        buffer: indexBuffer,
                        count: faces.count * faces.indexCountPerPrimitive,
                        offset: 0
                    )
                )
            ],
            vertexDescriptor: vertexDescriptor,
            vertexBuffers: [
                Mesh.Buffer(
                    buffer: vertexBuffer,
                    count: vertices.count,
                    offset: 0
                )
            ]
        )
    }
}
#endif
