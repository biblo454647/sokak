import Foundation

@main struct WiperTests {
    static let size = SIMD2<Float>(1440, 900)
    static func step(_ surface: GlassSimulation, dt: Float = 1 / 60, rain: Bool = false) {
        surface.update(deltaTime: dt, size: size, weather: .rain, intensity: 0.65, wind: 0.25, gentle: false, precipitating: rain)
    }
    static func grid(seed: UInt64 = 61) -> GlassSimulation {
        let s = GlassSimulation(seed: seed)
        s.reset(size: size, weather: .rain, intensity: 0, populate: false)
        for y in stride(from: 30, through: 870, by: 40) {
            for x in stride(from: 20, through: 1420, by: 40) { s.addImpact(at: SIMD2(Float(x), Float(y)), radius: 3) }
        }
        for _ in 0..<60 { step(s) }
        return s
    }
    static func main() {
        let pinned = GlassSimulation(seed: 7)
        pinned.reset(size: size, weather: .rain, intensity: 0, populate: false)
        pinned.addImpact(at: SIMD2(450, 220), radius: 3)
        for _ in 0..<10800 { step(pinned) }
        precondition(pinned.drops.count == 1 && pinned.drops[0].position == SIMD2(450, 220))
        precondition(pinned.drops[0].radius == 3 && pinned.sprites[0].opacity == 1, "Pinned rain must not fade on an expiry timer")

        let cap = GlassSimulation(seed: 23)
        cap.reset(size: size, weather: .rain, intensity: 0, populate: false)
        for i in 0..<GlassSimulation.maxDrops { cap.addImpact(at: SIMD2(Float(i % 60) * 24, Float(i / 60) * 30), radius: 2) }
        let beforeCap = cap.waterVolume
        cap.addImpact(at: SIMD2(602, 452), radius: 5)
        precondition(cap.drops.count == GlassSimulation.maxDrops && abs(cap.waterVolume - beforeCap - 125) < 0.1,
                     "A full particle pool must absorb incoming water without deleting a bead")

        let big = GlassSimulation(seed: 17)
        big.reset(size: size, weather: .rain, intensity: 0, populate: false)
        big.addImpact(at: SIMD2(420, 400), radius: 22); big.addImpact(at: SIMD2(421, 400), radius: 22)
        step(big)
        precondition(big.drops.count == 1 && big.drops[0].radius > 22 && abs(big.waterVolume - 21296) < 0.1,
                     "Coalescence must conserve volume above the old radius cap")

        let s = grid(), initialCount = s.drops.count, initialVolume = s.waterVolume
        precondition(s.wipe() && !s.wipe(), "Repeated triggers must not restart an active sweep")
        for _ in 0..<24 { step(s) }
        precondition(s.drops.count > initialCount / 3 && s.drops.count < initialCount, "Clearing must follow the moving blade, not erase the whole glass")
        precondition(s.wiper.carried.reduce(0,+) > 0 && s.sprites.contains { $0.kind == 5 }, "Removed beads must collect visibly along the rubber edge")
        let retainedRight = s.drops.filter { $0.position.x > 1100 }.count
        precondition(retainedRight > 100, "Water ahead of the blade must remain")
        for _ in 0..<126 { step(s) }
        precondition(!s.wiper.active && s.sprites.allSatisfy { $0.kind < 5 })
        precondition(s.drops.count < initialCount / 30, "The swept screen should be clear after one out-and-back cycle")
        precondition(abs(s.waterVolume + s.wiper.removedVolume + s.wiper.carried.reduce(0,+) - initialVolume) < 2,
                     "Swept water must be accounted for at the boundary")

        let thirty = grid(), sixty = grid()
        thirty.wipe(); sixty.wipe()
        for _ in 0..<72 { step(thirty, dt: 1 / 30) }
        for _ in 0..<144 { step(sixty) }
        precondition(thirty.drops.count == sixty.drops.count && abs(thirty.wiper.removedVolume - sixty.wiper.removedVolume) < 0.1)
        precondition(thirty.wipe(), "A completed sweep can be triggered again")
        let rain = grid()
        rain.wipe()
        var contacts = 0
        for _ in 0..<300 { step(rain, rain: true); contacts += rain.frameContacts.count }
        precondition(contacts > 60 && !rain.drops.isEmpty, "Rain must continue during and after a wipe")
        rain.update(deltaTime: 1 / 60, size: size, weather: .snow, intensity: 0.65, wind: 0.25, gentle: false)
        precondition(!rain.wipe() && !rain.wiper.active && rain.sprites.allSatisfy { $0.kind < 5 }, "Wipers must never leak into snow")
        print("Passed: persistent pinned water, bounded-pool volume, uncapped coalescence, progressive blade clearing, carried water, boundary discharge, 30/60 fps consistency, repeated triggers and uninterrupted rain.")
    }
}
