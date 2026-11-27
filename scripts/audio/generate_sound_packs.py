#!/usr/bin/env python3
"""Generate the PerfectTap cosmetic sound packs (Quack Attack, Purrfect Tap, Boom Mode).

Everything here is ORIGINAL PROCEDURAL SYNTHESIS: oscillators, filtered noise and
envelopes computed from fixed seeds. No samples, recordings or downloaded audio are
used. The "duck" and "cat" sounds are synthesized approximations (formant-filtered
buzz), not animal recordings.

Pipeline per sound
  1. synthesize float samples at 44.1 kHz mono (deterministic: random.Random(seed))
  2. DC blocker, then peak-normalise to -3 dBFS through a soft (tanh-knee) limiter
  3. loudness-match to the pre-Studio default tone for the same event
     (metric: "phone-speaker weighted" short-term loudness, see `loudness_db`)
  4. soft-limit again to the event's ceiling (-3 dBFS, or -9 dBFS for the frequent
     tap/good/great sounds so 2-3 overlapping rapid taps never clip the mixer)
  5. raised-cosine fade-in (2 ms) / fade-out (10 ms) -> no clicks
  6. quantise to 16-bit, write WAV to a temp dir, convert with macOS `afconvert`
     to 16-bit little-endian linear PCM CAF (LEI16 @ 44100, mono)
  7. validate numerically (duration, peak, RMS, DC, NaN, clipping, onset) and
     write Resources/Sounds/audio_manifest.json

Usage:  python3 scripts/audio/generate_sound_packs.py [--check]
  --check  regenerate into a temp dir and verify the committed files are identical
           (proves reproducibility; exits 1 on any difference).

Stdlib only (wave, math, random, struct, json, hashlib, subprocess, tempfile).
"""

import hashlib
import json
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

SR = 44100
MASTER_SEED = 20261127
GENERATOR = "scripts/audio/generate_sound_packs.py"
SCRIPT_VERSION = 1

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO, "ios", "PerfectTap", "Resources", "Sounds")

TWO_PI = 2.0 * math.pi

# Duration limits per event (ms): (min, max). Validation fails outside these.
DURATION_LIMITS = {
    "tap": (70, 220), "good": (70, 220), "great": (70, 220),
    "perfect": (70, 400), "miss": (70, 300), "lifeLost": (70, 500), "gameOver": (70, 900),
}
# Events on the scored-tap path must start sounding immediately.
ONSET_CRITICAL = {"tap", "good", "great", "perfect", "miss", "lifeLost"}
# Peak ceilings (linear). Frequent events get extra headroom for overlap.
CEILING = {
    "tap": 0.35, "good": 0.35, "great": 0.35,
    "perfect": 0.708, "miss": 0.708, "lifeLost": 0.708, "gameOver": 0.708,
}
# Loudness target = default tone of this SoundType + offset (dB).
LOUDNESS_TARGET = {
    "tap": ("good", -1.0), "good": ("good", 0.0), "great": ("great", 0.0),
    "perfect": ("perfect", 0.0), "miss": ("miss", -1.0),
    "lifeLost": ("comboBreak", 0.0), "gameOver": ("comboBreak", 0.0),
}


# --------------------------------------------------------------------------- DSP

def n_samples(seconds):
    return int(round(seconds * SR))


def zeros(seconds):
    return [0.0] * n_samples(seconds)


def mix_into(dst, src, offset_s=0.0, gain=1.0):
    off = n_samples(offset_s)
    end = min(len(dst), off + len(src))
    for i in range(off, end):
        dst[i] += src[i - off] * gain
    return dst


class Biquad:
    """RBJ cookbook biquad (transposed direct form II). Coefficients can be
    retuned while running for sweeps."""

    def __init__(self):
        self.b0 = 1.0; self.b1 = self.b2 = self.a1 = self.a2 = 0.0
        self.z1 = self.z2 = 0.0

    def _set(self, b0, b1, b2, a0, a1, a2):
        self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
        self.a1, self.a2 = a1 / a0, a2 / a0

    def bandpass(self, f, q):  # constant 0 dB peak gain
        f = min(max(f, 20.0), SR * 0.45)
        w = TWO_PI * f / SR; al = math.sin(w) / (2 * q); c = math.cos(w)
        self._set(al, 0.0, -al, 1 + al, -2 * c, 1 - al)
        return self

    def lowpass(self, f, q=0.7071):
        f = min(max(f, 20.0), SR * 0.45)
        w = TWO_PI * f / SR; al = math.sin(w) / (2 * q); c = math.cos(w)
        self._set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
        return self

    def highpass(self, f, q=0.7071):
        f = min(max(f, 20.0), SR * 0.45)
        w = TWO_PI * f / SR; al = math.sin(w) / (2 * q); c = math.cos(w)
        self._set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
        return self

    def highshelf(self, f, gain_db, s=1.0):
        a = 10 ** (gain_db / 40); w = TWO_PI * f / SR; c = math.cos(w)
        al = math.sin(w) / 2 * math.sqrt((a + 1 / a) * (1 / s - 1) + 2)
        sq = 2 * math.sqrt(a) * al
        self._set(a * ((a + 1) + (a - 1) * c + sq), -2 * a * ((a - 1) + (a + 1) * c),
                  a * ((a + 1) + (a - 1) * c - sq), (a + 1) - (a - 1) * c + sq,
                  2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - sq)
        return self

    def tick(self, x):
        y = self.b0 * x + self.z1
        self.z1 = self.b1 * x - self.a1 * y + self.z2
        self.z2 = self.b2 * x - self.a2 * y
        return y


def filt(signal, kind, f, q=0.7071, f_end=None, step=16):
    """Run a (optionally exponentially swept) filter over `signal`."""
    bq = Biquad()
    out = [0.0] * len(signal)
    n = len(signal)
    for i in range(n):
        if i % step == 0:
            fc = f if f_end is None else f * (f_end / f) ** (i / max(1, n - 1))
            getattr(bq, kind)(fc, q)
        out[i] = bq.tick(signal[i])
    return out


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(seconds))]


def polyblep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def saw_pulse(freqs, pulse_mix=0.3, duty=0.3):
    """Band-limited (PolyBLEP) sawtooth + pulse following a per-sample frequency
    list. A nasal, buzzy source for the formant voices."""
    out = [0.0] * len(freqs)
    p = 0.0
    for i, f in enumerate(freqs):
        dt = f / SR
        saw = 2.0 * p - 1.0 - polyblep(p, dt)
        p2 = (p + 1.0 - duty) % 1.0
        saw2 = 2.0 * p2 - 1.0 - polyblep(p2, dt)
        pulse = saw - saw2  # difference of two saws = pulse wave
        out[i] = (1.0 - pulse_mix) * saw + pulse_mix * pulse
        p += dt
        if p >= 1.0:
            p -= 1.0
    return out


def sine_sweep(seconds, f_fn, phase=0.0):
    out = []
    for i in range(n_samples(seconds)):
        t = i / SR
        out.append(math.sin(phase))
        phase += TWO_PI * f_fn(t) / SR
    return out


def exp_env(seconds, attack, tau, release=0.0):
    """Linear attack, exponential decay, optional linear release at the end."""
    n = n_samples(seconds); out = [0.0] * n
    na = max(1, n_samples(attack)); nr = n_samples(release)
    for i in range(n):
        t = i / SR
        a = min(1.0, (i + 1) / na)
        d = math.exp(-max(0.0, t - attack) / tau)
        r = 1.0 if nr == 0 or i < n - nr else (n - i) / nr
        out[i] = a * d * r
    return out


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def scale(a, g):
    return [x * g for x in a]


def glide(t_frac, points):
    """Piecewise-linear interpolation over [(frac, value), ...]."""
    if t_frac <= points[0][0]:
        return points[0][1]
    for (f0, v0), (f1, v1) in zip(points, points[1:]):
        if t_frac <= f1:
            u = (t_frac - f0) / (f1 - f0) if f1 > f0 else 1.0
            return v0 + (v1 - v0) * u
    return points[-1][1]


def formant_voice(seconds, f0_fn, formants, rng, jitter=0.004, pulse_mix=0.3, body=0.12, step=16):
    """Buzz source -> parallel resonant band-passes.

    formants: list of (center_fn(t_frac), q, gain). Centers may glide (vowel morph).
    """
    n = n_samples(seconds)
    jit = 0.0
    freqs = []
    for i in range(n):
        t = i / SR
        if i % 64 == 0:  # slow random pitch jitter -> less synthetic
            jit = 0.85 * jit + 0.15 * rng.uniform(-1, 1)
        freqs.append(max(40.0, f0_fn(t) * (1.0 + jitter * jit)))
    src = saw_pulse(freqs, pulse_mix=pulse_mix)
    out = [0.0] * n
    for center_fn, q, gain in formants:
        bq = Biquad()
        for i in range(n):
            if i % step == 0:
                bq.bandpass(center_fn(i / max(1, n - 1)), q)
            out[i] += gain * bq.tick(src[i])
    if body:
        lp = filt(src, "lowpass", 900.0)
        for i in range(n):
            out[i] += body * lp[i]
    return out


# ------------------------------------------------------------- default tones
# Exact Python mirror of SoundEngine.soundConfigs (linear-decay tones, amp 0.18),
# used only as the loudness reference.

DEFAULT_TONES = {
    "perfect": [(880, "sine", 0.18, 0.0), (1100, "sine", 0.12, 0.06)],
    "great": [(660, "sine", 0.15, 0.0)],
    "good": [(440, "sine", 0.12, 0.0)],
    "miss": [(180, "sawtooth", 0.22, 0.0)],
    "comboBreak": [(220, "sawtooth", 0.15, 0.0), (150, "sawtooth", 0.2, 0.08)],
}


def default_tone(kind):
    tones = DEFAULT_TONES[kind]
    total = max(d + dl for _, _, d, dl in tones)
    out = zeros(total + 0.01)
    for f, wave_type, dur, delay in tones:
        buf = []
        for i in range(int(dur * SR)):
            t = i / SR
            env = max(0.0, 1.0 - t / dur)
            if wave_type == "sine":
                s = math.sin(TWO_PI * f * t)
            else:
                s = 2.0 * ((t * f) % 1.0) - 1.0
            buf.append(s * 0.18 * env)
        mix_into(out, buf, delay)
    return out


# ------------------------------------------------------------- analysis

def loudness_db(x):
    """Perceived short-term loudness estimate (dB) for matching packs to the
    default tones.

    Two playback paths matter: the iPhone speaker, which rolls off steeply below
    ~300 Hz (a sub-bass thump is nearly inaudible), and headphones, where the same
    thump is loud. Each path gets a weighting -- phone: 2nd-order high-pass 300 Hz;
    headphones: high-pass 60 Hz (BS.1770 "RLB"-like) -- both followed by a
    BS.1770-style +4 dB high shelf at 1.5 kHz. The two mean-square values are
    averaged, so neither path ends up drastically louder than the default tones.
    Value = max over 100 ms windows (10 ms hop). Absolute calibration is
    irrelevant: it is only compared against the same metric on the default tones.
    """
    def weighted_ms(hp_hz):
        hp = Biquad().highpass(hp_hz, 0.7071)
        hs = Biquad().highshelf(1500.0, 4.0)
        sq = [v * v for v in (hs.tick(hp.tick(s)) for s in x)]
        win = n_samples(0.1); hop = n_samples(0.01)
        if len(sq) <= win:
            return sum(sq) / win
        best = 0.0
        for start in range(0, len(sq) - win + 1, hop):
            best = max(best, sum(sq[start:start + win]))
        return best / win
    ms = 0.5 * (weighted_ms(300.0) + weighted_ms(60.0))
    return 10 * math.log10(max(ms, 1e-12))


def soft_limit(x, ceiling):
    """tanh knee from 50% of the ceiling: transparent below, never exceeds it."""
    knee = 0.5 * ceiling; span = ceiling - knee
    out = []
    for s in x:
        a = abs(s)
        if a > knee:
            a = knee + span * math.tanh((a - knee) / span)
        out.append(math.copysign(a, s))
    return out


def dc_block(x):
    """2nd-order high-pass at 35 Hz: removes DC and inaudible infrasound left by
    decaying low sines / 25 Hz amplitude modulation."""
    hp = Biquad().highpass(35.0, 0.7071)
    return [hp.tick(s) for s in x]


def fades(x, fade_in=0.0025, fade_out=0.010):
    n = len(x); ni = n_samples(fade_in); no = n_samples(fade_out)
    x = list(x)
    for i in range(min(ni, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * (i + 1) / ni)
    for i in range(min(no, n)):
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / no)
    return x


def peak(x):
    return max(abs(s) for s in x) if x else 0.0


def master(x, event, target_db):
    x = dc_block(x)
    p = peak(x) or 1.0
    x = soft_limit(scale(x, 1.0 / p), 0.708)          # peak-normalise to -3 dBFS
    ceiling = CEILING[event]
    for _ in range(4):                                # loudness match (limiter is nonlinear -> iterate)
        g = 10 ** ((target_db - loudness_db(x)) / 20)
        x = soft_limit(scale(x, g), ceiling)
    return fades(x)


def quantise(x):
    return [max(-32767, min(32767, int(round(s * 32767)))) for s in x]


def analyse(ints, event):
    n = len(ints)
    fl = [v / 32767.0 for v in ints]
    pk = max(abs(v) for v in fl)
    rms = math.sqrt(sum(v * v for v in fl) / n)
    dc = sum(fl) / n
    thresh = pk * 0.01  # -40 dB re peak
    onset = next(i for i, v in enumerate(fl) if abs(v) >= thresh)
    half = next(i for i, v in enumerate(fl) if abs(v) >= pk * 0.5)
    return {
        "durationMs": round(n * 1000.0 / SR, 1),
        "peakDbfs": round(20 * math.log10(pk), 2),
        "rmsDbfs": round(20 * math.log10(max(rms, 1e-9)), 2),
        "loudnessDb": round(loudness_db(fl), 2),
        "dcOffset": round(dc, 6),
        "onsetMs": round(onset * 1000.0 / SR, 2),
        "halfPeakMs": round(half * 1000.0 / SR, 2),
        "clippedSamples": sum(1 for v in ints if abs(v) >= 32767),
        "nan": any(v != v for v in fl),
    }


# ------------------------------------------------------------- Quack Attack

def quack(seconds, f_start, f_end, rng, bend_tau=0.04, rising=False, fshift=1.0,
          bright=1.0, dip=True, decay_tau=None):
    """Duck-like 'q-ack': nasal buzz, fast pitch bend, three formants where F1
    opens over the first ~25 ms (closed 'q' -> open 'ack')."""
    if rising:
        f0 = lambda t: f_start + (f_end - f_start) * (1 - math.exp(-t / bend_tau))
    else:
        f0 = lambda t: f_end + (f_start - f_end) * math.exp(-t / bend_tau)
    open_frac = min(0.3, 0.025 / seconds)
    formants = [
        (lambda u: fshift * glide(u, [(0, 560), (open_frac, 820), (1, 760)]), 4.0, 1.0),
        (lambda u: fshift * glide(u, [(0, 1350), (open_frac, 1520), (1, 1450)]), 6.0, 0.75 * bright),
        (lambda u: fshift * 2500, 8.0, 0.4 * bright),
    ]
    v = formant_voice(seconds, f0, formants, rng, pulse_mix=0.35)
    n = len(v)
    tau = decay_tau or seconds * 0.45
    for i in range(n):
        t = i / SR
        a = min(1.0, t / 0.002)
        if dip:  # the "q" -> "ack" amplitude notch
            a *= 1.0 - 0.35 * math.exp(-((t - 0.016) / 0.006) ** 2)
        a *= math.exp(-max(0.0, t - 0.03) / tau)
        v[i] *= a
    return v


def sparkle(seconds, rng, notes, start=0.0, spacing=0.06, tau=0.05, amp=0.3):
    out = zeros(seconds)
    for k, f in enumerate(notes):
        dur = min(seconds - start - k * spacing, 0.18)
        if dur <= 0.01:
            break
        f = f * (1 + rng.uniform(-0.004, 0.004))
        ping = mul(sine_sweep(dur, lambda t, f=f: f), exp_env(dur, 0.001, tau))
        ping2 = mul(sine_sweep(dur, lambda t, f=f: f * 2.76), exp_env(dur, 0.001, tau * 0.5))
        mix_into(out, [a + 0.25 * b for a, b in zip(ping, ping2)], start + k * spacing, amp)
    return out


def splash(seconds, rng):
    body = filt(noise(seconds, rng), "bandpass", 2600.0, 1.1, f_end=650.0)
    body = mul(body, exp_env(seconds, 0.002, 0.11))
    hiss = mul(filt(noise(seconds, rng), "highpass", 4500.0), exp_env(seconds, 0.001, 0.025))
    out = [1.6 * a + 0.5 * b for a, b in zip(body, hiss)]
    t = 0.05
    while t < seconds - 0.06:  # bubbles: rising sine blips (seeded timing)
        dur = rng.uniform(0.025, 0.045)
        f = rng.uniform(380, 700)
        blip = mul(sine_sweep(dur, lambda tt, f=f, d=dur: f * (1 + 1.4 * tt / d)), exp_env(dur, 0.002, dur * 0.4))
        mix_into(out, blip, t, rng.uniform(0.25, 0.45))
        t += rng.uniform(0.035, 0.07)
    return out


def quack_pack(rng_for):
    s = {}
    vari = [(1.0, 1.0), (1.03, 1.02), (0.97, 0.985)]
    s[("tap", 1)] = quack(0.09, 290, 220, rng_for("qa.tap"), bend_tau=0.03)
    for k, (p, f) in enumerate(vari, 1):
        r = rng_for("qa.good.%d" % k)
        s[("good", k)] = scale(filt(quack(0.12, 260 * p, 210 * p, r, fshift=f, bright=0.6), "lowpass", 3200), 1.0)
        r = rng_for("qa.great.%d" % k)
        s[("great", k)] = quack(0.15, 240 * p, 330 * p, r, rising=True, bend_tau=0.05, fshift=f, bright=1.1)
    r = rng_for("qa.perfect")
    out = zeros(0.38)
    mix_into(out, quack(0.11, 260, 340, r, rising=True, bend_tau=0.04, bright=1.1), 0.0)
    mix_into(out, quack(0.12, 300, 390, r, rising=True, bend_tau=0.04, bright=1.15), 0.12)
    mix_into(out, sparkle(0.38, r, [2637, 3136, 3520, 4186], start=0.05, spacing=0.07), 0.0, 0.8)
    s[("perfect", 1)] = out
    s[("miss", 1)] = filt(quack(0.24, 190, 130, rng_for("qa.miss"), bend_tau=0.08, fshift=0.9,
                                bright=0.45, decay_tau=0.09), "lowpass", 2200)
    s[("lifeLost", 1)] = splash(0.48, rng_for("qa.lifeLost"))
    r = rng_for("qa.gameOver")
    out = zeros(0.88)
    notes = [(0.0, 0.17, 310, 280), (0.19, 0.17, 270, 240), (0.38, 0.17, 235, 205)]
    for start, dur, a, b in notes:
        mix_into(out, quack(dur, a, b, r, bend_tau=0.06, decay_tau=0.12), start)
    # final drooping "wah" with vibrato and a slow formant close
    dur = 0.30
    vib = lambda t: (200 - 60 * t / dur) * (1 + 0.03 * math.sin(TWO_PI * 6 * t))
    formants = [(lambda u: glide(u, [(0, 820), (1, 520)]), 4.0, 1.0),
                (lambda u: glide(u, [(0, 1500), (1, 1100)]), 6.0, 0.6),
                (lambda u: 2400.0, 8.0, 0.3)]
    last = formant_voice(dur, vib, formants, r, pulse_mix=0.35)
    last = mul(last, exp_env(dur, 0.01, 0.2, release=0.08))
    mix_into(out, last, 0.57)
    s[("gameOver", 1)] = out
    return s


# ------------------------------------------------------------- Purrfect Tap

def boop(seconds, f_hi, f_lo, tau, rng):
    f = lambda t: f_lo + (f_hi - f_lo) * math.exp(-t / tau)
    a = sine_sweep(seconds, f)
    b = sine_sweep(seconds, lambda t: 2 * f(t))
    env = exp_env(seconds, 0.002, seconds * 0.35)
    return [(x + 0.15 * y) * e for x, y, e in zip(a, b, env)]


def pop(seconds, f_hi, f_lo, rng):
    body = boop(seconds, f_hi, f_lo, 0.008, rng)
    click = mul(filt(noise(seconds, rng), "bandpass", 3000.0, 1.0), exp_env(seconds, 0.0005, 0.0015))
    return [a + 0.6 * b for a, b in zip(body, click)]


def purr(seconds, rng, rate=25.0, buzz_hz=140.0, level_fn=None):
    """Purr: band-limited buzz + filtered noise, amplitude-modulated at ~25 Hz.
    AM starts at its peak phase so the sound has no onset delay. The buzz sits at
    ~140 Hz with harmonics up to ~1.6 kHz so it is audible on a phone speaker
    (a true ~25-50 Hz purr fundamental would be inaudible there)."""
    n = n_samples(seconds)
    buzz = filt(saw_pulse([buzz_hz] * n, pulse_mix=0.2), "lowpass", 1600.0)
    buzz = filt(buzz, "highpass", 180.0)
    nz = filt(noise(seconds, rng), "bandpass", 900.0, 0.8)
    out = []
    for i in range(n):
        t = i / SR
        am = (0.55 + 0.45 * math.cos(TWO_PI * rate * t)) ** 1.5
        lvl = level_fn(t) if level_fn else 1.0
        out.append((0.6 * buzz[i] + 0.9 * nz[i]) * am * lvl)
    return out


def meow(seconds, rng, f0_points, vowels, attack=0.012, release=0.06, bright=1.0):
    """Cat-like 'meow': pitch arc + formant glide i -> a -> u (synthesized
    approximation, not a recording)."""
    f0 = lambda t: glide(t / seconds, f0_points)
    formants = [
        (lambda u: glide(u, [(p, v[0]) for p, v in vowels]), 6.0, 1.0),
        (lambda u: glide(u, [(p, v[1]) for p, v in vowels]), 8.0, 0.7 * bright),
        (lambda u: glide(u, [(p, v[2]) for p, v in vowels]), 10.0, 0.35 * bright),
    ]
    v = formant_voice(seconds, f0, formants, rng, jitter=0.006, pulse_mix=0.25, body=0.08)
    n = len(v); na = n_samples(attack); nr = n_samples(release)
    for i in range(n):
        a = min(1.0, (i + 1) / max(1, na))
        if i > n - nr:
            a *= (n - i) / nr
        v[i] *= a
    return v


VOWEL_I = (320, 2300, 3000)
VOWEL_A = (850, 1300, 2700)
VOWEL_U = (380, 850, 2400)


def chime(seconds, rng, notes, spacing=0.06, amp=0.5):
    return sparkle(seconds, rng, notes, start=0.0, spacing=spacing, tau=0.12, amp=amp)


def purr_pack(rng_for):
    s = {}
    vari = [1.0, 1.03, 0.97]
    s[("tap", 1)] = boop(0.09, 760, 480, 0.025, rng_for("pt.tap"))
    for k, p in enumerate(vari, 1):
        s[("good", k)] = pop(0.09, 1100 * p, 350 * p, rng_for("pt.good.%d" % k))
        r = rng_for("pt.great.%d" % k)
        g = purr(0.20, r, rate=25.0 * p, buzz_hz=140.0 * p,
                 level_fn=lambda t: min(1.0, 0.75 + t / 0.04) * math.exp(-max(0, t - 0.08) / 0.08))
        s[("great", k)] = g
    r = rng_for("pt.perfect")
    out = zeros(0.38)
    mix_into(out, chime(0.38, r, [1568, 2349, 3136], spacing=0.07, amp=0.55), 0.0)
    m = meow(0.33, r, [(0, 520), (0.35, 760), (1, 470)], [(0, VOWEL_I), (0.4, VOWEL_A), (1, VOWEL_U)])
    mix_into(out, m, 0.03, 0.9)
    s[("perfect", 1)] = out
    m = meow(0.22, rng_for("pt.miss"), [(0, 430), (1, 320)], [(0, VOWEL_A), (1, VOWEL_U)],
             attack=0.002, release=0.07, bright=0.5)
    s[("miss", 1)] = filt(m, "lowpass", 2000)
    r = rng_for("pt.lifeLost")
    puff = filt(noise(0.36, r), "lowpass", 1800.0, 0.7, f_end=250.0)
    s[("lifeLost", 1)] = mul(puff, exp_env(0.36, 0.006, 0.09))
    r = rng_for("pt.gameOver")
    out = zeros(0.85)
    mix_into(out, purr(0.34, r, rate=24.0, buzz_hz=125.0,
                       level_fn=lambda t: math.exp(-t / 0.25)), 0.0, 0.8)
    m = meow(0.55, r, [(0, 560), (0.25, 600), (1, 290)], [(0, VOWEL_A), (0.5, VOWEL_A), (1, VOWEL_U)],
             attack=0.03, release=0.15, bright=0.8)
    mix_into(out, m, 0.26)
    s[("gameOver", 1)] = out
    return s


# ------------------------------------------------------------- Boom Mode

def click(seconds, rng, hp=2000.0, tau=0.0015):
    return mul(filt(noise(seconds, rng), "highpass", hp), exp_env(seconds, 0.0003, tau))


def thump(seconds, f_hi, f_lo, tau_f, tau_a):
    f = lambda t: f_lo + (f_hi - f_lo) * math.exp(-t / tau_f)
    return mul(sine_sweep(seconds, f), exp_env(seconds, 0.001, tau_a))


def crackle(seconds, rng, rate0=600.0, rate1=50.0, hp=2500.0):
    n = n_samples(seconds); imp = [0.0] * n
    for i in range(n):
        t = i / n
        rate = rate0 * (rate1 / rate0) ** t
        if rng.random() < rate / SR:
            amp = rng.uniform(0.4, 1.0) * (1 - 0.6 * t)
            for k in range(min(6, n - i)):
                imp[i + k] += amp * rng.uniform(-1, 1)
    return filt(imp, "highpass", hp)


def explosion(seconds, rng, tau=0.14, sub_tau=0.16, lp_end=180.0, rumble=0.0):
    burst = filt(noise(seconds, rng), "lowpass", 6000.0, 0.8, f_end=lp_end)
    burst = mul(burst, exp_env(seconds, 0.002, tau))
    sub = thump(seconds, 80, 40, 0.08, sub_tau)
    mid = thump(seconds, 200, 80, 0.04, 0.07)
    out = [1.3 * a + 0.5 * b + 0.8 * c for a, b, c in zip(burst, sub, mid)]
    if rumble:
        rum = mul(filt(noise(seconds, rng), "lowpass", 320.0), exp_env(seconds, 0.05, rumble))
        out = [a + 1.4 * b for a, b in zip(out, rum)]
    return out


def boom_pack(rng_for):
    s = {}
    vari = [1.0, 1.03, 0.97]
    r = rng_for("bm.tap")
    s[("tap", 1)] = [a + 0.8 * b + 0.35 * c for a, b, c in zip(
        click(0.08, r, hp=1500.0, tau=0.002), thump(0.08, 1600, 1500, 1, 0.012),
        thump(0.08, 320, 200, 0.02, 0.02))]
    for k, p in enumerate(vari, 1):
        r = rng_for("bm.good.%d" % k)
        s[("good", k)] = [0.6 * a + b + 0.35 * c for a, b, c in zip(
            click(0.07, r, hp=3000.0, tau=0.001), thump(0.07, 3000 * p, 3000 * p, 1, 0.006),
            thump(0.07, 4200 * p, 4200 * p, 1, 0.004))]
        r = rng_for("bm.great.%d" % k)
        burst = mul(filt(noise(0.17, r), "bandpass", 6000.0 * p, 1.2), exp_env(0.17, 0.001, 0.02))
        s[("great", k)] = [a + 0.9 * b for a, b in zip(crackle(0.17, r, hp=2500.0 * p), burst)]
    r = rng_for("bm.perfect")
    d = 0.34
    tail = mul(filt(noise(d, r), "lowpass", 1200.0), exp_env(d, 0.002, 0.06))
    s[("perfect", 1)] = [0.9 * a + b + 0.45 * c + 0.8 * e for a, b, c, e in zip(
        click(d, r, hp=2500.0, tau=0.003), thump(d, 260, 130, 0.03, 0.05),
        thump(d, 90, 50, 0.05, 0.09), tail)]
    r = rng_for("bm.miss")
    d = 0.28
    fizz = filt(noise(d, r), "lowpass", 7000.0, 0.9, f_end=350.0)
    env = [min(1.0, (i + 1) / n_samples(0.004)) * (1 - i / n_samples(d)) ** 1.6 for i in range(n_samples(d))]
    s[("miss", 1)] = [a * e + 0.3 * c for a, e, c in zip(fizz, env, crackle(d, r, 300.0, 30.0, 3000.0))]
    s[("lifeLost", 1)] = explosion(0.48, rng_for("bm.lifeLost"))
    r = rng_for("bm.gameOver")
    out = zeros(0.85)
    mix_into(out, click(0.85, r, hp=1500.0, tau=0.003), 0.0, 0.8)
    mix_into(out, explosion(0.85, r, tau=0.2, sub_tau=0.25, lp_end=120.0, rumble=0.3), 0.0)
    s[("gameOver", 1)] = out
    return s


# ------------------------------------------------------------- packs / IO

PACKS = [
    ("quack_attack", "Quack Attack", quack_pack),
    ("purrfect_tap", "Purrfect Tap", purr_pack),
    ("boom_mode", "Boom Mode", boom_pack),
]
# rng names used inside each builder start with this prefix ("qa.good.2", ...).
SEED_PREFIX = {"quack_attack": "qa", "purrfect_tap": "pt", "boom_mode": "bm"}

# Sound-design confidence. Animal-like formant voices are rough approximations
# and need an owner listen (and probably a sound designer) before release.
NEEDS_DESIGNER = {
    ("quack_attack", "tap"), ("quack_attack", "good"), ("quack_attack", "great"),
    ("quack_attack", "perfect"), ("quack_attack", "miss"), ("quack_attack", "gameOver"),
    ("purrfect_tap", "great"), ("purrfect_tap", "perfect"), ("purrfect_tap", "miss"),
    ("purrfect_tap", "gameOver"),
}


def seed_for(name):
    # Deterministic, platform-independent (no hash randomisation).
    return MASTER_SEED + sum((i + 1) * ord(c) for i, c in enumerate(name))


def write_wav(path, ints):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(struct.pack("<%dh" % len(ints), *ints))


def afconvert(wav_path, caf_path):
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", wav_path, caf_path],
                   check=True)


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def generate(out_dir):
    targets = {k: loudness_db(default_tone(k)) for k in DEFAULT_TONES}
    entries = []
    failures = []
    tmp = tempfile.mkdtemp(prefix="pt-audio-")
    try:
        for pack_id, pack_name, builder in PACKS:
            seeds = {}

            def rng_for(name, seeds=seeds):
                seeds[name] = seed_for(name)
                return random.Random(seeds[name])

            sounds = builder(rng_for)
            pack_dir = os.path.join(out_dir, pack_id)
            os.makedirs(pack_dir, exist_ok=True)
            for (event, variant), raw in sorted(sounds.items()):
                ref, offset = LOUDNESS_TARGET[event]
                x = master(raw, event, targets[ref] + offset)
                ints = quantise(x)
                multi = sum(1 for (e, _) in sounds if e == event) > 1
                stem = "%s_%s%s" % (pack_id, event, "_v%d" % variant if multi else "")
                wav_path = os.path.join(tmp, stem + ".wav")
                caf_rel = "%s/%s.caf" % (pack_id, stem)
                caf_path = os.path.join(out_dir, caf_rel)
                write_wav(wav_path, ints)
                afconvert(wav_path, caf_path)
                st = analyse(ints, event)
                lo, hi = DURATION_LIMITS[event]
                problems = []
                if not (lo <= st["durationMs"] <= hi):
                    problems.append("duration %.1f ms outside %d-%d" % (st["durationMs"], lo, hi))
                if st["nan"]:
                    problems.append("NaN")
                if st["clippedSamples"]:
                    problems.append("%d clipped samples" % st["clippedSamples"])
                if abs(st["dcOffset"]) > 0.002:
                    problems.append("DC offset %.4f" % st["dcOffset"])
                if st["peakDbfs"] > 20 * math.log10(CEILING[event]) + 0.05:
                    problems.append("peak above ceiling")
                if event in ONSET_CRITICAL and st["onsetMs"] > 2.0:
                    problems.append("onset %.2f ms > 2 ms" % st["onsetMs"])
                if problems:
                    failures.append("%s: %s" % (stem, "; ".join(problems)))
                name_key = "%s.%s%s" % (SEED_PREFIX[pack_id], event, ".%d" % variant if multi else "")
                entries.append({
                    "id": stem,
                    "pack": pack_id,
                    "packName": pack_name,
                    "event": event,
                    "variant": variant,
                    "file": "Resources/Sounds/" + caf_rel,
                    "format": "CAF, linear PCM 16-bit little-endian, 44100 Hz, mono",
                    "bytes": os.path.getsize(caf_path),
                    "sha256": sha256(caf_path),
                    "seed": seeds.get(name_key),
                    "loudnessTargetDb": round(targets[ref] + offset, 2),
                    "loudnessRef": "default.%s%+.0f dB" % (ref, offset),
                    **{k: v for k, v in st.items() if k != "nan"},
                    "origin": "original procedural synthesis, %s (v%d), seed %s"
                              % (GENERATOR, SCRIPT_VERSION, seeds.get(name_key)),
                    "rights": "original work created for and owned by the PerfectTap project; "
                              "no third-party samples; commercial use permitted",
                    "status": "provisional-needs-sound-designer" if (pack_id, event) in NEEDS_DESIGNER
                              else "provisional-pending-owner-listen",
                })
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    manifest = {
        "generator": GENERATOR,
        "generatorVersion": SCRIPT_VERSION,
        "masterSeed": MASTER_SEED,
        "sampleRate": SR,
        "note": "Synthesized approximations, not animal recordings. Regenerate with "
                "`python3 %s`; `--check` verifies byte-identical output." % GENERATOR,
        "defaultToneLoudnessDb": {k: round(v, 2) for k, v in targets.items()},
        "totalBytes": sum(e["bytes"] for e in entries),
        "sounds": entries,
    }
    with open(os.path.join(out_dir, "audio_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
    return manifest, failures


def print_table(manifest):
    cols = ["id", "durationMs", "peakDbfs", "rmsDbfs", "loudnessDb", "loudnessTargetDb",
            "dcOffset", "onsetMs", "halfPeakMs", "clippedSamples", "bytes"]
    widths = [30, 8, 8, 8, 8, 8, 9, 7, 8, 5, 7]
    hdr = ["id", "dur ms", "peak dB", "rms dB", "loud", "target", "dc", "onset", "half pk", "clip", "bytes"]
    print("  ".join(h.ljust(w) for h, w in zip(hdr, widths)))
    for e in manifest["sounds"]:
        print("  ".join(str(e[c]).ljust(w) for c, w in zip(cols, widths)))
    print("total bytes: %d (%.1f KB) in %d files" % (manifest["totalBytes"], manifest["totalBytes"] / 1024,
                                                     len(manifest["sounds"])))


def main():
    check = "--check" in sys.argv
    if check:
        tmp_out = tempfile.mkdtemp(prefix="pt-audio-check-")
        try:
            manifest, failures = generate(tmp_out)
            diffs = []
            for e in manifest["sounds"]:
                committed = os.path.join(REPO, "ios", "PerfectTap", e["file"])
                if not os.path.exists(committed) or sha256(committed) != e["sha256"]:
                    diffs.append(e["file"])
            with open(os.path.join(tmp_out, "audio_manifest.json")) as a, \
                    open(os.path.join(OUT_DIR, "audio_manifest.json")) as b:
                if a.read() != b.read():
                    diffs.append("audio_manifest.json")
        finally:
            shutil.rmtree(tmp_out, ignore_errors=True)
        print_table(manifest)
        if failures or diffs:
            print("FAIL", failures, diffs)
            sys.exit(1)
        print("OK: regenerated output is byte-identical to the committed files")
        return
    manifest, failures = generate(OUT_DIR)
    print_table(manifest)
    if failures:
        print("VALIDATION FAILED:")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print("validation OK")


if __name__ == "__main__":
    main()
