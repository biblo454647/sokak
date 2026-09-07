import AppKit
import MetalKit
import AVFoundation
import SwiftUI

enum QualityCheck {
    /// Only renders app-owned photographs and views. Never captures the desktop.
    static func run(output: URL, model: AppModel) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let gpu = try WeatherGPU()
        guard !model.scenes.isEmpty, model.scenes.allSatisfy({ $0.isPersonal != true }) else { throw CocoaError(.fileReadCorruptFile) }
        guard MemoryLayout<WeatherUniforms>.stride == 64, MemoryLayout<GlassSprite>.stride == 48 else { throw CocoaError(.coderInvalidValue) }
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
            let sceneID = weather == .snow ? "bagcilar-evening" : "galata-rain"
            guard let scene = model.scenes.first(where: { $0.id == sceneID }) else { throw CocoaError(.fileNoSuchFile) }
            let photo = try gpu.loadPhoto(Assets.url(for: scene))
            for desktop in [false, true] {
                let name = weather.rawValue + (desktop ? "-transparent" : "-scene")
                let result = try render(gpu: gpu, weather: weather, photo: desktop ? nil : photo, time: 13.7, output: output.appendingPathComponent(name + ".png"))
                frames.append(["frame": name, "nonzeroAlphaPixels": result.nonzeroAlpha, "meanAlpha": result.meanAlpha])
                if !desktop && result.nonzeroAlpha != 1440 * 900 { throw CocoaError(.coderInvalidValue) }
                if desktop && (result.meanAlpha <= 0 || result.meanAlpha > 0.4) { throw CocoaError(.coderInvalidValue) }
                if weather != .mist {
                    let dry = try render(gpu: gpu, weather: weather, photo: desktop ? nil : photo, time: 13.7, glass: false)
                    let later = try render(gpu: gpu, weather: weather, photo: desktop ? nil : photo, time: 14.7)
                    let contact = difference(result.pixels, dry.pixels)
                    let movement = difference(result.pixels, later.pixels)
                    guard contact > 0.04, movement > 0.001 else {
                        throw NSError(domain: "Sokak.QA", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): glass difference \(contact), temporal difference \(movement)"])
                    }
                    frames[frames.count-1]["glassDifference"] = contact
                    frames[frames.count-1]["temporalDifference"] = movement
                }
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
        if CommandLine.arguments.contains("--motion-preview") {
            try motionPreviews(gpu: gpu, model: model, output: output)
            report["motionPreviews"] = ["rain-window.mp4", "snow-window.mp4"]
        }
        report["result"] = "passed"
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("report.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    struct Frame {
        let nonzeroAlpha: Int
        let meanAlpha: Double
        let pixels: [UInt8]
        let gpuMilliseconds: Double
    }
    static func render(gpu: WeatherGPU, weather: Weather, photo: MTLTexture?, time: Float, output: URL? = nil,
                       width: Int = 1440, height: Int = 900, glass: Bool = true,
                       surface: GlassSimulation? = nil, resources: WeatherFrameResources? = nil) throws -> Frame {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Use the hardware-appropriate CPU/GPU-accessible default storage mode.
        guard let target = gpu.device.makeTexture(descriptor: descriptor), let command = gpu.queue.makeCommandBuffer() else { throw CocoaError(.coderInvalidValue) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let size = SIMD2<Float>(1440, 900)
        let simulation = surface ?? GlassSimulation(seed: 741)
        if surface == nil && glass {
            for _ in 0..<Int(time * 60) {
                simulation.update(deltaTime: 1 / 60, size: size, weather: weather, intensity: 0.65, wind: 0.25, gentle: false)
            }
        }
        let u = WeatherUniforms(size: size, time: time, weather: weather.index, intensity: 0.65, wind: 0.25, dimming: photo == nil ? 0 : 0.12, hasPhoto: photo == nil ? 0 : 1, photoSize: SIMD2(Float(photo?.width ?? 1), Float(photo?.height ?? 1)), gentle: 0, glass: glass ? 1 : 0)
        try gpu.encode(command: command, pass: pass, resources: resources ?? WeatherFrameResources(), uniforms: u,
                       photo: photo, sprites: glass ? simulation.sprites : [])
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
        if let output {
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output)
        }
        return Frame(nonzeroAlpha: count, meanAlpha: Double(sum) / Double(width * height * 255), pixels: pixels,
                     gpuMilliseconds: max(0, command.gpuEndTime - command.gpuStartTime) * 1000)
    }

    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        zip(a, b).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(a.count)
    }

    private static func motionPreviews(gpu: WeatherGPU, model: AppModel, output: URL) throws {
        let width = 960, height = 600
        for weather in [Weather.rain, .snow] {
            let scene = model.scenes.first { $0.id == (weather == .rain ? "galata-rain" : "bagcilar-evening") }!
            let photo = try gpu.loadPhoto(Assets.url(for: scene))
            let url = output.appendingPathComponent(weather.rawValue + "-window.mp4")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            let simulation = GlassSimulation(seed: 741), resources = WeatherFrameResources()
            for _ in 0..<480 { simulation.update(deltaTime: 1 / 60, size: SIMD2(1440, 900), weather: weather, intensity: 0.65, wind: 0.25, gentle: false) }
            var timings: [Double] = []
            for i in 0..<300 {
                try autoreleasepool {
                    simulation.update(deltaTime: 1 / 30, size: SIMD2(1440, 900), weather: weather, intensity: 0.65, wind: 0.25, gentle: false)
                    let frame = try render(gpu: gpu, weather: weather, photo: photo, time: 8 + Float(i) / 30,
                                           width: width, height: height, surface: simulation, resources: resources)
                    timings.append(frame.gpuMilliseconds)
                    let deadline = Date().addingTimeInterval(10)
                    while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
                    }
                    guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                    var pixel: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { throw CocoaError(.fileWriteUnknown) }
                    CVPixelBufferLockBaseAddress(pixel, [])
                    let rowBytes = CVPixelBufferGetBytesPerRow(pixel)
                    frame.pixels.withUnsafeBytes { source in
                        for row in 0..<height {
                            memcpy(CVPixelBufferGetBaseAddress(pixel)!.advanced(by: row * rowBytes), source.baseAddress!.advanced(by: row * width * 4), width * 4)
                        }
                    }
                    CVPixelBufferUnlockBaseAddress(pixel, [])
                    guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                }
            }
            input.markAsFinished()
            writer.finishWriting {}
            let deadline = Date().addingTimeInterval(20)
            while writer.status == .writing && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            timings.sort()
            print("Motion preview: \(weather.rawValue), 300 frames, median GPU \(timings[timings.count / 2]) ms at 960 × 600.")
        }
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
