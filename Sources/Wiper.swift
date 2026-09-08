import Foundation

/// A parked, single-pivot beam wiper. The same swept geometry moves water and
/// draws the blade, so clearing never runs ahead of the visible rubber edge.
struct WiperPose {
    var pivot: SIMD2<Float>
    var angle: Float
    var inner: Float
    var outer: Float
    var scale: Float
    var direction: Float
    var axis: SIMD2<Float> { SIMD2(cos(angle), sin(angle)) }
    var leading: SIMD2<Float> { SIMD2(-axis.y, axis.x) * direction }
    func point(_ radius: Float) -> SIMD2<Float> { pivot + axis * radius }

    func crosses(_ point: SIMD2<Float>, radius: Float, from previous: WiperPose) -> Bool {
        let offset = point - pivot
        let distance = sqrt(offset.x * offset.x + offset.y * offset.y)
        guard distance + radius >= inner, distance - radius <= outer else { return false }
        var theta = atan2(offset.y, offset.x)
        if theta < 0 { theta += 2 * .pi }
        let margin = asin(min(1, (radius + 3.5 * scale) / max(1, distance)))
        return theta >= min(angle, previous.angle) - margin && theta <= max(angle, previous.angle) + margin
    }
}

struct WiperMotion {
    static let duration: Float = 2.35
    static let outward: Float = 1.05
    static let turn: Float = 0.12
    static let bins = 48
    private(set) var active = false
    private(set) var age: Float = 0
    private(set) var carried = [Float](repeating: 0, count: bins)
    private(set) var removedVolume: Float = 0
    private var emptiedAtTurn = false

    mutating func start() -> Bool {
        guard !active else { return false }
        active = true; age = 0; emptiedAtTurn = false
        carried = [Float](repeating: 0, count: Self.bins)
        return true
    }
    mutating func reset() { self = WiperMotion() }
    mutating func advance(_ dt: Float) {
        guard active else { return }
        age = min(Self.duration, age + dt)
        // The blade and its collected water have passed below the screen edge.
        if age >= Self.outward && !emptiedAtTurn {
            discharge(); emptiedAtTurn = true
        }
        if age >= Self.duration { discharge(); active = false }
    }
    private mutating func discharge() {
        removedVolume += carried.reduce(0, +)
        carried = [Float](repeating: 0, count: Self.bins)
    }
    mutating func drainIfParked() {
        if age >= Self.duration || (age >= Self.outward && age <= Self.outward + Self.turn) { discharge() }
    }
    mutating func collect(position: SIMD2<Float>, volume: Float, pose: WiperPose) {
        let d = position - pose.pivot
        let r = sqrt(d.x * d.x + d.y * d.y)
        let bin = min(Self.bins - 1, max(0, Int((r - pose.inner) / (pose.outer - pose.inner) * Float(Self.bins))))
        carried[bin] += volume
    }
    func pose(size: SIMD2<Float>) -> WiperPose {
        let scale = min(1.5, max(0.65, size.y / 900))
        let pivot = SIMD2(size.x * 0.5, size.y + 32 * scale)
        let outer = sqrt(pow(size.x * 0.5, 2) + pivot.y * pivot.y) + 12 * scale
        let phase: Float
        let returning = age > Self.outward + Self.turn
        if age <= Self.outward { phase = age / Self.outward }
        else if !returning { phase = 1 }
        else { phase = 1 - (age - Self.outward - Self.turn) / (Self.duration - Self.outward - Self.turn) }
        let eased = 0.5 - 0.5 * cos(min(1, max(0, phase)) * .pi)
        return WiperPose(pivot: pivot, angle: .pi - 0.025 + eased * (.pi + 0.05),
                         inner: 48 * scale, outer: outer, scale: scale, direction: returning ? -1 : 1)
    }

    func sprites(size: SIMD2<Float>) -> [GlassSprite] {
        guard active else { return [] }
        let p = pose(size: size), axis = p.axis
        var result: [GlassSprite] = []
        func segment(_ start: SIMD2<Float>, _ end: SIMD2<Float>, width: Float, kind: Float, opacity: Float = 1) -> GlassSprite {
            let d = end - start, length = sqrt(d.x * d.x + d.y * d.y)
            return GlassSprite(center: (start + end) * 0.5, extent: SIMD2(width, length * 0.5 + 6 * p.scale),
                               axis: d / max(0.001, length), age: age, seed: 0.42, kind: kind, opacity: opacity)
        }
        let spacing = (p.outer - p.inner) / Float(Self.bins)
        for i in carried.indices where carried[i] > 0 {
            let width = min(7 * p.scale, 0.65 * pow(carried[i], 1 / Float(3)))
            let center = p.point(p.inner + (Float(i) + 0.5) * spacing) + p.leading * (3.3 * p.scale + width * 0.65)
            result.append(GlassSprite(center: center, extent: SIMD2(max(0.6, width), spacing * 0.56),
                                      axis: axis, age: age, seed: Float(i) * 0.173, kind: 5, opacity: min(0.8, width * 0.24)))
        }
        let hinge = p.point(p.inner + (p.outer - p.inner) * 0.47)
        let side = SIMD2(axis.y, -axis.x)
        let armEnd = hinge + side * 12 * p.scale
        result.append(segment(p.pivot, armEnd, width: 8 * p.scale, kind: 7))
        result.append(segment(armEnd, hinge, width: 8 * p.scale, kind: 7))
        result.append(segment(p.point(p.inner), p.point(p.outer), width: 11 * p.scale, kind: 6))
        result.append(GlassSprite(center: hinge, extent: SIMD2(8 * p.scale, 13 * p.scale), axis: axis,
                                  age: age, seed: 0.42, kind: 8, opacity: 1))
        return result
    }
}
