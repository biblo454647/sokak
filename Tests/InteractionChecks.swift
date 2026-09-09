import AppKit
import MetalKit

/// Opt-in native QA. Uses bundled photographs, isolated preferences and only
/// this process's windows. Outputs aggregate timings, never desktop captures.
@MainActor @main struct InteractionChecks {
    static func pump(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    static func run(_ delegate: AppDelegate) async throws {
        let model = delegate.model
        model.preferences.sound = false
        model.preferences.backdrop = .desktop
        guard let menu = NSApp.keyWindow else { throw CocoaError(.coderInvalidValue) }
        let original = menu.frame
        var maximumDelta: CGFloat = 0
        for backdrop in [Backdrop.desktop, .istanbul] {
            model.preferences.backdrop = backdrop
            for running in [false, true] {
                if running { model.start() } else { model.stop() }
                for weather in [Weather.snow, .mist, .rain, .snow, .rain] {
                    model.chooseWeather(weather); await pump(0.15)
                    let delta = max(abs(menu.frame.minX - original.minX), abs(menu.frame.minY - original.minY))
                    maximumDelta = max(maximumDelta, delta)
                    guard menu.isVisible, delta < 1, menu.frame.size == original.size else {
                        throw NSError(domain: "Sokak.QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Menu changed: visible=\(menu.isVisible), delta=\(delta), size=\(menu.frame.size), original=\(original.size), weather=\(weather), backdrop=\(backdrop), running=\(running)"])
                    }
                }
            }
        }
        model.stop(); model.closePopover?()
        let navigation = try await NavigationChecks.run(model)
        let gpu = try WeatherGPU()
        guard let screen = NSScreen.main, let scene = model.scenes.first(where: { $0.id == "galata-rain" }) else { throw CocoaError(.coderInvalidValue) }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: gpu.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        let surface = GlassSimulation(seed: 741)
        let size = SIMD2(Float(screen.frame.width), Float(screen.frame.height))
        for _ in 0..<7200 { surface.update(deltaTime: 1 / 60, size: size, weather: .rain, intensity: 1, wind: 0.25, gentle: false) }
        var preferences = Preferences()
        preferences.weather = .rain; preferences.intensity = 1; preferences.economical = true
        let renderer = WeatherRenderer(gpu: gpu, preferences: preferences, surface: surface)
        renderer.configure(preferences, photoURL: Assets.url(for: scene))
        view.delegate = renderer; window.contentView = view
        var samples: [(Double, Double, Bool, Bool)] = []
        renderer.onPresentedFrame = { samples.append(($0, $1, $2, $3)) }
        window.orderFrontRegardless(); await pump(1.2)
        for _ in 0..<3 { renderer.wipeGlass(); await pump(2.7) }
        await pump(0.5); view.isPaused = true; window.close()
        func intervals(wiping: Bool) -> [Double] {
            zip(samples, samples.dropFirst()).compactMap { a, b in
                a.2 == wiping && b.2 == wiping && b.0 > a.0 ? (b.0 - a.0) * 1000 : nil
            }.sorted()
        }
        func percentile(_ values: [Double], _ p: Double) -> Double {
            values.isEmpty ? 0 : values[min(values.count - 1, Int(Double(values.count - 1) * p))]
        }
        let active = intervals(wiping: true), idle = intervals(wiping: false)
        guard active.count > 60 else { throw NSError(domain: "Sokak.QA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Insufficient presented frames: samples=\(samples.count), active=\(samples.filter { $0.2 }.count), positive stamps=\(samples.filter { $0.0 > 0 }.count), intervals=\(active.count), requestedFPS=\(view.preferredFramesPerSecond)"]) }
        let report: [String: Any] = ["streetNavigation": navigation, "menuMaximumOriginDeltaPoints": maximumDelta, "menuWeatherTransitions": 20,
            "timingSource": samples.allSatisfy { $0.3 } ? "drawable presentation timestamps" : "presentation-handler clock; display did not supply drawable timestamps",
            "wiperPresentedIntervals": active.count, "wiperMedianIntervalMS": percentile(active, 0.5),
            "wiperP95IntervalMS": percentile(active, 0.95), "economyIdleMedianIntervalMS": percentile(idle, 0.5),
            "wiperP95GPUMS": percentile(samples.filter { $0.2 }.map { $0.1 }.sorted(), 0.95),
            "renderPixels": [Int(view.drawableSize.width), Int(view.drawableSize.height)],
            "result": "passed"]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let output = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent("interaction-report.json"))
        print(String(decoding: data, as: UTF8.self))
    }
    static func main() {
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                do { try await run(delegate); app.terminate(nil) }
                catch { fputs("Interaction check failed: \(error)\n", stderr); exit(1) }
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }
}
