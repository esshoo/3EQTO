import Foundation
import simd

// Minimal model adapters: the exact production QTOTakeoffGeometry.swift is
// compiled unchanged by the macOS CI test, without needing a running AR session.
struct WallSnapshot {
    let id: UUID
    let width: Float
    let height: Float
    var matrix: simd_float4x4
    var transform: [Float] { values(matrix) }
}
struct SurfaceSnapshot {
    let width: Float
    let height: Float
    var matrix: simd_float4x4
    var parentWallID: UUID?
    var transform: [Float] { values(matrix) }
}
func values(_ m: simd_float4x4) -> [Float] {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x,$0.y,$0.z,$0.w] }
}
@main
struct WallAssignmentTests {
    static func main() {
        var assertions = 0
        func check(_ value: Bool, _ message: String) {
            assertions += 1
            precondition(value, message)
        }
        let identity = matrix_identity_float4x4
        let wall = WallSnapshot(id: UUID(), width: 4, height: 3, matrix: identity)
        var opening = SurfaceSnapshot(width: 2, height: 2, matrix: identity, parentWallID: wall.id)
        let assigned = QTOTakeoffGeometry.assignOpening(opening, walls: [wall])
        check(assigned?.wallID == wall.id, "native wall ID")
        check(abs((assigned?.rectangle.area ?? 0) - 4) < 1e-5, "aperture area")
        opening.matrix.columns.3.x = 2
        check(abs((QTOTakeoffGeometry.assignOpening(opening, walls: [wall])?.rectangle.area ?? 0) - 2) < 1e-5, "clip beyond wall")
        opening.matrix.columns.3.x = 5
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall]) == nil, "reject remote opening even with native ID")
        opening.matrix = identity
        opening.matrix.columns.3.z = 0.5
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall]) == nil, "reject wrong plane")
        opening.matrix = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0,1,0)))
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall]) == nil, "reject perpendicular surface")
        opening.matrix = identity
        opening.matrix.columns.3.x = .nan
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall]) == nil, "reject malformed coordinates")
        opening.matrix = identity
        opening.parentWallID = nil
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall])?.wallID == wall.id, "legacy projects without parent ID")
        var secondWall = wall
        secondWall = WallSnapshot(id: UUID(), width: 4, height: 3, matrix: identity)
        secondWall.matrix.columns.3.z = 0.1
        opening.parentWallID = secondWall.id
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [wall,secondWall])?.wallID == secondWall.id, "compatible parent preferred to nearest plane")
        opening.parentWallID = nil
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [secondWall,wall])?.wallID == wall.id, "nearest compatible wall for legacy")
        var singular = wall
        singular.matrix.columns.0 = .zero
        check(QTOTakeoffGeometry.assignOpening(opening, walls: [singular]) == nil, "reject singular transform")
        print("PASS: \(assertions) actual SIMD wall-assignment assertions")
    }
}
