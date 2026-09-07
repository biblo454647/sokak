import Foundation

@main struct GlassTests {
    static let size = SIMD2<Float>(1440, 900)
    static func step(_ glass: GlassSimulation, _ dt: Float, weather: Weather = .rain, intensity: Float = 0.65) {
        glass.update(deltaTime: dt, size: size, weather: weather, intensity: intensity, wind: 0.4, gentle: false)
    }
    static func main() {
        let merged = GlassSimulation(seed: 9)
        merged.reset(size: size, weather: .rain, intensity: 0, populate: false)
        merged.addImpact(at: SIMD2(400, 200), radius: 4)
        merged.addImpact(at: SIMD2(403, 200), radius: 5)
        step(merged, 1 / 120, intensity: 0)
        precondition(merged.drops.count == 1 && merged.merges == 1)
        precondition(abs(pow(merged.drops[0].radius, 3) - 189) < 0.01, "Merging must conserve water volume")
        for _ in 0..<120 { step(merged, 1 / 60, intensity: 0) }
        precondition(abs(merged.drops[0].position.y - 200) < 0.1, "Small merged beads should stay pinned to the glass")
        let runner = GlassSimulation(seed: 7)
        runner.reset(size: size, weather: .rain, intensity: 0, populate: false)
        runner.addImpact(at: SIMD2(400, 200), radius: 16)
        for _ in 0..<600 { step(runner, 1 / 60, intensity: 0) }
        let heavy = runner.drops.first { $0.radius > 15 }!
        precondition(heavy.position.y > 202 && heavy.position.y < 228 && !runner.trails.isEmpty, "Water on the shallow roof must creep without streaming down the screen")

        let roof = GlassSimulation(seed: 19)
        roof.reset(size: size, weather: .rain, intensity: 0, populate: false)
        roof.launchDrop(at: SIMD2(1000, 330), radius: 6, duration: 0.3)
        let start = roof.sprites.first!
        var contacts: [RainContact] = []
        for _ in 0..<15 { step(roof, 1 / 60, intensity: 0); contacts += roof.frameContacts }
        let near = roof.sprites.first { $0.kind == 4 && $0.seed == start.seed }!
        precondition(contacts.isEmpty && roof.drops.isEmpty, "Drops must approach the pane before making contact")
        precondition(near.extent.x > start.extent.x && abs(near.extent.x - near.extent.y) < 1,
                     "An approaching drop is round and grows in depth, never a vertical capsule")
        precondition(abs(near.center.y - start.center.y) < 40 && abs(near.center.x - start.center.x) < 40)
        for _ in 0..<9 { step(roof, 1 / 60, intensity: 0); contacts += roof.frameContacts }
        precondition(contacts.count == 1 && contacts[0].position == SIMD2(1000, 330), "One landing must emit one sound/contact event at its target")
        precondition(abs(roof.drops.reduce(0) { $0 + pow($1.radius, 3) } - 216) < 0.02,
                     "Spreading and satellite beads must conserve the incoming water")
        precondition(!roof.splashes.isEmpty && roof.splashes[0].center == SIMD2(1000, 330))

        let sixty = GlassSimulation(seed: 42), thirty = GlassSimulation(seed: 42)
        for _ in 0..<600 { step(sixty, 1 / 60) }
        for _ in 0..<300 { step(thirty, 1 / 30) }
        precondition(sixty.drops.count == thirty.drops.count && sixty.impacts == thirty.impacts)
        for (a, b) in zip(sixty.drops, thirty.drops) {
            precondition(abs(a.position.y - b.position.y) < 0.01 && abs(a.radius - b.radius) < 0.001)
        }
        precondition(sixty.impacts > 80 && sixty.impacts < 600 && sixty.merges > 0)
        precondition(sixty.drops.filter { $0.velocity < 0.1 }.count > sixty.drops.count * 9 / 10, "At least 90% of the glass beads should remain pinned")
        precondition(sixty.drops.allSatisfy { $0.velocity <= 2.8 }, "Roof water must never become a fast sheet of streaks")
        let another = GlassSimulation(seed: 17)
        for _ in 0..<600 { step(another, 1 / 60) }
        precondition(sixty.drops.first?.position != another.drops.first?.position, "Sessions must not replay the same glass pattern")
        let rising = GlassSimulation(seed: 71), light = GlassSimulation(seed: 71)
        for _ in 0..<120 { step(rising, 1 / 60, intensity: 0.1); step(light, 1 / 60, intensity: 0.1) }
        let originalCount = rising.drops.count, originalSeed = rising.drops[0].seed, originalElapsed = rising.elapsed
        step(rising, 1 / 60, intensity: 1)
        precondition(rising.drops.count < originalCount + 10 && rising.drops[0].seed == originalSeed && rising.elapsed > originalElapsed,
                     "Changing intensity must keep the live glass field instead of resetting it")
        for _ in 0..<600 { step(rising, 1 / 60, intensity: 1); step(light, 1 / 60, intensity: 0.1) }
        let visibleHeavy = rising.drops.filter { $0.radius > 3 }.count
        let visibleLight = light.drops.filter { $0.radius > 3 }.count
        precondition(rising.drops.count > light.drops.count * 2 && visibleHeavy > visibleLight * 2,
                     "Increasing intensity during playback must increase contacts and accumulated water")
        let wetCount = rising.drops.count
        step(rising, 1 / 60, intensity: 0.1)
        precondition(rising.drops.count > wetCount * 9 / 10, "Turning rain down must not abruptly erase wet glass")
        let lowShape = GlassSimulation(seed: 31), highShape = GlassSimulation(seed: 31)
        for surface in [lowShape, highShape] {
            surface.reset(size: size, weather: .rain, intensity: 0, populate: false)
            surface.launchDrop(at: SIMD2(1000, 300), radius: 6)
        }
        for _ in 0..<6 { step(lowShape, 1 / 60, intensity: 0.1); step(highShape, 1 / 60, intensity: 1) }
        let a = lowShape.sprites.first!, b = highShape.sprites.first!
        precondition(a.extent == b.extent && a.center == b.center, "Intensity must not thicken, stretch or accelerate an existing drop")
        var lowContacts: [RainContact] = [], highContacts: [RainContact] = []
        for _ in 0..<900 {
            step(lowShape, 1 / 60, intensity: 0.1); lowContacts += lowShape.frameContacts
            step(highShape, 1 / 60, intensity: 1); highContacts += highShape.frameContacts
        }
        let meanLow = lowContacts.reduce(0) { $0 + $1.radius } / Float(lowContacts.count)
        let meanHigh = highContacts.reduce(0) { $0 + $1.radius } / Float(highContacts.count)
        precondition(highContacts.count > lowContacts.count * 5 && abs(meanHigh / meanLow - 1) < 0.16,
                     "Heavy rain must increase contact frequency while keeping the same drop-size distribution")
        let before = sixty.elapsed
        step(sixty, .nan); step(sixty, -2)
        precondition(sixty.elapsed == before)
        step(sixty, 300)
        precondition(sixty.elapsed - before < 0.101, "Suspended frames must not cause a catch-up burst")
        for _ in 0..<1200 { step(sixty, 1 / 60, intensity: 1) }
        precondition(sixty.drops.count <= GlassSimulation.maxDrops && sixty.trails.count <= GlassSimulation.maxTrails)
        precondition(sixty.approaches.count <= GlassSimulation.maxApproaches && sixty.splashes.count <= GlassSimulation.maxSplashes)
        precondition(sixty.drops.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.radius.isFinite })
        step(sixty, 1 / 60, weather: .snow)
        precondition(sixty.drops.allSatisfy(\.snow) && sixty.trails.isEmpty && sixty.approaches.isEmpty && sixty.splashes.isEmpty && sixty.frameContacts.isEmpty,
                     "Weather changes must clear every rain effect and sound event")
        step(sixty, 1 / 60, weather: .mist)
        precondition(sixty.drops.isEmpty && sixty.sprites.isEmpty)
        precondition(MemoryLayout<GlassSprite>.stride == 48)
        print("Passed: roof approach/contact/recoil, water volume, contact events, intensity-independent drop geometry, live contact frequency, slow drainage, 30/60 fps equivalence, bounded state and weather changes.")
    }
}
