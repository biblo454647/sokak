#!/usr/bin/env python3
"""Author original, periodic stereo ambience. Requires numpy and ffmpeg at build time."""
from pathlib import Path
import subprocess
import tempfile
import wave
import argparse
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR, SECONDS = 44100, 48
N = SR * SECONDS
RNG = np.random.default_rng(41034)
FREQ = np.fft.rfftfreq(N, 1 / SR)
TIME = np.arange(N) / SR

def bed(slope, cutoff, floor=40):
    spectrum = np.fft.rfft(RNG.normal(size=N))
    shaping = np.maximum(FREQ, floor) ** (-slope / 2)
    shaping *= 1 / np.sqrt(1 + (FREQ / cutoff) ** 6)
    shaping *= FREQ / np.maximum(FREQ + 22, 1)
    signal = np.fft.irfft(spectrum * shaping, n=N)
    return signal / np.std(signal)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=['rain', 'snow', 'mist'])
    selected = parser.parse_args().only
    destination = ROOT / 'Resources' / 'Audio'
    destination.mkdir(parents=True, exist_ok=True)
    for name, slope, cutoff, loudness in [('rain', .55, 3900, -25), ('snow', 1.45, 1600, -29), ('mist', 1.7, 1100, -29)]:
        if selected and name != selected:
            continue
        common = bed(slope, cutoff)
        channels = []
        for channel in range(2):
            noise = .76 * common + .24 * bed(slope, cutoff)
            phase = channel * .19
            # Every LFO completes an integer number of cycles in the loop.
            gust = 1 + .09 * np.sin(2 * np.pi * TIME / SECONDS * 3 + phase) + .055 * np.sin(2 * np.pi * TIME / SECONDS * 7 + .8)
            noise *= gust
            if name == 'rain':
                # Random, quiet impacts diffuse across the continuous rainfall bed.
                for _ in range(3300):
                    start = RNG.integers(N)
                    length = RNG.integers(160, 2100)
                    t = np.arange(length) / SR
                    envelope = np.exp(-t * RNG.uniform(65, 190)) * (1 - np.exp(-t * 1600))
                    grain = RNG.normal(size=length) * envelope * RNG.uniform(.08, .55)
                    noise[(start + np.arange(length)) % N] += grain
                # Muted exterior rain with sparse, close taps against a window pane.
                # Very short damped modes avoid a tonal loop or startling knocks.
                for _ in range(135):
                    start = RNG.integers(N)
                    t = np.arange(int(SR * .075)) / SR
                    attack = 1 - np.exp(-t * 2500)
                    mode = RNG.uniform(900, 2350)
                    tap = (np.sin(2 * np.pi * mode * t) * np.exp(-t * 115)
                           + .24 * np.sin(2 * np.pi * mode * 1.73 * t) * np.exp(-t * 190)
                           + RNG.normal(size=len(t)) * .24 * np.exp(-t * 280))
                    noise[(start + np.arange(len(t))) % N] += tap * attack * RNG.uniform(.3, 1.1)
            channels.append(noise)
        signal = np.stack(channels, axis=1)
        signal = signal / max(1, np.max(np.abs(signal))) * .7
        # Long crossfade around the seam preserves a continuous periodic boundary.
        seam = SR * 2
        overlap = signal[:seam] * np.linspace(0, 1, seam)[:, None] + signal[-seam:] * np.linspace(1, 0, seam)[:, None]
        signal = np.concatenate([overlap, signal[seam:-seam]], axis=0)
        with tempfile.TemporaryDirectory(prefix='sokak-audio-') as temp:
            wav = Path(temp) / 'bed.wav'
            with wave.open(str(wav), 'wb') as file:
                file.setnchannels(2); file.setsampwidth(2); file.setframerate(SR)
                file.writeframes((signal * 32767).astype('<i2').tobytes())
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(wav), '-af', f'loudnorm=I={loudness}:TP=-9:LRA=5', '-ar', str(SR), '-c:a', 'aac', '-b:a', '160k', '-metadata', 'artist=Sokak', '-metadata', f'title={name.capitalize()} — original synthesized ambience', str(destination / (name + '.m4a'))], check=True)
        print(f'{name}: original stereo ambience, {len(signal)/SR:.0f}s, target {loudness} LUFS', flush=True)

if __name__ == '__main__': main()
