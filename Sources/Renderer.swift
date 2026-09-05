import AppKit
import MetalKit
import ImageIO

struct WeatherUniforms {
    var size: SIMD2<Float>
    var time: Float
    var weather: Float
    var intensity: Float
    var wind: Float
    var dimming: Float
    var hasPhoto: Float
    var photoSize: SIMD2<Float>
    var gentle: Float
    var padding: Float = 0
}

final class WeatherGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let background: MTLRenderPipelineState
    let particles: MTLRenderPipelineState
    let placeholder: MTLTexture

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Sokak", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal graphics are unavailable on this Mac."])
        }
        self.device = device
        self.queue = queue
        let source = try String(contentsOf: Assets.root.appendingPathComponent("Weather.metal"), encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            d.colorAttachments[0].isBlendingEnabled = true
            d.colorAttachments[0].sourceRGBBlendFactor = .one
            d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            d.colorAttachments[0].sourceAlphaBlendFactor = .one
            d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        background = try pipeline("backgroundVertex", "backgroundFragment")
        particles = try pipeline("particleVertex", "particleFragment")
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholder = device.makeTexture(descriptor: d) else { throw CocoaError(.coderInvalidValue) }
        self.placeholder = placeholder
        var zero: UInt32 = 0
        placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)
    }

    func loadPhoto(_ url: URL) throws -> MTLTexture {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        // Normalize explicitly to RGBA. JPEG decoders may provide RGBX layouts;
        // interpreting the unused byte as a colour channel creates a blue cast.
        let width = cg.width, height = cg.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CocoaError(.fileReadCorruptFile) }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        // Keep Metal's platform default: shared on Apple GPUs, managed on Intel/AMD.
        // Non-Apple GPUs do not support shared storage for textures.
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.fileReadTooLarge) }
        rgba.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    func encode(_ encoder: MTLRenderCommandEncoder, uniforms input: WeatherUniforms, photo: MTLTexture?) {
        var u = input
        encoder.setRenderPipelineState(background)
        encoder.setFragmentBytes(&u, length: MemoryLayout<WeatherUniforms>.stride, index: 0)
        encoder.setFragmentTexture(photo ?? placeholder, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        if u.weather < 1.5 {
            encoder.setRenderPipelineState(particles)
            encoder.setVertexBytes(&u, length: MemoryLayout<WeatherUniforms>.stride, index: 0)
            let density = Float(u.weather < 0.5 ? 1450 : 620)
            let area = min(2.8, max(0.35, (u.size.x * u.size.y) / (1440 * 900)))
            let count = Int((70 + density * u.intensity) * area * (u.gentle > 0.5 ? 0.65 : 1))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        }
    }
}

final class WeatherRenderer: NSObject, MTKViewDelegate {
    let gpu: WeatherGPU
    private var preferences: Preferences
    private var photo: MTLTexture?
    private var photoURL: URL?
    private let start = CACurrentMediaTime()
    private let gentle = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var onError: ((String) -> Void)?
    private var hasReportedError = false

    init(gpu: WeatherGPU, preferences: Preferences) {
        self.gpu = gpu
        self.preferences = preferences
        super.init()
    }
    func configure(_ preferences: Preferences, photoURL: URL?) throws {
        self.preferences = preferences
        if self.photoURL != photoURL {
            photo = try photoURL.map(gpu.loadPhoto)
            self.photoURL = photoURL
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard !view.isPaused, view.bounds.width > 0, view.bounds.height > 0,
              let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = gpu.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let u = WeatherUniforms(size: SIMD2(Float(view.bounds.width), Float(view.bounds.height)),
                                time: Float(CACurrentMediaTime() - start), weather: preferences.weather.index,
                                intensity: Float(preferences.intensity), wind: Float(preferences.wind),
                                dimming: Float(preferences.dimming), hasPhoto: photo == nil ? 0 : 1,
                                photoSize: SIMD2(Float(photo?.width ?? 1), Float(photo?.height ?? 1)), gentle: gentle ? 1 : 0)
        gpu.encode(encoder, uniforms: u, photo: photo)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] command in
            guard command.status == .error else { return }
            DispatchQueue.main.async {
                guard let self, !self.hasReportedError else { return }
                self.hasReportedError = true
                self.onError?("The graphics renderer stopped. Try Low power mode, then start again.")
            }
        }
        command.commit()
    }
}

final class WeatherWindow: NSWindow {
    var immersive = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { immersive }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

final class OverlayController {
    private let model: AppModel
    private var gpu: WeatherGPU?
    private var windows: [(WeatherWindow, MTKView, WeatherRenderer)] = []
    private var signature = ""
    private var currentScreenID: String?
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.refreshDisplays(); self?.signature = ""; self?.update()
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.model.stop() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in self?.update() })
    }
    func stop() {
        windows.forEach { $0.1.isPaused = true; $0.0.orderOut(nil); $0.0.close() }
        windows.removeAll()
        signature = ""
        currentScreenID = nil
    }
    func focusImmersive() {
        guard model.running, model.preferences.backdrop == .istanbul else { return }
        NSApp.activate(ignoringOtherApps: true)
        let window = windows.first(where: { $0.0.frame.contains(NSEvent.mouseLocation) })?.0 ?? windows.first?.0
        window?.makeKeyAndOrderFront(nil)
    }
    func update() {
        guard model.running else { stop(); return }
        let p = model.preferences
        if currentScreenID == nil {
            currentScreenID = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }).map(AppModel.id)
        }
        let screens: [NSScreen]
        if p.display == "all" { screens = NSScreen.screens }
        else {
            let id = p.display == "current" ? currentScreenID : p.display
            screens = NSScreen.screens.first(where: { AppModel.id(for: $0) == id }).map { [$0] } ?? Array(NSScreen.screens.prefix(1))
        }
        let key = p.backdrop.rawValue + p.display + screens.map { AppModel.id(for: $0) + NSStringFromRect($0.frame) }.joined()
        do {
            if gpu == nil { gpu = try WeatherGPU() }
            guard let gpu else { return }
            if signature != key {
                windows.forEach { $0.1.isPaused = true; $0.0.close() }
                windows.removeAll()
                for screen in screens {
                    let window = WeatherWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.immersive = p.backdrop == .istanbul
                    window.ignoresMouseEvents = !window.immersive
                    window.onEscape = { [weak model] in model?.stop() }
                    window.backgroundColor = .clear
                    window.isOpaque = false
                    window.hasShadow = false
                    window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                    window.hidesOnDeactivate = false
                    window.animationBehavior = .none
                    let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: gpu.device)
                    view.colorPixelFormat = .bgra8Unorm
                    view.clearColor = MTLClearColorMake(0, 0, 0, 0)
                    view.wantsLayer = true
                    view.layer?.isOpaque = false
                    view.framebufferOnly = true
                    view.autoresizingMask = [.width, .height]
                    let renderer = WeatherRenderer(gpu: gpu, preferences: p)
                    renderer.onError = { [weak model] message in model?.stop(); model?.error = message }
                    view.delegate = renderer
                    window.contentView = view
                    if window.immersive {
                        let label = NSTextField(labelWithString: "ESC TO LEAVE  ·  ⌃⌥⌘S TO PAUSE  ·  MENU BAR FOR CONTROLS")
                        label.font = .systemFont(ofSize: 10, weight: .medium)
                        label.textColor = NSColor.white.withAlphaComponent(0.75)
                        label.alignment = .center
                        label.frame = NSRect(x: 0, y: 25, width: screen.frame.width, height: 16)
                        label.autoresizingMask = [.width]
                        view.addSubview(label)
                    }
                    windows.append((window, view, renderer))
                }
                signature = key
            }
            for (window, view, renderer) in windows {
                try renderer.configure(p, photoURL: p.backdrop == .istanbul ? model.scene.map(Assets.url) : nil)
                view.preferredFramesPerSecond = p.economical || ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
                view.isPaused = false
                if !window.isVisible { window.orderFrontRegardless() }
            }
            if p.backdrop == .istanbul, !NSApp.windows.contains(where: { $0.isKeyWindow && !($0 is WeatherWindow) }) {
                windows.first?.0.makeKey()
            }
        } catch {
            model.stop()
            model.error = "Could not start the scene: \(error.localizedDescription)"
        }
    }
}
