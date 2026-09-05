import Foundation

@main struct CoreTests {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = SessionClock()
        clock.start(minutes: 15, now: start)
        precondition(!clock.expired(at: start.addingTimeInterval(899)))
        precondition(clock.expired(at: start.addingTimeInterval(900)))
        precondition(clock.remaining(at: start.addingTimeInterval(899.2)) == 1)
        precondition(clock.remaining(at: start.addingTimeInterval(5000)) == 0)
        clock.stop()
        precondition(!clock.expired(at: .distantFuture) && clock.remaining(at: start) == nil)
        clock.start(minutes: 0, now: start)
        precondition(!clock.expired(at: .distantFuture))

        var preferences = Preferences()
        preferences.volume = .infinity; preferences.intensity = -20; preferences.wind = 50
        preferences.timerMinutes = -50; preferences.display = "unplugged-invalid"
        preferences.sanitize()
        precondition(preferences.volume == 0.35 && preferences.intensity == 0 && preferences.wind == 1)
        precondition(preferences.timerMinutes == 0 && preferences.display == "current")
        precondition(Preferences.decode(Data("corrupt".utf8)) == Preferences())
        preferences.volume = 0.7; preferences.weather = .snow
        let encoded = try JSONEncoder().encode(preferences)
        precondition(Preferences.decode(encoded) == preferences)

        let data = try Data(contentsOf: URL(fileURLWithPath: "Resources/scenes.json"))
        let scenes = try JSONDecoder().decode([StreetScene].self, from: data)
        let summer = scenes.first { !$0.winter }!
        let winter = scenes.first { $0.winter }!
        let selected = StreetScene.matching(.snow, current: summer, scenes: scenes)
        precondition(scenes.first { $0.id == selected }!.winter)
        precondition(StreetScene.matching(.rain, current: summer, scenes: scenes) == summer.id)
        precondition(StreetScene.matching(.snow, current: winter, scenes: scenes) == winter.id)
        precondition(StreetScene.matching(.snow, current: summer, scenes: [summer]) == summer.id)
        precondition(StreetScene.matching(.rain, current: nil, scenes: []) == nil)
        precondition(Set(scenes.map(\.id)).count == scenes.count)
        print("Passed: timer boundaries, safe settings recovery, persistence, winter matching, empty catalogs, unique scene IDs.")
    }
}
