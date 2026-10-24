import Foundation

/// Shared, platform-independent calculation and resource-budget rules.
/// These exact functions are exercised by Tools/test-qto-quality.swift in CI.
struct QTOPoint2: Equatable {
    var x: Double
    var y: Double
}

struct QTORect: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var isValid: Bool {
        [minX, minY, maxX, maxY].allSatisfy(\.isFinite)
            && maxX > minX && maxY > minY
    }

    var area: Double { isValid ? (maxX - minX) * (maxY - minY) : 0 }

    func clipped(to bounds: QTORect) -> QTORect? {
        guard isValid, bounds.isValid else { return nil }
        let result = QTORect(
            minX: max(minX, bounds.minX), minY: max(minY, bounds.minY),
            maxX: min(maxX, bounds.maxX), maxY: min(maxY, bounds.maxY)
        )
        return result.isValid ? result : nil
    }
}

enum QTOQualityMath {
    static func positiveProduct(_ first: Float, _ second: Float) -> Float {
        guard first.isFinite, second.isFinite, first > 0, second > 0 else { return 0 }
        let value = first * second
        return value.isFinite ? value : 0
    }

    /// RoomPlan polygonCorners are in the surface's local XY plane, in metres.
    /// Reject malformed/non-planar/self-intersecting data, retaining a labelled
    /// rectangular fallback for legacy scans rather than inventing a footprint.
    static func floorPolygon(_ corners: [[Float]]?) -> [QTOPoint2]? {
        guard let corners, (3...512).contains(corners.count),
              corners.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) }),
              corners.allSatisfy({ abs($0[2]) <= 0.025 }) else { return nil }
        var points: [QTOPoint2] = []
        for corner in corners {
            let point = QTOPoint2(x: Double(corner[0]), y: Double(corner[1]))
            if let last = points.last, distanceSquared(last, point) < 1e-12 { continue }
            points.append(point)
        }
        if points.count > 2, distanceSquared(points[0], points[points.count - 1]) < 1e-12 {
            points.removeLast()
        }
        // Collinear points are redundant and can prevent ear clipping.
        var didRemove = true
        while didRemove && points.count > 3 {
            didRemove = false
            for index in points.indices {
                let a = points[(index + points.count - 1) % points.count]
                let b = points[index]
                let c = points[(index + 1) % points.count]
                if abs(cross(a, b, c)) < 1e-10,
                   (b.x - a.x) * (b.x - c.x) + (b.y - a.y) * (b.y - c.y) <= 1e-10 {
                    points.remove(at: index)
                    didRemove = true
                    break
                }
            }
        }
        guard points.count >= 3, abs(signedArea(points)) > 1e-6 else { return nil }
        for i in points.indices {
            let nextI = (i + 1) % points.count
            for j in points.indices where j > i {
                let nextJ = (j + 1) % points.count
                if nextI == j || nextJ == i { continue }
                if segmentsIntersect(points[i], points[nextI], points[j], points[nextJ]) {
                    return nil
                }
            }
        }
        return points
    }

    static func signedArea(_ points: [QTOPoint2]) -> Double {
        guard points.count >= 3 else { return 0 }
        // Translate to the first vertex to reduce cancellation for large offsets.
        let origin = points[0]
        var twiceArea = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            twiceArea += (a.x - origin.x) * (b.y - origin.y)
                - (b.x - origin.x) * (a.y - origin.y)
        }
        return twiceArea / 2
    }

    static func floorArea(corners: [[Float]]?, width: Float, depth: Float) -> Float {
        guard let polygon = floorPolygon(corners) else { return positiveProduct(width, depth) }
        let area = Float(abs(signedArea(polygon)))
        return area.isFinite ? area : positiveProduct(width, depth)
    }

    /// Ear clipping supports concave footprints (e.g. an L-shaped room).
    /// Returned indices refer to the supplied, validated polygon, not its bounds.
    static func triangles(_ polygon: [QTOPoint2]) -> [UInt16]? {
        guard (3...512).contains(polygon.count),
              polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var remaining = Array(polygon.indices)
        if signedArea(polygon) < 0 { remaining.reverse() }
        var result: [UInt16] = []
        while remaining.count > 3 {
            var foundEar = false
            for offset in remaining.indices {
                let a = remaining[(offset + remaining.count - 1) % remaining.count]
                let b = remaining[offset]
                let c = remaining[(offset + 1) % remaining.count]
                guard cross(polygon[a], polygon[b], polygon[c]) > 1e-10 else { continue }
                let containsVertex = remaining.contains { index in
                    guard index != a && index != b && index != c else { return false }
                    let p = polygon[index]
                    return cross(polygon[a], polygon[b], p) >= -1e-10
                        && cross(polygon[b], polygon[c], p) >= -1e-10
                        && cross(polygon[c], polygon[a], p) >= -1e-10
                }
                guard !containsVertex else { continue }
                result.append(contentsOf: [UInt16(a), UInt16(b), UInt16(c)])
                remaining.remove(at: offset)
                foundEar = true
                break
            }
            guard foundEar else { return nil }
        }
        result.append(contentsOf: remaining.map(UInt16.init))
        return result
    }

    /// Union, not sum: overlapping door/window/opening rectangles are deducted
    /// only once. Callers clip each rectangle to its wall before this function.
    static func unionArea(_ rectangles: [QTORect]) -> Double {
        let rectangles = rectangles.filter(\.isValid)
        let xs = Array(Set(rectangles.flatMap { [$0.minX, $0.maxX] })).sorted()
        guard xs.count > 1 else { return 0 }
        var result = 0.0
        for index in 0..<(xs.count - 1) {
            let left = xs[index]
            let right = xs[index + 1]
            let intervals = rectangles.filter { $0.minX < right && $0.maxX > left }
                .sorted { $0.minY < $1.minY }
            guard let first = intervals.first else { continue }
            var low = first.minY
            var high = first.maxY
            var height = 0.0
            for interval in intervals.dropFirst() {
                if interval.minY <= high {
                    high = max(high, interval.maxY)
                } else {
                    height += high - low
                    low = interval.minY
                    high = interval.maxY
                }
            }
            height += high - low
            result += (right - left) * height
        }
        return result.isFinite ? max(result, 0) : 0
    }

    private static func distanceSquared(_ a: QTOPoint2, _ b: QTOPoint2) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    private static func cross(_ a: QTOPoint2, _ b: QTOPoint2, _ c: QTOPoint2) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func segmentsIntersect(
        _ a: QTOPoint2, _ b: QTOPoint2, _ c: QTOPoint2, _ d: QTOPoint2
    ) -> Bool {
        let p = cross(a, b, c), q = cross(a, b, d)
        let r = cross(c, d, a), s = cross(c, d, b)
        if ((p > 1e-10 && q < -1e-10) || (p < -1e-10 && q > 1e-10)),
           ((r > 1e-10 && s < -1e-10) || (r < -1e-10 && s > 1e-10)) { return true }
        func onSegment(_ x: QTOPoint2, _ y: QTOPoint2, _ z: QTOPoint2) -> Bool {
            z.x >= min(x.x, y.x) - 1e-10 && z.x <= max(x.x, y.x) + 1e-10
                && z.y >= min(x.y, y.y) - 1e-10 && z.y <= max(x.y, y.y) + 1e-10
        }
        return (abs(p) <= 1e-10 && onSegment(a, b, c))
            || (abs(q) <= 1e-10 && onSegment(a, b, d))
            || (abs(r) <= 1e-10 && onSegment(c, d, a))
            || (abs(s) <= 1e-10 && onSegment(c, d, b))
    }
}

struct QTOFrameBudget: Equatable {
    let framesPerSecond: Int
    let antialiasing: Int
    let allowsShadows: Bool

    /// ProcessInfo thermal levels: 0 nominal, 1 fair, 2 serious, 3 critical.
    static func resolve(
        requestedFPS: Int, antialiasing: Int, thermalLevel: Int, lowPower: Bool
    ) -> QTOFrameBudget {
        let cap: Int
        switch thermalLevel {
        case 0: cap = 60
        case 1: cap = 30
        case 2: cap = 15
        case 3: cap = 10
        default: cap = 15
        }
        let fps = min(max(requestedFPS, 10), min(cap, lowPower ? 24 : 60))
        let aa = thermalLevel >= 2 || lowPower ? 0 : min(antialiasing, thermalLevel == 1 ? 2 : 4)
        return QTOFrameBudget(
            framesPerSecond: fps, antialiasing: max(0, aa),
            allowsShadows: thermalLevel == 0 && !lowPower && antialiasing >= 4
        )
    }

    static func referenceImageInterval(thermalLevel: Int, lowPower: Bool) -> TimeInterval {
        switch thermalLevel {
        case 0: return lowPower ? 3 : 1.5
        case 1: return 3
        case 2: return 6
        default: return .infinity
        }
    }
}

/// Bounds AR delegate delivery before dispatching a Task to the main actor.
/// No camera buffer is retained by the gate. NSLock protects the timestamp.
final class QTOFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTimestamp: TimeInterval = -.infinity
    private var deliveryInFlight = false
    private let interval: TimeInterval

    init(interval: TimeInterval) { self.interval = max(interval, 0) }

    func shouldDeliver(at timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard !deliveryInFlight,
              timestamp < lastTimestamp || timestamp - lastTimestamp >= interval else { return false }
        lastTimestamp = timestamp
        deliveryInFlight = true
        return true
    }

    func completeDelivery() {
        lock.lock()
        deliveryInFlight = false
        lock.unlock()
    }
}
