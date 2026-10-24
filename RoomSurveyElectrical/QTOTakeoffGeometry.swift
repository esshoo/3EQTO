import Foundation
import simd

/// A shared opening-to-wall rule for takeoff and app-owned 3D geometry.
/// Native RoomPlan parent IDs win only when the geometry is still compatible.
/// Old projects without parent IDs use the same finite, parallel-plane checks.
enum QTOTakeoffGeometry {
    struct Match {
        let wallID: UUID
        let rectangle: QTORect
        let distance: Float
    }

    static func assignOpening(_ surface: SurfaceSnapshot, walls: [WallSnapshot]) -> Match? {
        let candidates = walls.compactMap { projectedOpening(surface, onto: $0) }
        if let parentID = surface.parentWallID,
           let native = candidates.first(where: { $0.wallID == parentID }) { return native }
        return candidates.min {
            if abs($0.distance - $1.distance) > 0.0001 { return $0.distance < $1.distance }
            return $0.wallID.uuidString < $1.wallID.uuidString
        }
    }

    static func projectedOpening(_ surface: SurfaceSnapshot, onto wall: WallSnapshot) -> Match? {
        guard surface.width.isFinite, surface.height.isFinite,
              surface.width > 0, surface.height > 0,
              wall.width.isFinite, wall.height.isFinite, wall.width > 0, wall.height > 0,
              surface.transform.count == 16, wall.transform.count == 16,
              surface.transform.allSatisfy(\.isFinite), wall.transform.allSatisfy(\.isFinite),
              abs(simd_determinant(wall.matrix)) > 0.0001 else { return nil }
        let wallNormal = SIMD3(wall.matrix.columns.2.x, wall.matrix.columns.2.y, wall.matrix.columns.2.z)
        let surfaceNormal = SIMD3(surface.matrix.columns.2.x, surface.matrix.columns.2.y, surface.matrix.columns.2.z)
        guard simd_length(wallNormal) > 0.001, simd_length(surfaceNormal) > 0.001,
              abs(simd_dot(simd_normalize(wallNormal), simd_normalize(surfaceNormal))) >= 0.9659258 else {
            return nil
        }
        let transform = simd_inverse(wall.matrix) * surface.matrix
        let center = transform.columns.3
        // Do not deduct a perpendicular/remote opening from a nearby wall.
        guard abs(center.z) <= 0.20 else { return nil }
        let x = surface.width / 2, y = surface.height / 2
        let corners = [SIMD4<Float>(-x, -y, 0, 1), SIMD4<Float>(x, -y, 0, 1),
                       SIMD4<Float>(x, y, 0, 1), SIMD4<Float>(-x, y, 0, 1)]
            .map { transform * $0 }
        guard corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              corners.allSatisfy({ abs($0.z) <= 0.25 }) else { return nil }
        let projected = QTORect(
            minX: Double(corners.map(\.x).min()!), minY: Double(corners.map(\.y).min()!),
            maxX: Double(corners.map(\.x).max()!), maxY: Double(corners.map(\.y).max()!)
        )
        let bounds = QTORect(minX: -Double(wall.width) / 2, minY: -Double(wall.height) / 2,
                             maxX: Double(wall.width) / 2, maxY: Double(wall.height) / 2)
        guard let clipped = projected.clipped(to: bounds), clipped.area > 0.0001 else { return nil }
        return Match(wallID: wall.id, rectangle: clipped, distance: abs(center.z))
    }
}
