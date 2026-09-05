import AVFoundation

/// Independent looping beds are crossfaded rather than restarted on every slider change.
/// AVAudioPlayer owns decoding; the UI timer only controls a slow gain envelope.
final class Ambience {
    private var players: [Weather: AVAudioPlayer] = [:]
    private var timer: Timer?
    private var targetWeather: Weather = .rain
    private var targetVolume: Float = 0
    private var failed = false
    var onError: ((String) -> Void)?

    func update(running: Bool, preferences: Preferences) {
        targetWeather = preferences.weather
        targetVolume = running && preferences.sound ? Float(preferences.volume) * 0.8 : 0
        guard targetVolume > 0 || !players.isEmpty else { return }
        if targetVolume > 0, players[targetWeather] == nil {
            do {
                let url = Assets.root.appendingPathComponent("Audio/\(targetWeather.rawValue).m4a")
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 0
                guard player.prepareToPlay() else { throw CocoaError(.fileReadCorruptFile) }
                players[targetWeather] = player
                failed = false
            } catch {
                if !failed { onError?("Ambient sound is unavailable. The weather can still run silently."); failed = true }
            }
        }
        if targetVolume > 0, let player = players[targetWeather], !player.isPlaying {
            if !player.play(), !failed { onError?("The sound output is unavailable. Check the Mac’s sound output, then toggle sound again."); failed = true }
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in self?.tick() }
        }
    }
    private func tick() {
        var fading = false
        for (weather, player) in players {
            let target: Float = weather == targetWeather ? targetVolume : 0
            let delta = target - player.volume
            if abs(delta) > 0.002 {
                player.volume += delta * 0.075
                fading = true
            } else {
                player.volume = target
                if target == 0 { player.pause() }
            }
        }
        if !fading { timer?.invalidate(); timer = nil }
    }
    func stopImmediately() {
        timer?.invalidate(); timer = nil
        players.values.forEach { $0.stop() }
        players.removeAll()
    }
}
