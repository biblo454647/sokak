import Foundation

enum Weather: String, Codable, CaseIterable, Identifiable {
    case rain, snow, mist
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { switch self { case .rain: return "cloud.rain"; case .snow: return "snowflake"; case .mist: return "cloud.fog" } }
    var index: Float { switch self { case .rain: return 0; case .snow: return 1; case .mist: return 2 } }
    var soundDescription: String { switch self { case .rain: return "Soft rain & scattered droplets"; case .snow: return "Hushed winter wind"; case .mist: return "A slow, low breeze" } }
}

enum Backdrop: String, Codable { case desktop, istanbul }

struct Preferences: Codable, Equatable {
    var weather: Weather = .rain
    var backdrop: Backdrop = .desktop
    var intensity: Double = 0.48
    var wind: Double = 0.25
    var volume: Double = 0.35
    var sound: Bool = true
    var economical: Bool = false
    var matchSeason: Bool = true
    var dimming: Double = 0.12
    var timerMinutes: Int = 0
    var display: String = "current"
    var sceneID: String = "balat"

    mutating func sanitize() {
        intensity = Self.unit(intensity, fallback: 0.48)
        wind = Self.unit(wind, fallback: 0.25)
        volume = Self.unit(volume, fallback: 0.35)
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
    var resolution: String { "\(width) × \(height)" }

    static func matching(_ weather: Weather, current: StreetScene?, scenes: [StreetScene]) -> String? {
        let winter = weather == .snow
        if let current, current.winter == winter { return current.id }
        let preferred = winter ? "bagcilar-evening" : "balat"
        return scenes.first { $0.id == preferred && $0.winter == winter }?.id
            ?? scenes.first { $0.winter == winter }?.id
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
