import Foundation

@main struct SnowTests {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/snow-1.3.1.json"))
        let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let frames = fixture["frames"] as! [[String: Any]]
        let simulation = GlassSimulation(seed: 741)
        for i in 1...1080 {
            simulation.update(deltaTime: 1 / 60, size: SIMD2(1440, 900), weather: .snow, intensity: 0.65, wind: 0.25, gentle: false)
            guard let expected = frames.first(where: { $0["frame"] as? Int == i }) else { continue }
            let drops = expected["drops"] as! [[Double]]
            precondition(simulation.drops.count == expected["count"] as! Int && simulation.impacts == expected["impacts"] as! Int)
            for (actual, values) in zip(simulation.drops, drops) {
                let fields = [actual.position.x, actual.position.y, actual.radius, actual.age, actual.life, actual.seed]
                for (value, reference) in zip(fields, values) {
                    precondition(abs(Double(value) - reference) < 0.0001, "Snow changed from the accepted 1.3.1 behavior")
                }
            }
            precondition(simulation.approaches.isEmpty && simulation.splashes.isEmpty && simulation.frameContacts.isEmpty)
        }
        print("Passed: snowfall surface behavior matches the accepted 1.3.1 fixture at 4, 8 and 18 seconds; no rain contacts leak into snow.")
    }
}
