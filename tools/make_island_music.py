#!/usr/bin/env python3
"""Generates the exploration music of the islands (assets/audio/music_<island>.wav).
Mono, 22050 Hz, 16 bit like the rest of the game's music. The loop is seamless (the game
restarts the stream when it finishes). Run: python3 tools/make_island_music.py"""
import wave
import numpy as np

SR = 22050


def env(n, a=0.01, d=0.2, s=0.6, r=0.15):
    t = np.arange(n) / SR
    e = np.ones(n)
    e = np.minimum(e, t / a) if a > 0 else e
    e *= s + (1 - s) * np.exp(-(t - a).clip(0) / d)
    tail = int(r * SR)
    if tail > 0 and n > tail:
        e[-tail:] *= np.linspace(1, 0, tail)
    return e


def note(freq, dur, kind="pad", vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "pad":
        w = sum(np.sin(2 * np.pi * freq * (1 + d) * t) * a for d, a in [(0, 1), (0.003, 0.6), (-0.003, 0.6), (1.0, 0.25)])
        return w * env(n, 0.35, 1.0, 0.8, 0.5) * 0.18 * vel
    if kind == "bell":
        w = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 2.76 * t) * np.exp(-t * 3) + 0.3 * np.sin(2 * np.pi * freq * 5.4 * t) * np.exp(-t * 6)
        return w * np.exp(-t * 1.6) * 0.22 * vel
    if kind == "bass":
        w = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(4 * np.pi * freq * t)
        return w * env(n, 0.01, 0.4, 0.5, 0.1) * 0.3 * vel
    if kind == "pluck":
        # Karplus-Strong: a guitar-like string
        period = int(SR / freq)
        buf = np.random.RandomState(int(freq)).uniform(-1, 1, period)
        out = np.zeros(n)
        for i in range(n):
            out[i] = buf[i % period]
            buf[i % period] = 0.4975 * (buf[i % period] + buf[(i + 1) % period])
        return out * 0.35 * vel
    if kind == "kick":
        f = 90 * np.exp(-t * 18) + 40
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.5 * vel
    if kind == "tick":
        rs = np.random.RandomState(3)
        return rs.uniform(-1, 1, n) * np.exp(-t * 60) * 0.12 * vel
    raise ValueError(kind)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def mix(total, events):
    out = np.zeros(int(total * SR) + SR)
    for start, wave_ in events:
        i = int(start * SR)
        out[i:i + len(wave_)] += wave_[: len(out) - i]
    out = out[: int(total * SR)]
    # fold the tail on the start so the loop has no click
    return out


def save(path, data):
    data = data / max(1e-9, np.abs(data).max()) * 0.8
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def syrup():
    """Villa Syrup: slow, mysterious, A minor, bells over pads."""
    bpm = 66
    beat = 60 / bpm
    bar = beat * 4
    chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62], [57, 60, 64], [53, 57, 60], [52, 56, 59], [57, 60, 64]]
    ev = []
    rs = np.random.RandomState(7)
    melody = [76, 74, 72, 69, 72, 74, 76, 79, 77, 76, 72, 69, 71, 72, 76, 72]
    for i, ch in enumerate(chords):
        t0 = i * bar
        for m in ch:
            ev.append((t0, note(midi(m), bar + 0.6, "pad")))
        ev.append((t0, note(midi(ch[0] - 12), beat * 2, "bass")))
        ev.append((t0 + beat * 2, note(midi(ch[0] - 12), beat * 2, "bass", 0.7)))
        for k in range(2):
            m = melody[(i * 2 + k) % len(melody)]
            ev.append((t0 + beat * (k * 2 + (0.5 if k else 0)), note(midi(m), 2.2, "bell", 0.9)))
        for k in range(8):
            ev.append((t0 + k * beat / 2, note(1, 0.1, "tick", 0.6 if k % 2 else 1.0)))
    total = len(chords) * bar
    save("assets/audio/music_villa_syrup.wav", mix(total, ev))


def whisky():
    """Whisky Peak: dry guitar in A Phrygian dominant over a steady beat (a desert western)."""
    bpm = 100
    beat = 60 / bpm
    bar = beat * 4
    scale = [57, 58, 61, 62, 64, 65, 67, 69]
    prog = [57, 57, 65, 64, 57, 57, 62, 64]
    riff = [(0, 0), (1, 2), (1.5, 3), (2, 4), (3, 2), (3.5, 1)]
    ev = []
    for i, root in enumerate(prog):
        t0 = i * bar
        ev.append((t0, note(midi(root - 24), beat * 1.5, "bass")))
        ev.append((t0 + beat * 2, note(midi(root - 24), beat * 1.5, "bass", 0.8)))
        for b, deg in riff:
            ev.append((t0 + b * beat, note(midi(scale[(deg + (i % 4)) % len(scale)] + 12), 1.2, "pluck", 0.9)))
        for b in (0, 1, 2, 3):
            ev.append((t0 + b * beat, note(midi(root - 12), 0.6, "pluck", 0.5)) if b % 2 == 0 else (t0 + b * beat, note(1, 0.1, "tick", 1.0)))
        ev.append((t0, note(1, 0.3, "kick")))
        ev.append((t0 + beat * 2, note(1, 0.3, "kick", 0.8)))
    total = len(prog) * bar
    save("assets/audio/music_whisky_peak.wav", mix(total, ev))


if __name__ == "__main__":
    syrup()
    whisky()
