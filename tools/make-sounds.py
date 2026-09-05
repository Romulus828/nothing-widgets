#!/usr/bin/env python3
"""Generate sounds/timer.wav: three short, clean beeps in the Nothing idiom.
Standard library only, so the file can be regenerated anywhere. Run from the
repository root."""

import math
import struct
import wave

RATE = 44100
FREQ = 1760.0            # A6, bright but not shrill
BEEP = 0.09              # seconds per beep
GAP = 0.11
COUNT = 3
GAIN = 0.35


def tone(seconds, freq):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        # sine with a touch of third harmonic for edge, short attack/decay
        env = min(1.0, i / (RATE * 0.005)) * min(1.0, (n - i) / (RATE * 0.02))
        v = math.sin(2 * math.pi * freq * t) * 0.85 + math.sin(2 * math.pi * freq * 3 * t) * 0.15
        out.append(v * env * GAIN)
    return out


samples = []
for k in range(COUNT):
    samples += tone(BEEP, FREQ)
    if k < COUNT - 1:
        samples += [0.0] * int(RATE * GAP)
samples += [0.0] * int(RATE * 0.05)

with wave.open("sounds/timer.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
print("wrote sounds/timer.wav", len(samples) / RATE, "s")
