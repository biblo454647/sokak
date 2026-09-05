import AppKit
import MetalKit
import AVFoundation
import SwiftUI

enum QualityCheck {
    /// Only renders app-owned photographs and views. Never captures the desktop.
    static func run(output: URL, model: AppModel) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let gpu = try WeatherGPU()
        guard model.scenes.count == 11, model.scenes.allSatisfy({ $0.isPersonal != true }) else { throw CocoaError(.fileReadCorruptFile) }
        guard MemoryLayout<WeatherUniforms>.stride == 48 else { throw CocoaError(.coderInvalidValue) }
        var report: [String: Any] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "scenes": model.scenes.count,
            "uniformBytes": MemoryLayout<WeatherUniforms>.stride,
            "personalPhotosExcluded": true
        ]
        let saved = model.preferences
        var changes = 0
        model.onChange = { changes += 1 }
        model.preferences.intensity = 1.8
        guard model.preferences.intensity == 1, changes == 1 else { throw CocoaError(.coderInvalidValue) }
        model.preferences = saved
        model.onChange = nil
        report["publishedSettingsRecovery"] = "passed"
        // Check the RGBX-JPEG/texture conversion with an unambiguous red image.
        let colorImage = NSImage(size: NSSize(width: 16, height: 16))
        colorImage.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); colorImage.unlockFocus()
        let colorURL = output.appendingPathComponent("color-reference.png")
        try NSBitmapImageRep(data: colorImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: colorURL)
        let colorTexture = try gpu.loadPhoto(colorURL)
        let colorResult = output.appendingPathComponent("color-render.png")
        _ = try render(gpu: gpu, weather: .mist, photo: colorTexture, time: 2, output: colorResult)
        let color = NSBitmapImageRep(data: try Data(contentsOf: colorResult))!.colorAt(x: 720, y: 450)!.usingColorSpace(.sRGB)!
        guard color.redComponent > 0.65, color.blueComponent < 0.2, color.greenComponent < 0.2 else { throw CocoaError(.coderInvalidValue) }
        report["photoColorRegression"] = "passed"
        var frames: [[String: Any]] = []
        for weather in Weather.allCases {
            let sceneID = weather == .snow ? "bagcilar-evening" : "balat"
            guard let scene = model.scenes.first(where: { $0.id == sceneID }) else { throw CocoaError(.fileNoSuchFile) }
            let photo = try gpu.loadPhoto(Assets.url(for: scene))
            for desktop in [false, true] {
                let name = weather.rawValue + (desktop ? "-transparent" : "-scene")
                let result = try render(gpu: gpu, weather: weather, photo: desktop ? nil : photo, time: 13.7, output: output.appendingPathComponent(name + ".png"))
                frames.append(["frame": name, "nonzeroAlphaPixels": result.0, "meanAlpha": result.1])
                if !desktop && result.0 != 1440 * 900 { throw CocoaError(.coderInvalidValue) }
                if desktop && (result.1 <= 0 || result.1 > 0.4) { throw CocoaError(.coderInvalidValue) }
            }
        }
        for scene in model.scenes {
            guard FileManager.default.fileExists(atPath: Assets.url(for: scene).path), Assets.thumbnail(scene, maxSize: 80) != nil else { throw CocoaError(.fileReadCorruptFile) }
        }
        var audio: [[String: Any]] = []
        for weather in Weather.allCases {
            let url = Assets.root.appendingPathComponent("Audio/\(weather.rawValue).m4a")
            let file = try AVAudioFile(forReading: url)
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.prepareToPlay(), file.length > 44100 * 30, file.processingFormat.channelCount == 2 else { throw CocoaError(.fileReadCorruptFile) }
            audio.append(["weather": weather.rawValue, "frames": file.length, "seconds": player.duration, "channels": file.processingFormat.channelCount])
        }
        report["frames"] = frames
        report["audio"] = audio
        model.preferences.backdrop = .istanbul
        try snapshotUI(model: model, output: output.appendingPathComponent("menu.png"))
        model.libraryVisible = true
        try snapshotUI(model: model, output: output.appendingPathComponent("library.png"))
        report["result"] = "passed"
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("report.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    static func render(gpu: WeatherGPU, weather: Weather, photo: MTLTexture?, time: Float, output: URL) throws -> (Int, Double) {
        let width = 1440, height = 900
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Use the hardware-appropriate CPU/GPU-accessible default storage mode.
        guard let target = gpu.device.makeTexture(descriptor: descriptor), let command = gpu.queue.makeCommandBuffer() else { throw CocoaError(.coderInvalidValue) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw CocoaError(.coderInvalidValue) }
        let u = WeatherUniforms(size: SIMD2(Float(width), Float(height)), time: time, weather: weather.index, intensity: 0.65, wind: 0.25, dimming: photo == nil ? 0 : 0.12, hasPhoto: photo == nil ? 0 : 1, photoSize: SIMD2(Float(photo?.width ?? 1), Float(photo?.height ?? 1)), gentle: 0)
        gpu.encode(encoder, uniforms: u, photo: photo)
        encoder.endEncoding()
        if target.storageMode == .managed {
            guard let blit = command.makeBlitCommandEncoder() else { throw CocoaError(.coderInvalidValue) }
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { throw command.error ?? CocoaError(.coderInvalidValue) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        var count = 0, sum = 0
        for index in stride(from: 3, to: pixels.count, by: 4) { if pixels[index] > 0 { count += 1 }; sum += Int(pixels[index]) }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output)
        return (count, Double(sum) / Double(width * height * 255))
    }

    private static func snapshotUI(model: AppModel, output: URL) throws {
        let view = NSHostingView(rootView: MenuView(model: model, height: 730))
        view.frame = NSRect(x: 0, y: 0, width: 390, height: 730)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: output)
        window.close()
    }
}
