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
        precondition(heavy.position.y > 220 && heavy.position.y < 440 && !runner.trails.isEmpty, "Heavy beads must glide slowly and leave a trail")

        let sixty = GlassSimulation(seed: 42), thirty = GlassSimulation(seed: 42)
        for _ in 0..<600 { step(sixty, 1 / 60) }
        for _ in 0..<300 { step(thirty, 1 / 30) }
        precondition(sixty.drops.count == thirty.drops.count && sixty.impacts == thirty.impacts)
        for (a, b) in zip(sixty.drops, thirty.drops) {
            precondition(abs(a.position.y - b.position.y) < 0.01 && abs(a.radius - b.radius) < 0.001)
        }
        precondition(sixty.impacts > 10 && sixty.impacts < 100 && sixty.merges > 0)
        precondition(sixty.drops.filter { $0.velocity < 0.1 }.count > sixty.drops.count * 9 / 10, "At least 90% of the glass beads should remain pinned")
        precondition(sixty.drops.allSatisfy { $0.velocity <= 24 }, "Runoff must never become a fast sheet of streaks")
        let another = GlassSimulation(seed: 17)
        for _ in 0..<600 { step(another, 1 / 60) }
        precondition(sixty.drops.first?.position != another.drops.first?.position, "Sessions must not replay the same glass pattern")
        let before = sixty.elapsed
        step(sixty, .nan); step(sixty, -2)
        precondition(sixty.elapsed == before)
        step(sixty, 300)
        precondition(sixty.elapsed - before < 0.101, "Suspended frames must not cause a catch-up burst")
        for _ in 0..<1200 { step(sixty, 1 / 60, intensity: 1) }
        precondition(sixty.drops.count <= GlassSimulation.maxDrops && sixty.trails.count <= GlassSimulation.maxTrails)
        precondition(sixty.drops.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.radius.isFinite })
        step(sixty, 1 / 60, weather: .snow)
        precondition(sixty.drops.allSatisfy(\.snow) && sixty.trails.isEmpty, "Weather changes must clear old rain trails")
        step(sixty, 1 / 60, weather: .mist)
        precondition(sixty.drops.isEmpty && sixty.sprites.isEmpty)
        precondition(MemoryLayout<GlassSprite>.stride == 48)
        print("Passed: droplet mass conservation, gravity/runoff, trails, irregular impacts, 30/60 fps equivalence, bounded state, pause recovery and weather changes.")
    }
}
