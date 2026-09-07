import Foundation

enum Weather: String, Codable, CaseIterable, Identifiable {
    case rain, snow, mist
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { switch self { case .rain: return "cloud.rain"; case .snow: return "snowflake"; case .mist: return "cloud.fog" } }
    var index: Float { switch self { case .rain: return 0; case .snow: return 1; case .mist: return 2 } }
    var soundDescription: String { switch self { case .rain: return "Rain outside & soft taps on glass"; case .snow: return "Hushed winter wind"; case .mist: return "A slow, low breeze" } }
}

enum Backdrop: String, Codable { case desktop, istanbul }
enum SceneFilter: String { case weather, winter, all }

struct Preferences: Codable, Equatable {
    var weather: Weather = .rain
    var backdrop: Backdrop = .desktop
    var intensity: Double = 0.48
    var wind: Double = 0.25
    var volume: Double = 0.35
    var sound: Bool = true
    var economical: Bool = false
    var matchSeason: Bool = true
    var windowGlass: Bool = true
    var glassFocus: Double = 0.65
    var dimming: Double = 0.12
    var timerMinutes: Int = 0
    var display: String = "current"
    var sceneID: String = "galata-rain"

    init() {}
    private enum CodingKeys: String, CodingKey {
        case weather, backdrop, intensity, wind, volume, sound, economical, matchSeason, windowGlass, glassFocus, dimming, timerMinutes, display, sceneID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weather = try c.decodeIfPresent(Weather.self, forKey: .weather) ?? .rain
        backdrop = try c.decodeIfPresent(Backdrop.self, forKey: .backdrop) ?? .desktop
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.48
        wind = try c.decodeIfPresent(Double.self, forKey: .wind) ?? 0.25
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.35
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        economical = try c.decodeIfPresent(Bool.self, forKey: .economical) ?? false
        matchSeason = try c.decodeIfPresent(Bool.self, forKey: .matchSeason) ?? true
        windowGlass = try c.decodeIfPresent(Bool.self, forKey: .windowGlass) ?? true
        glassFocus = try c.decodeIfPresent(Double.self, forKey: .glassFocus) ?? 0.65
        dimming = try c.decodeIfPresent(Double.self, forKey: .dimming) ?? 0.12
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes) ?? 0
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? "current"
        sceneID = try c.decodeIfPresent(String.self, forKey: .sceneID) ?? "galata-rain"
    }

    mutating func sanitize() {
        intensity = Self.unit(intensity, fallback: 0.48)
        wind = Self.unit(wind, fallback: 0.25)
        volume = Self.unit(volume, fallback: 0.35)
        glassFocus = Self.unit(glassFocus, fallback: 0.65)
        dimming = min(0.65, Self.unit(dimming, fallback: 0.12))
        if ![0, 15, 30, 60, 120].contains(timerMinutes) { timerMinutes = 0 }
        if display != "current" && display != "all" && UInt32(display) == nil { display = "current" }
    }

    static func unit(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }

    static func decode(_ data: Data?) -> Preferences {
        var value = data.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        value.sanitize()
        return value
    }
}

struct StreetScene: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let winter: Bool
    let filename: String
    let width: Int
    let height: Int
    let author: String
    let license: String
    let licenseURL: String
    let sourceURL: String
    var isPersonal: Bool? = nil
    var conditions: [Weather]? = nil
    var resolution: String { "\(width) × \(height)" }

    func suits(_ weather: Weather) -> Bool {
        // Imported photos retain the owner's choice, including legacy imports.
        if isPersonal == true { return winter == (weather == .snow) }
        return conditions?.contains(weather) ?? (winter && weather == .snow)
    }

    static func matching(_ weather: Weather, current: StreetScene?, scenes: [StreetScene]) -> String? {
        if let current, current.suits(weather) { return current.id }
        let preferred = weather == .snow ? "bagcilar-evening" : weather == .rain ? "galata-rain" : "bosphorus-clouds"
        return scenes.first { $0.id == preferred && $0.suits(weather) }?.id
            ?? scenes.first { $0.suits(weather) }?.id
            ?? current?.id
            ?? scenes.first?.id
    }
}

struct SessionClock {
    private(set) var deadline: Date?
    mutating func start(minutes: Int, now: Date = Date()) {
        deadline = minutes > 0 ? now.addingTimeInterval(Double(minutes) * 60) : nil
    }
    mutating func stop() { deadline = nil }
    func expired(at date: Date) -> Bool { deadline.map { date >= $0 } ?? false }
    func remaining(at date: Date) -> Int? { deadline.map { max(0, Int(ceil($0.timeIntervalSince(date)))) } }
}
