import LegoDrawFile

/// Computes a face normal from a polygon's local-space vertices and the effective
/// winding order (folding together the file's declared CW/CCW state, `INVERTNEXT`,
/// and the accumulated sign of nested subfile transform determinants).
enum LDrawBFCNormalResolver {
    static func faceNormal(_ vertices: [Vector3], ccw: Bool) -> Vector3 {
        guard vertices.count >= 3 else { return Vector3(x: 0, y: 1, z: 0) }
        let edge1 = vertices[1] - vertices[0]
        let edge2 = vertices[2] - vertices[0]
        let normal = edge1.cross(edge2)
        return (ccw ? normal : -normal).normalized
    }
}
