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
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "windowGlass")
        legacy.removeValue(forKey: "glassFocus")
        let migrated = Preferences.decode(try JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated == preferences && migrated.windowGlass)
        preferences.windowGlass = false
        let glassDisabled = try JSONEncoder().encode(preferences)
        precondition(!Preferences.decode(glassDisabled).windowGlass)
        var oldSettings = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        oldSettings.removeValue(forKey: "wiperShortcut")
        let upgraded = Preferences.decode(try JSONSerialization.data(withJSONObject: oldSettings))
        precondition(upgraded.wiperShortcut == .wiperDefault && upgraded.volume == 0.7 && upgraded.weather == .snow)
        var custom = upgraded
        custom.wiperShortcut = KeyShortcut(keyCode: 40, modifiers: KeyShortcut.control | KeyShortcut.option, keyLabel: "K")
        let customData = try JSONEncoder().encode(custom)
        precondition(Preferences.decode(customData) == custom)
        custom.wiperShortcut.modifiers = 0; custom.sanitize()
        precondition(custom.wiperShortcut == .wiperDefault)
        oldSettings["wiperShortcut"] = ["bad": "data"]
        let malformedShortcut = try JSONSerialization.data(withJSONObject: oldSettings)
        precondition(Preferences.decode(malformedShortcut) == upgraded)
        precondition(KeyShortcut(keyCode: 1, modifiers: KeyShortcut.wiperDefault.modifiers, keyLabel: "S").isSokakReserved)

        let data = try Data(contentsOf: URL(fileURLWithPath: "Resources/scenes.json"))
        let scenes = try JSONDecoder().decode([StreetScene].self, from: data)
        // A retired sunny scene still represents preferences from older releases.
        let summer = StreetScene(id: "balat", title: "Legacy sunny scene", subtitle: "", winter: false,
                                 filename: "retired.jpg", width: 3000, height: 2000, author: "Fixture",
                                 license: "CC0", licenseURL: "", sourceURL: "", conditions: [])
        let winter = scenes.first { $0.winter }!
        let selected = StreetScene.matching(.snow, current: summer, scenes: scenes)
        precondition(scenes.first { $0.id == selected }!.winter)
        let rainy = StreetScene.matching(.rain, current: summer, scenes: scenes)
        precondition(rainy == "galata-rain", "Old sunny preferences must migrate to a rain-appropriate photograph")
        precondition(scenes.first { $0.id == rainy }!.suits(.rain))
        precondition(!summer.suits(.rain))
        let ayasofya = scenes.first { $0.id == "ayasofya-rain" }!
        precondition(StreetScene.matching(.rain, current: ayasofya, scenes: scenes) == ayasofya.id)
        precondition(StreetScene.matching(.mist, current: summer, scenes: scenes) == "bosphorus-clouds")
        precondition(StreetScene.matching(.snow, current: winter, scenes: scenes) == winter.id)
        precondition(StreetScene.matching(.snow, current: summer, scenes: [summer]) == summer.id)
        precondition(StreetScene.matching(.rain, current: nil, scenes: []) == nil)
        precondition(Set(scenes.map(\.id)).count == scenes.count)
        print("Passed: timer boundaries, safe settings recovery, persistence, winter matching, empty catalogs, unique scene IDs.")
    }
}
