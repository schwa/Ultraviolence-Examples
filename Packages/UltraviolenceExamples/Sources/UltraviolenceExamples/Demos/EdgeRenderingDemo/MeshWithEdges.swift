import Foundation

/// Helper struct for edge hashing - uses canonical ordering
struct Edge: Hashable {
    let startIndex: UInt32
    let endIndex: UInt32

    init(_ a: UInt32, _ b: UInt32) {
        // Canonical ordering: smaller index first
        if a < b {
            startIndex = a
            endIndex = b
        } else {
            startIndex = b
            endIndex = a
        }
    }
}

/// A mesh with precomputed unique edges for efficient edge rendering
struct MeshWithEdges {
    let mesh: Mesh
    let uniqueEdges: [(startIndex: UInt32, endIndex: UInt32)]
}

extension MeshWithEdges {
    /// Extract unique edges from a mesh by processing all triangles
    nonisolated static func extractEdges(from mesh: Mesh) -> [(startIndex: UInt32, endIndex: UInt32)] {
        var edgeSet = Set<Edge>()
        var uniqueEdges: [(startIndex: UInt32, endIndex: UInt32)] = []

        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indices.buffer
            let offset = submesh.indices.offset
            let ptr = indexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt32.self)

            let triangleCount = submesh.indices.count / 3
            for triangleIndex in 0..<triangleCount {
                let i0 = ptr[triangleIndex * 3 + 0]
                let i1 = ptr[triangleIndex * 3 + 1]
                let i2 = ptr[triangleIndex * 3 + 2]

                let edges = [
                    Edge(i0, i1),
                    Edge(i1, i2),
                    Edge(i2, i0)
                ]

                for edge in edges where edgeSet.insert(edge).inserted {
                    uniqueEdges.append((edge.startIndex, edge.endIndex))
                }
            }
        }

        return uniqueEdges
    }

    /// Create a MeshWithEdges from a Mesh by extracting its unique edges
    init(mesh: Mesh) {
        self.mesh = mesh
        self.uniqueEdges = Self.extractEdges(from: mesh)
    }
}
