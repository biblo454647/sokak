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
    static let maxDrops = 1800
    static let maxTrails = 900
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
    private var untilMerge: Float = 0
    private var shower: Float = 0.6
    private var showerTarget: Float = 0.6
    private var untilShower: Float = 0
    private var lastIntensity: Float = 0
    private var pendingImpacts: Float = 0
    private var initialized = false

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed }

    private func random() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float((state >> 40) & 0xffffff) / Float(0x1000000)
    }

    func reset(size: SIMD2<Float>, weather: Weather, intensity: Float, populate: Bool = true) {
        self.size = size; self.weather = weather
        drops.removeAll(keepingCapacity: true); trails.removeAll(keepingCapacity: true)
        elapsed = 0; remainder = 0; untilImpact = 0.8; untilMerge = 0; impacts = 0; merges = 0
        shower = 0.6; showerTarget = 0.6; untilShower = 3
        lastIntensity = intensity; pendingImpacts = 0
        initialized = true
        guard populate, weather != .mist else { return }
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        let count = min(Self.maxDrops, Int(weather == .rain ? rainPopulation(intensity) : (8 + intensity * 12) * area))
        for _ in 0..<count {
            let p = SIMD2(random() * size.x, random() * size.y)
            addImpact(at: p, radius: weather == .rain ? beadRadius(intensity) : 2.5 + random() * 3.5)
            drops[drops.count - 1].age = weather == .rain ? 2 + random() * 80 : 1 + random() * 4
        }
        impacts = 0
    }

    func addImpact(at position: SIMD2<Float>, radius: Float) {
        guard drops.count < Self.maxDrops else { return }
        let r = min(22, max(0.55, radius))
        drops.append(GlassDrop(position: position, radius: r,
                               life: weather == .snow ? 7 + random() * 12 : 150 + random() * 270,
                               seed: random(), anchor: position, snow: weather == .snow))
        impacts += 1
    }

    private func rainPopulation(_ intensity: Float) -> Float {
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        return min(Float(Self.maxDrops), (220 + 1050 * pow(intensity, 1.1)) * area)
    }

    private func beadRadius(_ intensity: Float) -> Float {
        // Keep fine beads, but give medium lenses enough area to read at screen size.
        let radius = random() < 0.45 ? 0.9 + pow(random(), 1.4) * 2.3 : 2.2 + pow(random(), 1.8) * 8.2
        return radius * (0.85 + intensity * 0.30)
    }

    func update(deltaTime: Float, size: SIMD2<Float>, weather: Weather, intensity: Float, wind: Float, gentle: Bool) {
        guard size.x > 0, size.y > 0 else { return }
        if !initialized || self.size != size || self.weather != weather {
            reset(size: size, weather: weather, intensity: intensity)
        }
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        if weather == .rain && intensity != lastIntensity {
            // Add water over several seconds, preserving every existing bead and
            // its motion. Turning rain down reduces arrivals; wet glass dries slowly.
            pendingImpacts = max(0, pendingImpacts + rainPopulation(intensity) - rainPopulation(lastIntensity))
            lastIntensity = intensity
        }
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
        untilShower -= dt
        if untilShower <= 0 {
            showerTarget = 0.18 + random() * 0.82
            untilShower = 6 + random() * 17
        }
        shower += (showerTarget - shower) * min(1, dt * 0.22)
        let extraRate = pendingImpacts / 4
        pendingImpacts = max(0, pendingImpacts - extraRate * dt)
        untilImpact -= dt
        while untilImpact <= 0 {
            let rate = (weather == .rain ? (1.4 + intensity * 6) * (0.35 + shower) : 0.7 + intensity * 2.0) * area + extraRate
            untilImpact += max(0.003, -log(max(0.001, random())) / rate)
            let radius = weather == .rain ? beadRadius(intensity) : 3.0 + random() * 4.0
            addImpact(at: SIMD2(random() * size.x, random() * (size.y + 40) - 20), radius: radius)
        }
        for i in trails.indices { trails[i].age += dt }
        trails.removeAll { $0.age > 16.0 }
        for i in drops.indices {
            drops[i].age += dt
            if drops[i].snow { continue }
            let threshold = 9.4 + drops[i].seed * 2.6
            // Contact-angle hysteresis pins small beads for minutes. Coalescence can
            // release a heavy bead; the wet path then needs less force to keep moving.
            let moving = drops[i].velocity > 0.3
            let release = threshold * (moving ? 0.73 : 1)
            if drops[i].radius > release && drops[i].age > 0.6 {
                let friction = 0.65 + 0.35 * sin(drops[i].position.y * 0.019 + drops[i].seed * 91)
                let target = min(24, (drops[i].radius - release + 0.6) * 3.2) * friction
                drops[i].velocity += (target - drops[i].velocity) * min(1, dt * 0.7)
                let distance = drops[i].velocity * dt
                drops[i].position.y += distance
                drops[i].position.x += distance * (sin(drops[i].position.y * 0.043 + drops[i].seed * 31) * 0.12 + wind * 0.025)
                let offset = drops[i].position - drops[i].anchor
                if offset.x * offset.x + offset.y * offset.y > 9 {
                    trails.append(GlassTrail(start: drops[i].anchor, end: drops[i].position,
                                             width: max(0.6, drops[i].radius * 0.15), seed: drops[i].seed))
                    drops[i].anchor = drops[i].position
                }
            }
        }
        untilMerge -= dt
        if weather == .rain && untilMerge <= 0 {
            coalesce()
            untilMerge += 1 / 30
        }
        drops.removeAll { $0.position.y > size.y + 35 || $0.age > $0.life }
        if trails.count > Self.maxTrails { trails.removeFirst(trails.count - Self.maxTrails) }
    }

    private func coalesce() {
        // Spatial bins keep the large, mostly still bead field inexpensive. A drop
        // travels less than one point between collision passes, even at maximum speed.
        var cells: [SIMD2<Int32>: [Int]] = [:]
        for i in drops.indices {
            let cell = SIMD2<Int32>(Int32(floor(drops[i].position.x / 44)), Int32(floor(drops[i].position.y / 44)))
            var consumed = false
            for dy: Int32 in -1...1 {
                for dx: Int32 in -1...1 {
                    for j in cells[cell &+ SIMD2(dx, dy)] ?? [] where !consumed {
                        let delta = drops[i].position - drops[j].position
                        let reach = (drops[i].radius + drops[j].radius) * 0.86
                        guard delta.x * delta.x + delta.y * delta.y < reach * reach else { continue }
                        let a = pow(drops[j].radius, 3), b = pow(drops[i].radius, 3)
                        drops[j].position = (drops[j].position * a + drops[i].position * b) / (a + b)
                        drops[j].velocity = (drops[j].velocity * a + drops[i].velocity * b) / (a + b)
                        drops[j].radius = min(22, pow(a + b, 1 / Float(3)))
                        drops[j].life = max(drops[j].life, drops[i].life)
                        drops[j].anchor = drops[j].position
                        drops[i].radius = 0
                        consumed = true; merges += 1
                    }
                }
            }
            if !consumed { cells[cell, default: []].append(i) }
        }
        drops.removeAll { $0.radius == 0 }
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
                                      age: trail.age, seed: trail.seed, kind: 1, opacity: pow(max(0, 1 - trail.age / 16), 1.6)))
        }
        for drop in drops {
            let fade = min(1, max(0, (drop.life - drop.age) / (drop.snow ? 3 : 18)))
            let arrival = min(1, drop.age / (drop.snow ? 0.28 : 0.7))
            let stretch = min(0.32, drop.velocity / 65)
            let radius = drop.radius * (0.7 + 0.3 * arrival) * sqrt(fade)
            let extent = SIMD2(radius * (0.95 + drop.seed * 0.07), radius * (1 + stretch))
            result.append(GlassSprite(center: drop.position, extent: extent, axis: SIMD2(0, 1),
                                      age: drop.age, seed: drop.seed, kind: drop.snow ? 3 : 0, opacity: fade * arrival))
        }
        return result
    }
}
