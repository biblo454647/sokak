import Foundation

/// A small, deterministic surface-water simulation in logical screen points.
/// Fixed steps keep coalescence and runoff consistent at 30 and 60 fps.
struct GlassDrop {
    var position: SIMD2<Float>
    var radius: Float
    var velocity: Float = 0
    var age: Float = 0
    var life: Float
    var seed: Float
    var anchor: SIMD2<Float>
    var snow: Bool = false
}

struct GlassTrail {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var width: Float
    var age: Float = 0
    var seed: Float
}

/// Matches GlassSprite in Weather.metal (48 bytes, no platform-specific types).
struct GlassSprite {
    var center: SIMD2<Float>
    var extent: SIMD2<Float>
    var axis: SIMD2<Float>
    var age: Float
    var seed: Float
    var kind: Float
    var opacity: Float
    var padding: SIMD2<Float> = .zero
}

final class GlassSimulation {
    static let maxDrops = 240
    static let maxTrails = 640
    private(set) var drops: [GlassDrop] = []
    private(set) var trails: [GlassTrail] = []
    private(set) var elapsed: Float = 0
    private(set) var impacts = 0
    private(set) var merges = 0
    private var state: UInt64
    private var size = SIMD2<Float>(1440, 900)
    private var weather: Weather = .rain
    private var remainder: Float = 0
    private var untilImpact: Float = 0
    private var initialized = false

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed }

    private func random() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float((state >> 40) & 0xffffff) / Float(0x1000000)
    }

    func reset(size: SIMD2<Float>, weather: Weather, intensity: Float, populate: Bool = true) {
        self.size = size; self.weather = weather
        drops.removeAll(keepingCapacity: true); trails.removeAll(keepingCapacity: true)
        elapsed = 0; remainder = 0; untilImpact = 0.1; impacts = 0; merges = 0
        initialized = true
        guard populate, weather != .mist else { return }
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        let count = Int((weather == .rain ? 75 + intensity * 70 : 8 + intensity * 12) * area)
        for _ in 0..<count {
            let p = SIMD2(random() * size.x, random() * size.y)
            addImpact(at: p, radius: weather == .rain ? 1.8 + pow(random(), 2) * 9.0 : 2.5 + random() * 3.5)
            drops[drops.count - 1].age = 1 + random() * 4
        }
        impacts = 0
    }

    func addImpact(at position: SIMD2<Float>, radius: Float) {
        guard drops.count < Self.maxDrops else { return }
        let r = min(18, max(0.7, radius))
        drops.append(GlassDrop(position: position, radius: r,
                               life: weather == .snow ? 7 + random() * 12 : 18 + random() * 28,
                               seed: random(), anchor: position, snow: weather == .snow))
        impacts += 1
    }

    func update(deltaTime: Float, size: SIMD2<Float>, weather: Weather, intensity: Float, wind: Float, gentle: Bool) {
        guard size.x > 0, size.y > 0 else { return }
        if !initialized || self.size != size || self.weather != weather {
            reset(size: size, weather: weather, intensity: intensity)
        }
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        // A delayed frame never becomes an explosive catch-up after sleep or a resize.
        remainder += min(deltaTime, 0.1)
        let step: Float = 1 / 120
        while remainder + 0.000001 >= step {
            tick(step * (gentle ? 0.55 : 1), intensity: intensity, wind: wind)
            remainder = max(0, remainder - step)
        }
    }

    private func tick(_ dt: Float, intensity: Float, wind: Float) {
        elapsed += dt
        guard weather != .mist else { return }
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        untilImpact -= dt
        if untilImpact <= 0 {
            let rate = (weather == .rain ? 4 + intensity * 15 : 0.7 + intensity * 2.0) * area
            untilImpact += max(0.025, -log(max(0.001, random())) / rate)
            let radius = weather == .rain ? 2.1 + pow(random(), 2.3) * 10.4 : 3.0 + random() * 4.0
            addImpact(at: SIMD2(random() * size.x, random() * (size.y + 40) - 20), radius: radius)
        }
        for i in trails.indices { trails[i].age += dt }
        trails.removeAll { $0.age > 5.0 }
        for i in drops.indices {
            drops[i].age += dt
            if drops[i].snow { continue }
            let threshold = 3.5 + drops[i].seed * 1.9
            // Surface tension holds small beads. Deposited water gradually adds mass.
            drops[i].radius += dt * intensity * 0.025
            if drops[i].radius > threshold && drops[i].age > 0.18 {
                let slip = 0.68 + 0.32 * sin(drops[i].position.y * 0.045 + drops[i].seed * 19)
                let target = min(265, (drops[i].radius - threshold + 0.45) * 44) * slip
                drops[i].velocity += (target - drops[i].velocity) * min(1, dt * 2.2)
                let distance = drops[i].velocity * dt
                drops[i].position.y += distance
                drops[i].position.x += distance * (sin(drops[i].position.y * 0.026 + drops[i].seed * 31) * 0.075 + wind * 0.025)
                let offset = drops[i].position - drops[i].anchor
                if offset.x * offset.x + offset.y * offset.y > 25 {
                    trails.append(GlassTrail(start: drops[i].anchor, end: drops[i].position,
                                             width: max(0.8, drops[i].radius * 0.28), seed: drops[i].seed))
                    drops[i].anchor = drops[i].position
                }
            }
        }
        // Merge close beads using volume and momentum, so a growing drop really runs.
        if weather == .rain {
            var i = 0
            while i < drops.count {
                var j = i + 1
                while j < drops.count {
                    let delta = drops[i].position - drops[j].position
                    let reach = (drops[i].radius + drops[j].radius) * 0.82
                    if abs(delta.x) < reach && abs(delta.y) < reach && delta.x * delta.x + delta.y * delta.y < reach * reach {
                        let a = pow(drops[i].radius, 3), b = pow(drops[j].radius, 3)
                        drops[i].position = (drops[i].position * a + drops[j].position * b) / (a + b)
                        drops[i].velocity = (drops[i].velocity * a + drops[j].velocity * b) / (a + b)
                        drops[i].radius = min(18, pow(a + b, 1 / Float(3)))
                        drops[i].life = max(drops[i].life, drops[j].life)
                        drops[i].age = max(0.2, min(drops[i].age, drops[j].age))
                        drops[i].anchor = drops[i].position
                        drops.remove(at: j); merges += 1
                    } else { j += 1 }
                }
                i += 1
            }
        }
        drops.removeAll { $0.position.y > size.y + 35 || $0.age > $0.life }
        if trails.count > Self.maxTrails { trails.removeFirst(trails.count - Self.maxTrails) }
    }

    var sprites: [GlassSprite] {
        var result: [GlassSprite] = []
        result.reserveCapacity(trails.count + drops.count * 2)
        for trail in trails {
            let d = trail.end - trail.start
            let length = sqrt(d.x * d.x + d.y * d.y)
            guard length > 0.01 else { continue }
            result.append(GlassSprite(center: (trail.start + trail.end) * 0.5,
                                      extent: SIMD2(trail.width, length * 0.5 + trail.width), axis: d / length,
                                      age: trail.age, seed: trail.seed, kind: 1, opacity: pow(max(0, 1 - trail.age / 5), 1.6)))
        }
        for drop in drops {
            let fade = min(1, max(0, (drop.life - drop.age) / (drop.snow ? 3 : 2)))
            let hit = exp(-drop.age * 17)
            let stretch = min(0.65, drop.velocity / 240)
            let extent = SIMD2(drop.radius * (1 + hit * 0.6), drop.radius * (1 - hit * 0.35 + stretch))
            result.append(GlassSprite(center: drop.position, extent: extent, axis: SIMD2(0, 1),
                                      age: drop.age, seed: drop.seed, kind: drop.snow ? 3 : 0, opacity: fade))
            if !drop.snow && drop.age < 0.32 && drop.radius > 3.2 {
                let spread = drop.radius + drop.age * 36
                result.append(GlassSprite(center: drop.position, extent: SIMD2(repeating: spread), axis: SIMD2(0, 1),
                                          age: drop.age, seed: drop.seed, kind: 2, opacity: (1 - drop.age / 0.32) * 0.32))
            }
        }
        return result
    }
}
