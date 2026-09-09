import AppKit
import MetalKit

@MainActor enum NavigationChecks {
    static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(12)
        while !condition() {
            guard Date() < deadline else { throw CocoaError(.coderInvalidValue) }
            await InteractionChecks.pump(0.02)
        }
    }
    static func run(_ model: AppModel) async throws -> [String: Any] {
        let saved = model.preferences
        defer { model.stop(); model.preferences = saved }
        model.preferences.weather = .rain
        model.preferences.backdrop = .istanbul
        model.preferences.matchSeason = true
        model.preferences.sceneID = "galata-rain"
        model.preferences.intensity = 1
        model.preferences.windowGlass = true
        model.preferences.timerMinutes = 15
        let stoppedScene = model.preferences.sceneID
        model.browseStreet(1)
        guard model.preferences.sceneID == stoppedScene else { throw CocoaError(.coderInvalidValue) }
        model.start()
        guard let window = NSApp.windows.compactMap({ $0 as? WeatherWindow }).first(where: { $0.isVisible }),
              let view = window.contentView as? MTKView, let renderer = view.delegate as? WeatherRenderer else { throw CocoaError(.coderInvalidValue) }
        try await waitUntil { renderer.navigationSnapshot.photo == Assets.url(for: model.scene!) }
        try await waitUntil { renderer.navigationSnapshot.drops > 10 }
        var times: [Double] = []
        renderer.onPresentedFrame = { stamp, _, _, _ in times.append(stamp) }
        defer { renderer.onPresentedFrame = nil }
        model.wipeGlass(); await InteractionChecks.pump(0.08)
        let before = renderer.navigationSnapshot
        guard before.wiping else { throw CocoaError(.coderInvalidValue) }
        let preferencesBefore = model.preferences
        let right = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{F703}",
                                     charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124)!
        window.keyDown(with: right)
        guard model.preferences.sceneID == "paris-turenne", model.running,
              renderer.navigationSnapshot.photo == before.photo,
              renderer.navigationSnapshot.elapsed == before.elapsed,
              renderer.navigationSnapshot.drops == before.drops,
              renderer.navigationSnapshot.wiping else { throw CocoaError(.coderInvalidValue) }
        var restored = model.preferences; restored.sceneID = preferencesBefore.sceneID
        guard restored == preferencesBefore else { throw CocoaError(.coderInvalidValue) }
        try await waitUntil { renderer.navigationSnapshot.photo == Assets.url(for: model.scene!) }
        guard renderer.navigationSnapshot.elapsed > before.elapsed, model.remaining != nil,
              (window.contentView as? MTKView)?.delegate === renderer, window.isVisible else { throw CocoaError(.coderInvalidValue) }
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        guard let next = buttons.first(where: { $0.action == #selector(WeatherWindow.nextStreet) }),
              let previous = buttons.first(where: { $0.action == #selector(WeatherWindow.previousStreet) }) else { throw CocoaError(.coderInvalidValue) }
        // Dispatch the button's real target/action without performClick's blocking
        // highlight delay, which would contaminate display-cadence measurements.
        guard NSApp.sendAction(previous.action!, to: previous.target, from: previous) else { throw CocoaError(.coderInvalidValue) }
        guard model.preferences.sceneID == "galata-rain" else { throw CocoaError(.coderInvalidValue) }
        guard NSApp.sendAction(next.action!, to: next.target, from: next) else { throw CocoaError(.coderInvalidValue) }
        guard model.preferences.sceneID == "paris-turenne" else { throw CocoaError(.coderInvalidValue) }
        // Repeated arrows must resolve to the final selection, even if older files
        // are still decoding. The same window and wet pane remain alive.
        let burstStart = CACurrentMediaTime()
        for _ in 0..<29 { window.keyDown(with: right) }
        let burstMilliseconds = (CACurrentMediaTime() - burstStart) * 1000
        let finalURL = Assets.url(for: model.scene!)
        try await waitUntil { renderer.navigationSnapshot.photo == finalURL }
        await InteractionChecks.pump(0.25)
        guard renderer.navigationSnapshot.photo == finalURL, model.running,
              renderer.navigationSnapshot.elapsed > before.elapsed,
              renderer.navigationSnapshot.impacts >= before.impacts else { throw CocoaError(.coderInvalidValue) }
        let intervals = zip(times, times.dropFirst()).map { ($1 - $0) * 1000 }.sorted()
        guard intervals.count > 5 else { throw CocoaError(.coderInvalidValue) }
        // A failed photo keeps the previous image and the live rain.
        var failure = false
        renderer.onPhotoError = { _ in failure = true }
        renderer.configure(model.preferences, photoURL: Assets.root.appendingPathComponent("missing-photo-test.jpg"))
        try await waitUntil { failure }
        guard renderer.navigationSnapshot.photo == finalURL, model.running else { throw CocoaError(.coderInvalidValue) }
        model.chooseWeather(.snow)
        let snow = model.preferences.sceneID
        window.keyDown(with: right)
        guard model.preferences.sceneID != snow, model.scene!.winter, model.running else { throw CocoaError(.coderInvalidValue) }
        try await waitUntil { renderer.navigationSnapshot.photo == Assets.url(for: model.scene!) }
        model.preferences.backdrop = .desktop
        let desktopScene = model.preferences.sceneID
        model.browseStreet(1)
        guard model.preferences.sceneID == desktopScene else { throw CocoaError(.coderInvalidValue) }
        try await loaderCancellation(gpu: renderer.gpu)
        return ["result": "passed", "rapidArrowEvents": 29,
                "synchronousArrowBurstMS": burstMilliseconds,
                "preserves": "window, renderer, wet pane, active wiper, weather and timer settings",
                "photoFailure": "retains previous image and running session",
                "presentedIntervals": intervals.count,
                "p95PresentationHandlerIntervalMS": intervals[Int(Double(intervals.count - 1) * 0.95)],
                "maximumPresentationHandlerIntervalMS": intervals.last!,
                "loader": "obsolete queued requests and late results discarded; cancellation passed"]
    }

    static func loaderCancellation(gpu: WeatherGPU) async throws {
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let texture = gpu.placeholder
        let loader = PhotoLoader { url in
            guard !Thread.isMainThread else { throw CocoaError(.coderInvalidValue) }
            if url.lastPathComponent == "first" {
                started.signal()
                guard release.wait(timeout: .now() + 10) == .success else { throw CocoaError(.coderInvalidValue) }
            }
            return texture
        }
        var delivered: [String] = []
        loader.load(URL(fileURLWithPath: "/first")) { _ in delivered.append("first") }
        try await waitUntil { started.wait(timeout: .now()) == .success }
        loader.load(URL(fileURLWithPath: "/obsolete")) { _ in delivered.append("obsolete") }
        loader.load(URL(fileURLWithPath: "/latest")) { _ in
            precondition(Thread.isMainThread)
            delivered.append("latest")
        }
        release.signal()
        try await waitUntil { !delivered.isEmpty }
        guard delivered == ["latest"] else { throw CocoaError(.coderInvalidValue) }
        loader.load(URL(fileURLWithPath: "/cancelled")) { _ in delivered.append("cancelled") }
        loader.cancel()
        await InteractionChecks.pump(0.1)
        guard delivered == ["latest"] else { throw CocoaError(.coderInvalidValue) }
    }
}
