import LegoDrawFile

extension Array where Element == LDrawWorldTriangle {

    /// The axis-aligned bounding box of every vertex, or `nil` if empty.
    var bounds: (min: Vector3, max: Vector3)? {
        guard !isEmpty else { return nil }
        var minPoint = self[0].vertex1
        var maxPoint = self[0].vertex1
        for triangle in self {
            for vertex in [triangle.vertex1, triangle.vertex2, triangle.vertex3] {
                minPoint = Vector3(
                    x: Swift.min(minPoint.x, vertex.x),
                    y: Swift.min(minPoint.y, vertex.y),
                    z: Swift.min(minPoint.z, vertex.z)
                )
                maxPoint = Vector3(
                    x: Swift.max(maxPoint.x, vertex.x),
                    y: Swift.max(maxPoint.y, vertex.y),
                    z: Swift.max(maxPoint.z, vertex.z)
                )
            }
        }
        return (minPoint, maxPoint)
    }

    /// The center of the bounding box, or `.zero` if empty.
    var boundsCenter: Vector3 {
        guard let bounds else { return .zero }
        return (bounds.min + bounds.max) * 0.5
    }

    /// Half the largest bounding box extent, or a small positive fallback if empty.
    var boundsRadius: Float {
        guard let bounds else { return 100 }
        let size = bounds.max - bounds.min
        return Swift.max(size.x, Swift.max(size.y, size.z)) * 0.5 + 1
    }
}
