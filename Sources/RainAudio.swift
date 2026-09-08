import Foundation
import AVFoundation

/// Original quiet wet-rubber strokes, following the blade's travel and reversal.
enum WiperSound {
    static func samples() -> [Float] {
        let count = Int(WiperMotion.duration * Float(RainTapSound.sampleRate))
        var result = [Float](repeating: 0, count: count * 2)
        var state: UInt64 = 39271
        var low: Float = 0, slow: Float = 0
        for i in 0..<count {
            let t = Float(i) / Float(RainTapSound.sampleRate)
            let returning = t > WiperMotion.outward + WiperMotion.turn
            let phase = returning ? (t - WiperMotion.outward - WiperMotion.turn) / (WiperMotion.duration - WiperMotion.outward - WiperMotion.turn) : t / WiperMotion.outward
            guard phase >= 0 && phase <= 1 else { continue }
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float((state >> 40) & 0xffffff) / Float(0x800000) - 1
            low += (noise - low) * 0.19; slow += (noise - slow) * 0.022
            let velocity = pow(max(0, sin(phase * .pi)), 0.85)
            let value = ((low - slow) * 0.86 + sin(t * 2 * .pi * 92) * 0.022) * velocity * (returning ? 0.86 : 1)
            let pan = (returning ? 1 : -1) * cos(phase * .pi) * 0.55
            result[i * 2] = value * sqrt((1 - pan) * 0.5)
            result[i * 2 + 1] = value * sqrt((1 + pan) * 0.5)
        }
        let peak = max(0.001, result.map(abs).max() ?? 1)
        result = result.map { $0 * 0.18 / peak }
        result[0] = 0; result[1] = 0; result[count * 2 - 2] = 0; result[count * 2 - 1] = 0
        return result
    }
}

/// Original short, damped water-on-glass sounds; no microphone or audio engine.
enum RainTapSound {
    static let sampleRate = 44100
    static let variants = 16

    static func variant(for contact: RainContact) -> Int {
        min(variants - 1, max(0, Int(contact.seed * Float(variants))))
    }
    static func gain(for contact: RainContact) -> Float { 0.22 + min(1, contact.radius / 8) * 0.22 }

    static func samples(variant: Int) -> [Float] {
        var state = UInt64(701 + variant * 137)
        func random() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 40) & 0xffffff) / Float(0x1000000)
        }
        let frequency = 620 + random() * 1050
        var previous: Float = 0
        var result = [Float](repeating: 0, count: sampleRate / 10)
        for i in result.indices {
            let t = Float(i) / Float(sampleRate)
            previous += ((random() * 2 - 1) - previous) * 0.42
            let attack = 1 - exp(-t * 1900)
            let pulse = previous * 0.75 * exp(-t * 220)
                + sin(2 * .pi * frequency * t) * 0.33 * exp(-t * 110)
                + sin(2 * .pi * frequency * 0.56 * t) * 0.12 * exp(-t * 75)
            let tail = min(1, Float(result.count - 1 - i) / 180)
            result[i] = pulse * attack * tail
        }
        let peak = result.map(abs).max() ?? 1
        return result.map { $0 * (0.38 / max(peak, 0.001)) }
    }

    static func wave(samples: [Float], channels: Int = 1) -> Data {
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: "RIFF".utf8); word(bytes + 36)
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(channels))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * channels * 2)); word(UInt16(channels * 2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(bytes)
        for sample in samples { word(Int16(min(1, max(-1, sample)) * 32767)) }
        return data
    }
}

final class RainTapPlayer {
    private var voices: [[AVAudioPlayer]] = []
    private(set) var playedContacts = 0

    init() throws {
        // Two voices per timbre allow overlap without cutting a preceding tap off.
        for variant in 0..<RainTapSound.variants {
            let data = RainTapSound.wave(samples: RainTapSound.samples(variant: variant))
            let pair = try (0..<2).map { _ -> AVAudioPlayer in
                let player = try AVAudioPlayer(data: data)
                guard player.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
                return player
            }
            voices.append(pair)
        }
    }

    func play(_ contacts: [RainContact], gain: Float) {
        guard gain > 0.001 else { return }
        for contact in contacts {
            guard let voice = voices[RainTapSound.variant(for: contact)].first(where: { !$0.isPlaying }) else { continue }
            voice.currentTime = 0
            voice.pan = contact.pan
            voice.volume = min(0.8, gain) * RainTapSound.gain(for: contact)
            if voice.play() { playedContacts += 1 }
        }
    }

    func stop() { voices.flatMap { $0 }.forEach { $0.stop() } }
}
