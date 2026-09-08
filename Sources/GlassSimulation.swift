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

struct RainApproach {
    var target: SIMD2<Float>
    var radius: Float
    var seed: Float
    var drift: SIMD2<Float>
    var age: Float = 0
    var duration: Float
}

struct RainSplash {
    var center: SIMD2<Float>
    var radius: Float
    var seed: Float
    var age: Float = 0
}

struct RainContact {
    var position: SIMD2<Float>
    var radius: Float
    var seed: Float
    var pan: Float
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
    static let maxApproaches = 160
    static let maxSplashes = 180
    private(set) var drops: [GlassDrop] = []
    private(set) var trails: [GlassTrail] = []
    private(set) var approaches: [RainApproach] = []
    private(set) var splashes: [RainSplash] = []
    private(set) var frameContacts: [RainContact] = []
    private(set) var elapsed: Float = 0
    private(set) var impacts = 0
    private(set) var merges = 0
    private(set) var wiper = WiperMotion()
    private(set) var drainedVolume: Float = 0
    var waterVolume: Float { drops.filter { !$0.snow }.reduce(0) { $0 + pow($1.radius, 3) } }
    private var state: UInt64
    private var size = SIMD2<Float>(1440, 900)
    private var weather: Weather = .rain
    private var remainder: Float = 0
    private var untilImpact: Float = 0
    private var untilMerge: Float = 0
    private var shower: Float = 0.6
    private var showerTarget: Float = 0.6
    private var untilShower: Float = 0
    private var rainHazard: Float = 0.8
    private var initialized = false

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { state = seed }

    private func random() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float((state >> 40) & 0xffffff) / Float(0x1000000)
    }

    func reset(size: SIMD2<Float>, weather: Weather, intensity: Float, populate: Bool = true) {
        self.size = size; self.weather = weather
        drops.removeAll(keepingCapacity: true); trails.removeAll(keepingCapacity: true)
        approaches.removeAll(keepingCapacity: true); splashes.removeAll(keepingCapacity: true)
        frameContacts.removeAll(keepingCapacity: true)
        elapsed = 0; remainder = 0; untilImpact = 0.8; untilMerge = 0; impacts = 0; merges = 0
        shower = 0.6; showerTarget = 0.6; untilShower = 3
        rainHazard = 0.8
        wiper.reset(); drainedVolume = 0
        initialized = true
        guard populate, weather != .mist else { return }
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        // The roof is already lightly wet. Intensity changes incoming frequency,
        // never the geometry or size of an individual drop.
        let count = min(Self.maxDrops, Int((weather == .rain ? 240 : 8 + intensity * 12) * area))
        for _ in 0..<count {
            let p = SIMD2(random() * size.x, random() * size.y)
            addImpact(at: p, radius: weather == .rain ? beadRadius() : 2.5 + random() * 3.5)
            drops[drops.count - 1].age = weather == .rain ? 2 + random() * 25 : 1 + random() * 4
        }
        impacts = 0
    }

    func addImpact(at position: SIMD2<Float>, radius: Float, recordImpact: Bool = true) {
        let r = min(22, max(0.55, radius))
        // Keep the accepted rain's random sequence; only rain's lifetime changes.
        let longevity = random(), seed = random()
        if drops.count >= Self.maxDrops {
            guard weather == .rain, let nearest = drops.indices.min(by: {
                let a = drops[$0].position - position, b = drops[$1].position - position
                return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y
            }) else { return }
            // Dense wet glass absorbs new water locally instead of deleting an old
            // bead or dropping incoming volume when the bounded particle pool fills.
            drops[nearest].radius = pow(pow(drops[nearest].radius, 3) + pow(r, 3), 1 / Float(3))
            if recordImpact { impacts += 1 }
            return
        }
        drops.append(GlassDrop(position: position, radius: r,
                               life: weather == .snow ? 7 + longevity * 12 : .infinity,
                               seed: seed, anchor: position, snow: weather == .snow))
        if recordImpact { impacts += 1 }
    }

    @discardableResult func wipe() -> Bool {
        guard initialized, weather == .rain else { return false }
        return wiper.start()
    }
    func cancelWipe() { wiper.reset() }

    private func beadRadius() -> Float {
        random() < 0.5 ? 0.8 + pow(random(), 1.4) * 2.5 : 2 + pow(random(), 1.8) * 6.5
    }

    func launchDrop(at position: SIMD2<Float>, radius: Float, duration: Float = 0.3, wind: Float = 0) {
        guard approaches.count < Self.maxApproaches else { return }
        approaches.append(RainApproach(target: position, radius: min(9, max(1, radius)), seed: random(),
                                      drift: SIMD2(wind * (5 + random() * 12), (random() - 0.5) * 8),
                                      duration: max(0.12, duration)))
    }

    private func land(_ drop: RainApproach) {
        // One contact drives both the visible lamella and its optional sound.
        let fragments = drop.radius > 4.1 && drop.seed > 0.25 ? 3 + Int(random() * 3) : 0
        let volumeShare: Float = fragments > 0 ? 0.05 : 0
        addImpact(at: drop.target, radius: drop.radius * pow(1 - volumeShare, 1 / Float(3)))
        for i in 0..<fragments {
            let angle = (Float(i) + random() * 0.6) / Float(fragments) * 2 * .pi + drop.seed * 7
            let distance = drop.radius * (1.5 + random() * 1.4)
            addImpact(at: drop.target + SIMD2(cos(angle), sin(angle)) * distance,
                      radius: drop.radius * pow(volumeShare / Float(fragments), 1 / Float(3)), recordImpact: false)
        }
        splashes.append(RainSplash(center: drop.target, radius: drop.radius, seed: drop.seed))
        frameContacts.append(RainContact(position: drop.target, radius: drop.radius, seed: drop.seed,
                                        pan: min(0.85, max(-0.85, (drop.target.x / size.x * 2 - 1) * 0.85))))
    }

    static func contactSpread(age: Float) -> Float {
        // Brief inertial spread, then damped recoil into the deposited water.
        age < 0.055 ? 0.5 + 1.7 * sin(max(0, age) / 0.055 * .pi * 0.5) : 1 + 1.2 * exp(-(age - 0.055) * 14)
    }

    func update(deltaTime: Float, size: SIMD2<Float>, weather: Weather, intensity: Float, wind: Float, gentle: Bool, precipitating: Bool = true) {
        frameContacts.removeAll(keepingCapacity: true)
        guard size.x > 0, size.y > 0 else { return }
        if !initialized || self.size != size || self.weather != weather {
            reset(size: size, weather: weather, intensity: intensity)
        }
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        // A delayed frame never becomes an explosive catch-up after sleep or a resize.
        remainder += min(deltaTime, 0.1)
        let step: Float = 1 / 120
        while remainder + 0.000001 >= step {
            tick(step * (gentle ? 0.55 : 1), intensity: intensity, wind: wind, precipitating: precipitating)
            advanceWiper(step)
            remainder = max(0, remainder - step)
        }
    }

    private func tick(_ dt: Float, intensity: Float, wind: Float, precipitating: Bool) {
        elapsed += dt
        guard weather != .mist else { return }
        let area = min(2.4, max(0.35, size.x * size.y / 1_296_000))
        untilShower -= dt
        if untilShower <= 0 {
            showerTarget = 0.18 + random() * 0.82
            untilShower = 6 + random() * 17
        }
        shower += (showerTarget - shower) * min(1, dt * 0.22)
        if weather == .rain {
            for i in splashes.indices { splashes[i].age += dt }
            splashes.removeAll { $0.age > 0.5 }
            for i in approaches.indices { approaches[i].age += dt }
            let landed = approaches.filter { $0.age >= $0.duration }
            approaches.removeAll { $0.age >= $0.duration }
            for drop in landed { land(drop) }
            // Integrate a Poisson hazard, so live frequency changes apply immediately.
            let rate = (2.5 + 42 * pow(intensity, 1.35)) * (0.75 + shower * 0.5) * area
            if precipitating { rainHazard -= dt * rate }
            while rainHazard <= 0 {
                rainHazard += max(0.01, -log(max(0.001, random())))
                let point = SIMD2(random() * size.x, random() * size.y)
                let radius = 2.3 + pow(random(), 1.6) * 5.6
                launchDrop(at: point, radius: radius, duration: 0.18 + random() * 0.19, wind: wind)
            }
            if splashes.count > Self.maxSplashes { splashes.removeFirst(splashes.count - Self.maxSplashes) }
        } else {
            // Keep the existing snowfall simulation and its random sequence intact.
            untilImpact -= dt
            while untilImpact <= 0 {
                let rate = (0.7 + intensity * 2.0) * area
                untilImpact += max(0.003, -log(max(0.001, random())) / rate)
                let radius = 3.0 + random() * 4.0
                addImpact(at: SIMD2(random() * size.x, random() * (size.y + 40) - 20), radius: radius)
            }
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
                // A shallow roof pitch lets heavy water creep; it does not stream
                // vertically across the viewer's field like a wall-mounted window.
                let excess = max(0, drops[i].radius - 18)
                let speedLimit = min(26, 2.8 + pow(excess, 1.3) * 0.45)
                let target = min(speedLimit, (drops[i].radius - release + 0.6) * (0.45 + excess * 0.07)) * friction
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
        for drop in drops where !drop.snow && drop.position.y > size.y + drop.radius + 2 {
            drainedVolume += pow(drop.radius, 3)
        }
        drops.removeAll { $0.snow ? ($0.position.y > size.y + 35 || $0.age > $0.life) : $0.position.y > size.y + $0.radius + 2 }
        if trails.count > Self.maxTrails { trails.removeFirst(trails.count - Self.maxTrails) }
    }

    private func advanceWiper(_ dt: Float) {
        guard weather == .rain, wiper.active else { return }
        let previous = wiper.pose(size: size)
        wiper.advance(dt)
        let current = wiper.pose(size: size)
        drops.removeAll { drop in
            guard current.crosses(drop.position, radius: drop.radius, from: previous) else { return false }
            wiper.collect(position: drop.position, volume: pow(drop.radius, 3), pose: current)
            return true
        }
        splashes.removeAll { current.crosses($0.center, radius: $0.radius, from: previous) }
        trails.removeAll {
            current.crosses($0.start, radius: $0.width, from: previous) || current.crosses($0.end, radius: $0.width, from: previous)
                || current.crosses(($0.start + $0.end) * 0.5, radius: $0.width, from: previous)
        }
        wiper.drainIfParked()
    }

    private func coalesce() {
        // Spatial bins keep the large, mostly still bead field inexpensive. A drop
        // travels less than one point between collision passes, even at maximum speed.
        var cells: [SIMD2<Int32>: [Int]] = [:]
        let cellWidth = max(44, (drops.map(\.radius).max() ?? 22) * 1.73)
        for i in drops.indices {
            let cell = SIMD2<Int32>(Int32(floor(drops[i].position.x / cellWidth)), Int32(floor(drops[i].position.y / cellWidth)))
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
                        drops[j].radius = pow(a + b, 1 / Float(3))
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
        result.reserveCapacity(trails.count + drops.count + approaches.count + splashes.count)
        for drop in approaches {
            let phase = min(1, drop.age / drop.duration)
            let near = phase * phase
            let vanishingPoint = size * SIMD2(0.52, 0.43)
            let center = drop.target - (drop.target - vanishingPoint) * (0.055 * (1 - near)) - drop.drift * (1 - near)
            let radius = drop.radius * (0.32 + 0.53 * near)
            result.append(GlassSprite(center: center, extent: SIMD2(radius, radius * (0.94 + drop.seed * 0.12)),
                                      axis: SIMD2(0, 1), age: phase, seed: drop.seed, kind: 4,
                                      opacity: min(1, phase / 0.22) * (0.16 + 0.60 * near)))
        }
        for trail in trails {
            let d = trail.end - trail.start
            let length = sqrt(d.x * d.x + d.y * d.y)
            guard length > 0.01 else { continue }
            result.append(GlassSprite(center: (trail.start + trail.end) * 0.5,
                                      extent: SIMD2(trail.width, length * 0.5 + trail.width), axis: d / length,
                                      age: trail.age, seed: trail.seed, kind: 1, opacity: pow(max(0, 1 - trail.age / 16), 1.6)))
        }
        for drop in drops {
            let fade: Float = drop.snow ? min(1, max(0, (drop.life - drop.age) / 3)) : 1
            let arrival = drop.snow ? min(1, drop.age / 0.28) : min(1, max(0, (drop.age - 0.06) / 0.24))
            let stretch = min(0.32, drop.velocity / 65)
            let radius = drop.radius * (0.7 + 0.3 * arrival) * sqrt(fade)
            let extent = SIMD2(radius * (0.95 + drop.seed * 0.07), radius * (1 + stretch))
            result.append(GlassSprite(center: drop.position, extent: extent, axis: SIMD2(0, 1),
                                      age: drop.age, seed: drop.seed, kind: drop.snow ? 3 : 0, opacity: fade * arrival))
        }
        for splash in splashes {
            let radius = splash.radius * Self.contactSpread(age: splash.age)
            result.append(GlassSprite(center: splash.center, extent: SIMD2(radius, radius * (0.9 + splash.seed * 0.16)),
                                      axis: SIMD2(0, 1), age: splash.age, seed: splash.seed, kind: 2, opacity: 1))
        }
        result += wiper.sprites(size: size)
        return result
    }
}
