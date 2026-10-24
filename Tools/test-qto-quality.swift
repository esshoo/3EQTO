import Foundation

/// Compiles alongside the app's actual QTOQualityCore.swift, on Linux and macOS.
/// No reimplementation of the production algorithms is used as the test target.
@main
struct QualityRegressionTests {
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError("FAIL: \(message)") }
    }
    static func near(_ actual: Double, _ expected: Double, _ message: String, tolerance: Double = 1e-6) {
        expect(actual.isFinite && abs(actual - expected) <= tolerance, "\(message): \(actual) != \(expected)")
    }
    static func corners(_ xy: [[Float]]) -> [[Float]] { xy.map { [$0[0], $0[1], 0] } }
    static func verifyTriangulation(_ corners: [[Float]], _ expectedArea: Double, _ label: String) {
        guard let polygon = QTOQualityMath.floorPolygon(corners),
              let indices = QTOQualityMath.triangles(polygon) else { fatalError("FAIL: \(label) triangulation") }
        expect(indices.count == (polygon.count - 2) * 3, "\(label) triangle count")
        var area = 0.0
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let triangle = Array(indices[offset..<(offset + 3)]).map { polygon[Int($0)] }
            let value = QTOQualityMath.signedArea(triangle)
            expect(value > 0, "\(label) winding / zero-area triangle")
            area += value
        }
        near(area, expectedArea, "\(label) area conservation", tolerance: max(expectedArea * 1e-6, 1e-6))
    }
    static func main() {
        let rectangle = corners([[0,0], [4,0], [4,3], [0,3]])
        let lShape = corners([[0,0], [4,0], [4,1], [1,1], [1,3], [0,3]])
        near(Double(QTOQualityMath.floorArea(corners: rectangle, width: 4, depth: 3)), 12, "rectangle")
        near(Double(QTOQualityMath.floorArea(corners: lShape, width: 4, depth: 3)), 6, "L-shaped floor uses polygon, not 12m2 box")
        verifyTriangulation(lShape, 6, "concave L")
        verifyTriangulation(Array(lShape.reversed()), 6, "clockwise L")
        verifyTriangulation(rectangle, 12, "rectangle")
        verifyTriangulation(rectangle + [rectangle[0]], 12, "closed polygon")
        verifyTriangulation(corners([[0,0],[2,0],[4,0],[4,3],[0,3],[0,3]]), 12, "duplicates and collinear")
        verifyTriangulation(corners([[1000,1000],[1004,1000],[1004,1003],[1000,1003]]), 12, "translated polygon")
        let malformed: [[[Float]]?] = [
            nil, [], [[1,2,3]], [[0,0],[4,0],[4,3],[0,3]],
            corners([[0,0],[4,3],[0,3],[4,0]]), // bow-tie
            corners([[0,0],[1,0],[2,0]]),
            [[0,0,0],[4,0,0],[4,3,0.5],[0,3,0]],
            [[0,0,0],[.nan,0,0],[4,3,0],[0,3,0]],
            [[0,0,0],[.infinity,0,0],[4,3,0],[0,3,0]],
            corners([[0,0],[4,0],[4,3],[1,0],[0,3]]) // non-adjacent touch
        ]
        for (i, value) in malformed.enumerated() {
            expect(QTOQualityMath.floorPolygon(value) == nil, "malformed \(i) rejected")
            near(Double(QTOQualityMath.floorArea(corners: value, width: 4, depth: 3)), 12, "legacy fallback \(i)")
        }
        near(Double(QTOQualityMath.positiveProduct(-1, 3)), 0, "negative size")
        near(Double(QTOQualityMath.positiveProduct(.nan, 3)), 0, "NaN size")
        near(Double(QTOQualityMath.positiveProduct(.greatestFiniteMagnitude, 3)), 0, "overflow size")
        let wall = QTORect(minX: -2, minY: -1.5, maxX: 2, maxY: 1.5)
        let a = QTORect(minX: 0, minY: 0, maxX: 2, maxY: 2)
        let b = QTORect(minX: 1, minY: 1, maxX: 3, maxY: 3)
        near(QTOQualityMath.unionArea([a, b]), 7, "overlap not deducted twice")
        near(QTOQualityMath.unionArea([a, a, a]), 4, "identical apertures")
        near(QTOQualityMath.unionArea([a, QTORect(minX: 0.5,minY: 0.5,maxX: 1,maxY: 1)]), 4, "nested aperture")
        near(QTOQualityMath.unionArea([a, QTORect(minX: 2,minY: 0,maxX: 4,maxY: 2)]), 8, "touching rectangles")
        near(QTOQualityMath.unionArea([a, b].compactMap { $0.clipped(to: wall) }), 3, "wall clipping and union")
        expect(QTORect(minX: 3,minY: 0,maxX: 4,maxY: 1).clipped(to: wall) == nil, "outside aperture")
        near(QTOQualityMath.unionArea([QTORect(minX: .nan,minY: 0,maxX: 3,maxY: 1)]), 0, "invalid rectangle")
        // Reproducible property tests: rectangle sweep versus integer-cell coverage.
        var state: UInt64 = 0x3E_0710
        func random(_ max: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(max))
        }
        for caseIndex in 0..<400 {
            var rects: [QTORect] = []
            var cells: Set<Int> = []
            for _ in 0..<(1 + random(12)) {
                let x = random(12), y = random(12), right = x + 1 + random(6), top = y + 1 + random(6)
                rects.append(QTORect(minX: Double(x), minY: Double(y), maxX: Double(right), maxY: Double(top)))
                for xx in x..<right { for yy in y..<top { cells.insert(xx * 100 + yy) } }
            }
            near(QTOQualityMath.unionArea(rects), Double(cells.count), "union property \(caseIndex)")
        }
        // Simple star-shaped polygons (concave and convex) around the origin.
        for caseIndex in 0..<150 {
            let count = 3 + random(25)
            let points = (0..<count).map { index -> [Float] in
                let angle = 2 * Double.pi * Double(index) / Double(count)
                let radius = 1 + Double(random(400)) / 100
                return [Float(cos(angle) * radius), Float(sin(angle) * radius), 0]
            }
            guard let polygon = QTOQualityMath.floorPolygon(points) else { fatalError("invalid generated polygon") }
            verifyTriangulation(points, abs(QTOQualityMath.signedArea(polygon)), "polygon property \(caseIndex)")
        }
        for level in 0...3 {
            let caps = [60, 30, 15, 10]
            for request in [15,24,30,60,120] {
                for lowPower in [false, true] {
                    let budget = QTOFrameBudget.resolve(requestedFPS: request, antialiasing: 4, thermalLevel: level, lowPower: lowPower)
                    expect(budget.framesPerSecond <= caps[level], "thermal FPS cap")
                    expect(budget.framesPerSecond <= request, "do not raise requested FPS")
                    expect(!lowPower || budget.framesPerSecond <= 24, "low-power FPS cap")
                    expect(level < 2 && !lowPower || budget.antialiasing == 0, "expensive AA off")
                    expect(!budget.allowsShadows || (level == 0 && !lowPower), "shadows only nominal")
                }
            }
        }
        expect(QTOFrameBudget.referenceImageInterval(thermalLevel: 3, lowPower: false).isInfinite, "no critical-state reference snapshots")
        let gate = QTOFrameGate(interval: 0.1)
        expect(gate.shouldDeliver(at: 1), "first frame")
        expect(!gate.shouldDeliver(at: 1.01), "drop burst frame")
        expect(!gate.shouldDeliver(at: 3), "coalesce while main actor is busy")
        gate.completeDelivery()
        expect(!gate.shouldDeliver(at: 1.01), "interval still applies after completion")
        expect(gate.shouldDeliver(at: 1.11), "accept next interval")
        expect(!gate.shouldDeliver(at: .nan), "reject NaN timestamp")
        gate.completeDelivery()
        expect(gate.shouldDeliver(at: 0), "new AR session timestamp reset")
        gate.completeDelivery()
        print("PASS: \(checks) actual Swift assertions (including 550 generated geometry cases)")
    }
}
