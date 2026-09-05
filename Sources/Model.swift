import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum Assets {
    static var root: URL { Bundle.main.resourceURL! }
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sokak", isDirectory: true)
    static var imports: URL { support.appendingPathComponent("Imports", isDirectory: true) }
    static func url(for scene: StreetScene) -> URL {
        // The catalog can only name a file, never navigate out of its resource directory.
        let filename = URL(fileURLWithPath: scene.filename).lastPathComponent
        return (scene.isPersonal == true ? imports : root.appendingPathComponent("Scenes")).appendingPathComponent(filename)
    }
    static func thumbnail(_ scene: StreetScene, maxSize: Int = 700) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url(for: scene) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

final class AppModel: ObservableObject {
    @Published var preferences: Preferences { didSet {
        var checked = preferences
        checked.sanitize()
        if checked != preferences { preferences = checked; return }
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences-v1") }
        if oldValue.timerMinutes != preferences.timerMinutes && running { clock.start(minutes: preferences.timerMinutes) }
        onChange?()
    } }
    @Published private(set) var running = false
    @Published private(set) var scenes: [StreetScene] = []
    @Published var error: String?
    @Published var remaining: Int?
    @Published var displays: [(id: String, name: String)] = []
    @Published var libraryVisible = false
    @Published var winterOnly = false
    var onChange: (() -> Void)?
    var onRunningChange: (() -> Void)?
    var closePopover: (() -> Void)?
    private var clock = SessionClock()
    private var timer: Timer?
    private let defaults: UserDefaults
    private var thumbnails: [String: NSImage] = [:]

    init(defaults: UserDefaults = .standard, includePersonalPhotos: Bool = true) {
        self.defaults = defaults
        preferences = Preferences.decode(defaults.data(forKey: "preferences-v1"))
        let catalog = Assets.root.appendingPathComponent("scenes.json")
        do { scenes = try JSONDecoder().decode([StreetScene].self, from: Data(contentsOf: catalog)) }
        catch { self.error = "The scene library could not be loaded. Please download Sokak again." }
        if includePersonalPhotos,
           let data = try? Data(contentsOf: Assets.imports.appendingPathComponent("catalog.json")),
           let personal = try? JSONDecoder().decode([StreetScene].self, from: data) {
            scenes += personal.filter { $0.isPersonal == true && FileManager.default.fileExists(atPath: Assets.url(for: $0).path) }
        }
        if !scenes.contains(where: { $0.id == preferences.sceneID }), let first = scenes.first { preferences.sceneID = first.id }
        refreshDisplays()
    }

    private func scheduleClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            if self.clock.expired(at: Date()) { self.stop() }
            self.remaining = self.clock.remaining(at: Date())
        }
    }

    var scene: StreetScene? { scenes.first { $0.id == preferences.sceneID } }
    func thumbnail(_ scene: StreetScene) -> NSImage? {
        if let value = thumbnails[scene.id] { return value }
        let value = Assets.thumbnail(scene)
        thumbnails[scene.id] = value
        return value
    }
    func refreshDisplays() {
        displays = NSScreen.screens.map { (id: Self.id(for: $0), name: $0.localizedName) }
    }
    static func id(for screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "current"
    }
    func chooseWeather(_ weather: Weather) {
        var next = preferences
        next.weather = weather
        if next.matchSeason, let id = StreetScene.matching(weather, current: scene, scenes: scenes) { next.sceneID = id }
        preferences = next
    }
    func toggle() { running ? stop() : start() }
    func start() {
        error = nil
        clock.start(minutes: preferences.timerMinutes)
        remaining = clock.remaining(at: Date())
        running = true
        scheduleClock()
        onRunningChange?()
    }
    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        clock.stop()
        remaining = nil
        onRunningChange?()
    }
    func select(_ scene: StreetScene) { preferences.sceneID = scene.id }

    func importPhoto() {
        closePopover?()
        let panel = NSOpenPanel()
        panel.title = "Add a street of your own"
        panel.prompt = "Add photo"
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let winter = NSButton(checkboxWithTitle: "This is a winter photograph", target: nil, action: nil)
        winter.state = preferences.weather == .snow ? .on : .off
        panel.accessoryView = winter
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 24000, height <= 24000 else {
                    throw NSError(domain: "Sokak", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a readable photograph up to 24,000 pixels on each side."])
                }
                try FileManager.default.createDirectory(at: Assets.imports, withIntermediateDirectories: true)
                let id = "personal-" + UUID().uuidString.lowercased()
                let filename = id + "." + url.pathExtension.lowercased()
                try FileManager.default.copyItem(at: url, to: Assets.imports.appendingPathComponent(filename))
                let scene = StreetScene(id: id, title: url.deletingPathExtension().lastPathComponent, subtitle: "Your photograph", winter: winter.state == .on, filename: filename, width: width, height: height, author: "Your library", license: "Personal photo", licenseURL: "", sourceURL: "", isPersonal: true)
                let personal = self.scenes.filter { $0.isPersonal == true } + [scene]
                try JSONEncoder().encode(personal).write(to: Assets.imports.appendingPathComponent("catalog.json"), options: .atomic)
                self.scenes.append(scene)
                self.preferences.sceneID = id
                self.preferences.backdrop = .istanbul
            } catch { self.error = "Could not add this photo: \(error.localizedDescription)" }
        }
    }
}
