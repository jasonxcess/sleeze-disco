#!/usr/bin/env python3
"""Sleeze Disco — render the v7.6 TRACKS patterns to Ogg loops + UI blips.
Faithful to the web synth engine (PORT_SPEC.md §8.1):
  kick  tone(145 Hz, 0.16 s, sine, vol 0.6, slide to 42)
  bass  tone(pat.bass[i%8], beatDur*0.85, sawtooth, vol 0.16)
  lead  tone(pat.lead[i%8], beatDur*0.4, square, vol 0.06)
  master gain 0.45
Loops are 60 s: an integer number of beats at every track BPM
(100/110/120/130/140), so the loop seam lands exactly on a beat.
Blips are the web judgement/UI tones, rendered as WAV for Godot import.
Usage: python3 tools/render_tracks.py [--outdir assets/audio]
Requires: numpy, ffmpeg (Ogg encode).
"""
import argparse, math, os, subprocess, sys, wave
import numpy as np

SR = 44100

# Verbatim from web v7.6 TRACKS (PORT_SPEC.md §8).
TRACKS = {
    "myluva":     {"name": "MY LUVA",      "bpm": 100, "genre": "FUNK",
                   "bass": [55, 55, 65.41, 49, 55, 55, 82.41, 73.42],
                   "lead": [220, 261.63, 329.63, 392, 329.63, 261.63, 220, 196]},
    "bigscreen":  {"name": "BIG SCREEN",   "bpm": 110, "genre": "FUNK",
                   "bass": [55, 49, 55, 65.41, 55, 73.42, 55, 49],
                   "lead": [246.94, 220, 261.63, 293.66, 261.63, 220, 196, 220]},
    "dceased":    {"name": "DCEASED",      "bpm": 120, "genre": "HOUSE",
                   "bass": [55, 55, 55, 55, 65.41, 55, 49, 55],
                   "lead": [220, 220, 261.63, 220, 196, 220, 246.94, 220]},
    "foolmeonce": {"name": "FOOL ME ONCE", "bpm": 130, "genre": "HOUSE",
                   "bass": [58.27, 58.27, 51.91, 58.27, 65.41, 58.27, 49, 58.27],
                   "lead": [233.08, 220, 261.63, 233.08, 196, 220, 246.94, 233.08]},
    "shittalkin": {"name": "SHIT TALKIN",  "bpm": 140, "genre": "DARK DISCO",
                   "bass": [55, 49, 55, 65.41, 55, 49, 82.41, 73.42],
                   "lead": [220, 196, 220, 261.63, 220, 196, 174.61, 196]},
}

# Web judgement/UI tones (square unless noted, vol/Hz/dur from PORT_SPEC).
BLIPS = {
    "blip_perfect": (780.0, 780.0, 0.08, 0.15, "square"),
    "blip_good":    (420.0, 420.0, 0.08, 0.15, "square"),
    "blip_dance":   (660.0, 880.0, 0.08, 0.10, "square"),
    "blip_rush":    (880.0, 1320.0, 0.15, 0.18, "square"),
    "blip_notokens": (140.0, 140.0, 0.08, 0.15, "square"),
    "blip_counter": (780.0, 220.0, 0.08, 0.15, "square"),
}


def _tone(freq, dur, wave_type, vol, slide=None):
    n = max(1, int(SR * dur))
    t = np.arange(n) / SR
    if slide is not None:
        # exponential frequency ramp freq -> slide over dur
        f = freq * np.exp(np.log(slide / freq) * (t / dur))
        phase = 2 * math.pi * np.cumsum(f) / SR
    else:
        phase = 2 * math.pi * freq * t
    if wave_type == "sine":
        sig = np.sin(phase)
    elif wave_type == "square":
        sig = np.sign(np.sin(phase))
    elif wave_type == "sawtooth":
        # 8-harmonic sawtooth
        sig = np.zeros(n)
        for k in range(1, 9):
            sig += np.sin(k * phase) / k
        sig *= 2.0 / math.pi
    else:
        raise ValueError(wave_type)
    env = np.exp(np.log(0.001 / vol) * (t / dur)) if vol > 0 else np.zeros(n)
    return sig * env


def render_track(key, seconds=60):
    tr = TRACKS[key]
    bpm = tr["bpm"]
    beat = 60.0 / bpm
    n = int(SR * seconds)
    mix = np.zeros(n)
    beats = int(round(seconds / beat))
    for i in range(beats):
        start = int(i * beat * SR)
        # kick: 145 Hz sine, 0.16 s, vol 0.6, slide to 42
        k = _tone(145.0, 0.16, "sine", 0.6, slide=42.0)
        mix[start:start + len(k)] += k
        # bass: sawtooth, beatDur*0.85, vol 0.16
        b = _tone(tr["bass"][i % 8], beat * 0.85, "sawtooth", 0.16)
        mix[start:start + len(b)] += b
        # lead: square, beatDur*0.4, vol 0.06
        l = _tone(tr["lead"][i % 8], beat * 0.4, "square", 0.06)
        mix[start:start + len(l)] += l
    mix *= 0.45  # master gain
    peak = np.max(np.abs(mix))
    if peak > 0.95:
        mix *= 0.95 / peak
    return np.clip(mix, -1.0, 1.0)


def _write_wav(path, mono):
    stereo = np.stack([mono, mono], axis=1)
    pcm = (stereo * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def _encode_ogg(wav_path, ogg_path):
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", wav_path,
                    "-c:a", "libvorbis", "-b:a", "128k", "-ar", "44100",
                    ogg_path], check=True)
    os.remove(wav_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="assets/audio")
    ap.add_argument("--seconds", type=int, default=60)
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    for key, tr in TRACKS.items():
        mono = render_track(key, a.seconds)
        tmp = os.path.join(a.outdir, "bgm_%s.wav" % key)
        out = os.path.join(a.outdir, "bgm_%s.ogg" % key)
        _write_wav(tmp, mono)
        _encode_ogg(tmp, out)
        print("%s: %s %d BPM, %ds, %d KB, 128k Ogg"
              % (out, tr["name"], tr["bpm"], a.seconds, os.path.getsize(out) // 1024))
    for name, (f0, f1, dur, vol, wtype) in BLIPS.items():
        sig = _tone(f0, dur, wtype, vol, slide=f1 if f1 != f0 else None)
        out = os.path.join(a.outdir, name + ".wav")
        _write_wav(out, sig)
        print("%s: %.0f->%.0f Hz, %.2fs, %d KB"
              % (out, f0, f1, dur, os.path.getsize(out) // 1024))


if __name__ == "__main__":
    main()
