#!/usr/bin/env python3
"""Sleeze Disco — synth BGM generator (placeholder tracks, NOT the game score).
Renders a 30 s loop at the given BPM: kick on every beat, snare on 2 & 4,
hats on 8ths, and a simple Am bassline. Writes 44.1 kHz 16-bit stereo WAV,
then encodes to Ogg Vorbis 128 kbps (the Vita budget: 44.1 kHz, 96-128 kbps).
Usage: python3 tools/make_bgm.py --bpm 120 --out assets/audio/bgm_dive_bar.ogg
Requires: numpy, ffmpeg (for the Ogg encode).
Swap these files for real mixed stems before shipping.
"""
import argparse, math, os, subprocess, sys
import numpy as np

SR = 44100

def kick(t):
    # Sine drop 150 -> 45 Hz, 0.14 s, exponential decay.
    f = 150.0 * np.exp(-t * 28.0) + 45.0
    phase = 2 * math.pi * np.cumsum(f) / SR
    env = np.exp(-t * 32.0)
    return np.sin(phase) * env

def snare(t):
    noise = np.random.randn(len(t)) * np.exp(-t * 22.0) * 0.5
    tone = np.sin(2 * math.pi * 180.0 * t) * np.exp(-t * 30.0) * 0.4
    return noise + tone

def hat(t):
    noise = np.random.randn(len(t))
    # crude high-pass: differentiate
    hp = np.diff(noise, prepend=0.0)
    return hp * np.exp(-t * 90.0) * 0.35

def bass_note(freq, dur):
    t = np.arange(int(SR * dur)) / SR
    # sine + 2nd harmonic, soft attack
    sig = np.sin(2 * math.pi * freq * t) + 0.4 * np.sin(2 * math.pi * freq * 2 * t)
    env = np.minimum(1.0, t * 40.0) * np.exp(-t * 2.0)
    return sig * env * 0.5

def render(bpm, seconds=30):
    n = int(SR * seconds)
    mix = np.zeros(n)
    beat = 60.0 / bpm
    roots = [55.0, 55.0, 65.41, 49.0]  # A1 A1 C2 G1, one per bar
    bar = beat * 4
    # kicks on beats, snare 2 & 4, hats 8ths
    for i in range(int(seconds / beat) + 1):
        start = int(i * beat * SR)
        klen = int(0.16 * SR)
        if start + klen <= n:
            mix[start:start + klen] += kick(np.arange(klen) / SR) * 0.9
        if i % 2 == 1:  # snare on 2 & 4
            slen = int(0.2 * SR)
            if start + slen <= n:
                mix[start:start + slen] += snare(np.arange(slen) / SR) * 0.6
        for h in range(2):  # hats on 8ths
            hs = start + int(h * beat * SR / 2)
            hlen = int(0.04 * SR)
            if hs + hlen <= n:
                mix[hs:hs + hlen] += hat(np.arange(hlen) / SR) * (0.7 if h == 0 else 0.45)
    # bass: one root per bar, quarter notes
    for b in range(int(seconds / bar) + 1):
        root = roots[b % len(roots)]
        for q in range(4):
            s = int((b * bar + q * beat) * SR)
            note = bass_note(root, beat * 0.95)
            if s + len(note) <= n:
                mix[s:s + len(note)] += note
    # gentle limiter
    peak = np.max(np.abs(mix))
    if peak > 0.95:
        mix *= 0.95 / peak
    return np.clip(mix, -1.0, 1.0)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bpm", type=float, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seconds", type=int, default=30)
    a = ap.parse_args()
    np.random.seed(7)
    mono = render(a.bpm, a.seconds)
    stereo = np.stack([mono, mono], axis=1)
    pcm = (stereo * 32767).astype(np.int16)
    tmp = a.out + ".tmp.wav"
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    import wave
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp,
                    "-c:a", "libvorbis", "-b:a", "128k", "-ar", "44100", a.out],
                   check=True)
    os.remove(tmp)
    print(f"{a.out}: {a.bpm} BPM, {a.seconds}s, {os.path.getsize(a.out)//1024} KB, 128k Ogg")

if __name__ == "__main__":
    main()
