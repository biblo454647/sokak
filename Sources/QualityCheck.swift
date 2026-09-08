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
        var wipes = 0
        model.onWipe = { wipes += 1 }
        model.preferences.weather = .rain; model.preferences.windowGlass = true
        model.wipeGlass()
        guard wipes == 0 else { throw CocoaError(.coderInvalidValue) }
        model.start(); model.wipeGlass()
        model.preferences.windowGlass = false; model.wipeGlass()
        model.preferences.windowGlass = true; model.preferences.weather = .snow; model.wipeGlass()
        model.stop(); model.onWipe = nil; model.preferences = saved
        guard wipes == 1 else { throw CocoaError(.coderInvalidValue) }
        report["wiperControls"] = "Enabled only for a running rain session with glass"
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
        report["photoVisibilityAndRainIntensity"] = try visibilityRegression(gpu: gpu, output: output)
        report["exteriorCache"] = try cacheRegression(gpu: gpu, photo: colorTexture)
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
                if weather == .rain && !desktop {
                    _ = try render(gpu: gpu, weather: .rain, photo: photo, time: 13.7,
                                   output: output.appendingPathComponent("rain-light.png"), intensity: 0.1)
                    _ = try render(gpu: gpu, weather: .rain, photo: photo, time: 13.7,
                                   output: output.appendingPathComponent("rain-heavy.png"), intensity: 1, focus: 1)
                }
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
            if CommandLine.arguments.contains("--gallery-preview") {
                let photo = try gpu.loadPhoto(Assets.url(for: scene))
                let weather: Weather = scene.winter ? .snow : scene.suits(.rain) ? .rain : .mist
                let frame = try render(gpu: gpu, weather: weather, photo: photo, time: 13.7,
                                       output: output.appendingPathComponent("gallery-\(scene.id).png"))
                guard frame.nonzeroAlpha == 1440 * 900 else { throw CocoaError(.coderInvalidValue) }
            }
        }
        if CommandLine.arguments.contains("--gallery-preview") { report["galleryRenderedScenes"] = model.scenes.count }
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
        let tapPlayer = try RainTapPlayer()
        tapPlayer.play([RainContact(position: .zero, radius: 6, seed: 0.4, pan: 0)], gain: 0)
        guard tapPlayer.playedContacts == 0 else { throw CocoaError(.coderInvalidValue) }
        for variant in 0..<RainTapSound.variants {
            let samples = RainTapSound.samples(variant: variant)
            guard samples.count == 4410, samples.allSatisfy(\.isFinite), samples.first == 0, samples.last == 0,
                  (samples.map(abs).max() ?? 1) <= 0.381 else { throw CocoaError(.coderInvalidValue) }
        }
        tapPlayer.stop()
        report["contactAudio"] = "16 decodable original tap variants; bounded peaks; zero-gain contacts remain silent"
        let swish = WiperSound.samples()
        guard swish.allSatisfy(\.isFinite), (swish.map(abs).max() ?? 1) <= 0.181,
              swish.prefix(2).allSatisfy({ $0 == 0 }), swish.suffix(2).allSatisfy({ $0 == 0 }) else { throw CocoaError(.coderInvalidValue) }
        let wiperAudio = try AVAudioPlayer(data: RainTapSound.wave(samples: swish, channels: 2))
        guard wiperAudio.prepareToPlay(), wiperAudio.numberOfChannels == 2,
              abs(wiperAudio.duration - Double(WiperMotion.duration)) < 0.001 else { throw CocoaError(.fileReadCorruptFile) }
        report["wiperAudio"] = "Bounded stereo rubber strokes match the 2.35-second sweep; silent endpoints"
        model.preferences.backdrop = .istanbul
        try snapshotUI(model: model, output: output.appendingPathComponent("menu.png"))
        model.libraryVisible = true
        try snapshotUI(model: model, output: output.appendingPathComponent("library.png"))
        if CommandLine.arguments.contains("--motion-preview") {
            try motionPreviews(gpu: gpu, model: model, output: output)
            report["motionPreviews"] = ["rain-window.mp4", "rain-preview.wav", "snow-window.mp4", "wiper-window.mp4", "wiper-preview.wav"]
        }
        report["result"] = "passed"
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("report.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    struct Frame {
        let width: Int
        let height: Int
        let nonzeroAlpha: Int
        let meanAlpha: Double
        let pixels: [UInt8]
        let gpuMilliseconds: Double
    }
    static func cacheRegression(gpu: WeatherGPU, photo: MTLTexture) throws -> String {
        let resources = WeatherFrameResources(), dry = GlassSimulation(seed: 1)
        var expectedPasses = 0
        let cases: [(Weather, Float, MTLTexture?, Int, Bool)] = [
            (.rain, 0.65, photo, 1440, true), (.rain, 0.65, photo, 1440, false),
            (.snow, 0.65, photo, 1440, false), (.rain, 1, photo, 1440, true),
            (.rain, 1, nil, 1440, true), (.mist, 1, nil, 1440, true),
            (.mist, 1, nil, 1440, true), (.rain, 1, nil, 1440, true),
            (.rain, 1, photo, 2880, true)]
        for (i, item) in cases.enumerated() {
            let (weather, focus, texture, width, refresh) = item
            let time = Float(i)
            let cached = try render(gpu: gpu, weather: weather, photo: texture, time: time, width: width,
                                    focus: focus, surface: dry, resources: resources)
            let reference = try render(gpu: gpu, weather: weather, photo: texture, time: time, width: width,
                                       focus: focus, surface: dry)
            if refresh { expectedPasses += 1 }
            guard cached.pixels == reference.pixels, resources.exteriorPasses == expectedPasses else {
                throw NSError(domain: "Sokak.QA", code: 4, userInfo: [NSLocalizedDescriptionKey: "Stale exterior or redundant pass at cache case \(i)"])
            }
        }
        return "Cached frames match fresh rendering; photo, focus, size and moving-mist invalidation pass"
    }

    static func render(gpu: WeatherGPU, weather: Weather, photo: MTLTexture?, time: Float, output: URL? = nil,
                       width: Int = 1440, height: Int = 900, glass: Bool = true,
                       intensity: Float = 0.65, focus: Float = 0.65,
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
        if surface == nil && (glass || weather == .rain) {
            for _ in 0..<Int(time * 60) {
                simulation.update(deltaTime: 1 / 60, size: size, weather: weather, intensity: intensity, wind: 0.25, gentle: false)
            }
        }
        let u = WeatherUniforms(size: size, time: time, weather: weather.index, intensity: intensity, wind: 0.25, dimming: photo == nil ? 0 : 0.12, hasPhoto: photo == nil ? 0 : 1, photoSize: SIMD2(Float(photo?.width ?? 1), Float(photo?.height ?? 1)), gentle: 0, glass: glass ? 1 : 0, focus: focus)
        try gpu.encode(command: command, pass: pass, resources: resources ?? WeatherFrameResources(), uniforms: u,
                       photo: photo, sprites: glass || weather == .rain ? simulation.sprites : [])
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
        return Frame(width: width, height: height, nonzeroAlpha: count, meanAlpha: Double(sum) / Double(width * height * 255), pixels: pixels,
                     gpuMilliseconds: max(0, command.gpuEndTime - command.gpuStartTime) * 1000)
    }

    private static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        zip(a, b).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(a.count)
    }

    private static func visibilityRegression(gpu: WeatherGPU, output: URL) throws -> [String: Any] {
        // Primary colours expose channel swaps; small checker tiles expose excess
        // blur even when opacity and a large solid-colour sample both look correct.
        let chart = NSImage(size: NSSize(width: 1440, height: 900))
        chart.lockFocus()
        for (i, color) in [NSColor.red, .green, .blue].enumerated() {
            color.setFill(); NSRect(x: i * 480, y: 450, width: 480, height: 450).fill()
        }
        for y in 0..<19 {
            for x in 0..<60 {
                NSColor(white: (x + y) % 2 == 0 ? 0.2 : 0.8, alpha: 1).setFill()
                NSRect(x: x * 24, y: y * 24, width: 24, height: min(24, 450 - y * 24)).fill()
            }
        }
        chart.unlockFocus()
        let bitmap = NSBitmapImageRep(data: chart.tiffRepresentation!)!
        func sample(_ frame: Frame, x: Int, y: Int, channel: Int) -> Double {
            let px = x * frame.width / 1440, py = y * frame.height / 900
            var sum = 0
            for dy in -3...3 { for dx in -3...3 { sum += Int(frame.pixels[((py + dy) * frame.width + px + dx) * 4 + channel]) } }
            return Double(sum) / 49
        }
        func contrast(_ frame: Frame) -> Double {
            (0..<8).map { i in
                abs(sample(frame, x: 12 + i * 48, y: 606, channel: 1) - sample(frame, x: 36 + i * 48, y: 606, channel: 1))
            }.reduce(0, +) / 8
        }
        let emptyGlass = GlassSimulation(seed: 1)
        var checks: [[String: Any]] = []
        for format: NSBitmapImageRep.FileType in [.png, .jpeg] {
            let name = format == .png ? "png" : "jpeg"
            let url = output.appendingPathComponent("detail-reference." + name)
            try bitmap.representation(using: format, properties: [.compressionFactor: 0.95])!.write(to: url)
            let texture = try gpu.loadPhoto(url)
            let clear = try render(gpu: gpu, weather: .rain, photo: texture, time: 13.7, glass: false, intensity: 1, surface: emptyGlass)
            for focus: Float in [0.65, 1] {
                let frame = try render(gpu: gpu, weather: .rain, photo: texture, time: 13.7,
                                       output: output.appendingPathComponent("detail-\(name)-\(focus).png"),
                                       intensity: 1, focus: focus, surface: emptyGlass)
                let retained = contrast(frame) / contrast(clear)
                guard retained > 0.75 else {
                    throw NSError(domain: "Sokak.QA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Photo detail lost at focus \(focus): retained \(retained)"])
                }
                for (x, channel) in [(240, 2), (720, 1), (1200, 0)] {
                    guard sample(frame, x: x, y: 200, channel: channel) > 180,
                          (0..<3).filter({ $0 != channel }).allSatisfy({ sample(frame, x: x, y: 200, channel: $0) < 25 }) else {
                        throw NSError(domain: "Sokak.QA", code: 3, userInfo: [NSLocalizedDescriptionKey: "Photo colour channels changed in \(name) at focus \(focus)"])
                    }
                }
                checks.append(["format": name, "focus": focus, "retainedDetailContrast": retained])
            }
            if format == .jpeg {
                let retina = try render(gpu: gpu, weather: .snow, photo: texture, time: 13.7,
                                        width: 2880, height: 1800, intensity: 1, focus: 1, surface: emptyGlass)
                guard retina.nonzeroAlpha == 2880 * 1800, contrast(retina) / contrast(clear) > 0.75,
                      sample(retina, x: 240, y: 200, channel: 2) > 180,
                      sample(retina, x: 240, y: 200, channel: 0) < 25 else { throw CocoaError(.coderInvalidValue) }
            }
        }
        let surface = GlassSimulation(seed: 19)
        surface.reset(size: SIMD2(1440, 900), weather: .rain, intensity: 0, populate: false)
        surface.launchDrop(at: SIMD2(720, 450), radius: 7, duration: 0.3)
        var contactEvents = 0, contactFrame: Frame?, settledFrame: Frame?
        for i in 0..<66 {
            surface.update(deltaTime: 1 / 120, size: SIMD2(1440, 900), weather: .rain, intensity: 0, wind: 0, gentle: false)
            contactEvents += surface.frameContacts.filter { $0.position == SIMD2(720, 450) }.count
            if [24, 42, 65].contains(i) {
                let name = i == 24 ? "approach" : i == 42 ? "contact" : "settle"
                let frame = try render(gpu: gpu, weather: .rain, photo: nil, time: Float(i) / 120,
                                       output: output.appendingPathComponent("roof-\(name).png"), surface: surface)
                if i == 24 { guard contactEvents == 0 else { throw CocoaError(.coderInvalidValue) } }
                if i == 42 { contactFrame = frame }
                if i == 65 { settledFrame = frame }
            }
        }
        // Inspect the contact footprint, rather than rewarding long, opaque streaks.
        func footprint(_ frame: Frame) -> Int {
            var count = 0
            for y in 425..<475 { for x in 695..<745 {
                if frame.pixels[(y * frame.width + x) * 4 + 3] > 8 { count += 1 }
            } }
            return count
        }
        let impactArea = footprint(contactFrame!), settledArea = footprint(settledFrame!)
        guard contactEvents == 1, impactArea > 100, settledArea > 30, impactArea > settledArea else {
            throw NSError(domain: "Sokak.QA", code: 4, userInfo: [NSLocalizedDescriptionKey: "Roof contact missing: events \(contactEvents), spread pixels \(impactArea), settled pixels \(settledArea)"])
        }
        return ["detail": checks, "retinaPhoto": "passed", "roofContactEvents": contactEvents,
                "roofImpactFootprint": impactArea, "roofSettledFootprint": settledArea]
    }

    private static func motionPreviews(gpu: WeatherGPU, model: AppModel, output: URL) throws {
        let width = 960, height = 600
        for (weather, name, wiping) in [(Weather.rain, "rain", false), (.snow, "snow", false), (.rain, "wiper", true)] {
            let scene = model.scenes.first { $0.id == (weather == .rain ? "galata-rain" : "bagcilar-evening") }!
            let photo = try gpu.loadPhoto(Assets.url(for: scene))
            let url = output.appendingPathComponent(name + "-window.mp4")
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
            let fps: Int32 = wiping ? 60 : 30
            let frameCount = Int(fps) * 10
            for _ in 0..<480 { simulation.update(deltaTime: 1 / 60, size: SIMD2(1440, 900), weather: weather, intensity: 0.65, wind: 0.25, gentle: false) }
            if wiping {
                for _ in 0..<2400 { simulation.update(deltaTime: 1 / 60, size: SIMD2(1440, 900), weather: .rain, intensity: 0.65, wind: 0.25, gentle: false) }
            }
            var timings: [Double] = []
            var contacts: [(Double, RainContact)] = []
            for i in 0..<frameCount {
                try autoreleasepool {
                    if wiping && i == Int(fps) * 2 { simulation.wipe() }
                    simulation.update(deltaTime: 1 / Float(fps), size: SIMD2(1440, 900), weather: weather, intensity: 0.65, wind: 0.25, gentle: false)
                    if weather == .rain { contacts += simulation.frameContacts.map { (Double(i) / Double(fps), $0) } }
                    let frame = try render(gpu: gpu, weather: weather, photo: photo, time: 8 + Float(i) / Float(fps),
                                           width: width, height: height, surface: simulation, resources: resources)
                    timings.append(frame.gpuMilliseconds)
                    if wiping && [0, Int(fps) * 5 / 2, Int(fps) * 9 / 2].contains(i) {
                        _ = try render(gpu: gpu, weather: weather, photo: photo, time: 8 + Float(i) / Float(fps),
                                       output: output.appendingPathComponent("wiper-frame-\(i).png"), surface: simulation)
                    }
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
                    guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(i), timescale: fps)) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                }
            }
            input.markAsFinished()
            writer.finishWriting {}
            let deadline = Date().addingTimeInterval(20)
            while writer.status == .writing && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            if weather == .rain {
                try writeRainPreviewAudio(contacts: contacts, output: output.appendingPathComponent(name + "-preview.wav"), wipeAt: wiping ? 2 : nil)
            }
            timings.sort()
            print("Motion preview: \(name), \(frameCount) frames at \(fps) fps, median GPU \(timings[timings.count / 2]) ms at 960 × 600.")
        }
    }

    private static func writeRainPreviewAudio(contacts: [(Double, RainContact)], output: URL, wipeAt: Double? = nil) throws {
        let rate = RainTapSound.sampleRate, length = rate * 10
        let bed = try AVAudioFile(forReading: Assets.root.appendingPathComponent("Audio/rain.m4a"),
                                  commonFormat: .pcmFormatFloat32, interleaved: false)
        guard Int(bed.processingFormat.sampleRate) == rate, bed.processingFormat.channelCount == 2,
              let buffer = AVAudioPCMBuffer(pcmFormat: bed.processingFormat, frameCapacity: AVAudioFrameCount(length)) else { throw CocoaError(.coderInvalidValue) }
        bed.framePosition = AVAudioFramePosition(rate * 8)
        try bed.read(into: buffer, frameCount: AVAudioFrameCount(length))
        guard Int(buffer.frameLength) == length, let channels = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
        let gain: Float = 0.28
        var stereo = [Float](repeating: 0, count: length * 2)
        for i in 0..<length { stereo[i * 2] = channels[0][i] * gain; stereo[i * 2 + 1] = channels[1][i] * gain }
        for (time, contact) in contacts {
            let samples = RainTapSound.samples(variant: RainTapSound.variant(for: contact))
            let start = Int(time * Double(rate)), volume = gain * RainTapSound.gain(for: contact)
            let left = sqrt((1 - contact.pan) * 0.5), right = sqrt((1 + contact.pan) * 0.5)
            for i in samples.indices where start + i < length {
                stereo[(start + i) * 2] += samples[i] * volume * left
                stereo[(start + i) * 2 + 1] += samples[i] * volume * right
            }
        }
        if let wipeAt {
            let samples = WiperSound.samples(), start = Int(wipeAt * Double(rate))
            for i in 0..<(samples.count / 2) where start + i < length {
                stereo[(start + i) * 2] += samples[i * 2] * gain * 0.55
                stereo[(start + i) * 2 + 1] += samples[i * 2 + 1] * gain * 0.55
            }
        }
        for i in 0..<length {
            let envelope = min(1, min(Float(i), Float(length - 1 - i)) / Float(rate / 20))
            stereo[i * 2] *= envelope; stereo[i * 2 + 1] *= envelope
        }
        guard stereo.allSatisfy(\.isFinite), (stereo.map(abs).max() ?? 1) < 0.95 else { throw CocoaError(.coderInvalidValue) }
        try RainTapSound.wave(samples: stereo, channels: 2).write(to: output)
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
