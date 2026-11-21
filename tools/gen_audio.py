#!/usr/bin/env python3
"""用 numpy 合成全部配乐与音效，写到 audio/*.wav（16 位单声道）。
    python3 tools/gen_audio.py
配乐是五声音阶的拨弦旋律加鼓，音效是噪声与正弦的组合；没有用任何外部素材。"""
import numpy as np, wave, os

SR = 32000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def save(name, x, peak=0.89):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x))
    if m > 0:
        x = x / m * peak
    w = wave.open(os.path.join(OUT, name + ".wav"), "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype("<i2").tobytes())
    w.close()
    print("%-12s %5.2f 秒  均方根 %.3f" % (name, len(x) / SR, float(np.sqrt(np.mean(x * x)))))


def noise_band(dur, lo, hi, sweep=None):
    """带通噪声；sweep=(lo2, hi2) 时频带随时间滑动（分段拼接）。"""
    n = int(SR * dur)
    if sweep is None:
        spec = np.fft.rfft(rng.standard_normal(n))
        f = np.fft.rfftfreq(n, 1 / SR)
        spec *= np.exp(-0.5 * ((np.log(np.maximum(f, 1)) - np.log(np.sqrt(lo * hi))) / (np.log(hi / lo) / 2.0)) ** 2)
        return np.fft.irfft(spec, n)
    out = np.zeros(n)
    segs = 8
    L = n // segs
    win = np.hanning(2 * L)
    for i in range(segs + 1):
        k = i / segs
        seg = noise_band(2 * L / SR, lo + (sweep[0] - lo) * k, hi + (sweep[1] - hi) * k)[: 2 * L] * win
        a = i * L - L
        s0, s1 = max(a, 0), min(a + 2 * L, n)
        out[s0:s1] += seg[s0 - a: s1 - a]
    return out


def env(dur, a, d_rate):
    t = t_axis(dur)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t * d_rate)


def pluck(f, dur, bright=1.0):
    """拨弦（筝）：各次谐波按次数越高衰减越快，起音带一点下滑。"""
    t = t_axis(dur)
    bend = 1.0 + 0.012 * np.exp(-t * 30)
    ph = 2 * np.pi * f * np.cumsum(bend) / SR
    x = np.zeros_like(t)
    for k in range(1, 11):
        if f * k > SR * 0.45:
            break
        x += (bright ** (k - 1)) / k * np.sin(k * ph + 0.3 * k) * np.exp(-t * (1.1 + 0.55 * k))
    x[: int(SR * 0.004)] *= np.linspace(0, 1, int(SR * 0.004))
    return x


def reed(f, dur, vib=5.5, depth=0.006, bright=0.6):
    """长音（箫 / 唢呐）：带颤音，起音慢。"""
    t = t_axis(dur)
    ph = 2 * np.pi * f * t
    if vib > 0:
        ph = ph + depth * f / vib * np.sin(2 * np.pi * vib * t)
    x = np.sin(ph) + bright * 0.5 * np.sin(2 * ph) + bright * 0.33 * np.sin(3 * ph) + bright * 0.2 * np.sin(5 * ph)
    a = np.minimum(t / 0.07, 1.0) * np.minimum((dur - t) / 0.12, 1.0)
    return x * np.clip(a, 0, 1)


def drum(f0, dur, punch=1.0):
    t = t_axis(dur)
    f = f0 * (1.0 + 1.2 * np.exp(-t * 28))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7 / dur * 0.6)
    click = noise_band(dur, 300, 2500) * np.exp(-t * 90) * 0.5 * punch
    return x * np.exp(-t * 5) + click


def gong(f, dur):
    t = t_axis(dur)
    x = np.zeros_like(t)
    for r, a, d in [(1.0, 1.0, 1.2), (1.48, 0.6, 1.6), (2.07, 0.5, 2.0), (2.63, 0.35, 2.6), (3.41, 0.3, 3.2), (4.2, 0.2, 4.0)]:
        x += a * np.sin(2 * np.pi * f * r * t + r) * np.exp(-t * d)
    return x * np.minimum(t / 0.01, 1.0) + noise_band(dur, 1500, 6000) * np.exp(-t * 14) * 0.25


def reverb(x, size=0.9, mix=0.25, loop=False):
    n = int(SR * size)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5.5 / size)
    ir[: int(SR * 0.012)] = 0
    L = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)
    wet *= np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-9)
    if loop:      # 尾音绕回开头，循环处不断
        y = wet[: len(x)].copy()
        y[: n] += wet[len(x):]
        return x + mix * y
    out = np.zeros(L)
    out[: len(x)] = x
    return out + mix * wet


def put(buf, x, at, gain=1.0, loop=True):
    i = int(at * SR)
    n = len(buf)
    if loop:
        idx = (i + np.arange(len(x))) % n
        np.add.at(buf, idx, x * gain)
    else:
        e = min(n, i + len(x))
        buf[i:e] += x[: e - i] * gain


NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    return 440.0 * 2 ** ((NOTE[name[0]] + 12 * (int(name[-1]) - 4) - 9) / 12.0)


def parse(mel):
    return [(p.split(":")[0], float(p.split(":")[1])) for p in mel.split()]


# ───────────── 配乐 ─────────────

def music_map():
    beat = 60 / 66.0
    A1 = "E4:2 G4:1 A4:1  G4:2 E4:1 D4:1  C4:1 D4:1 E4:1 G4:1  D4:4"
    A2 = "E4:2 G4:1 A4:1  C5:2 A4:1 G4:1  E4:1 G4:1 D4:1 E4:1  C4:4"
    B = "A4:2 C5:2  D5:1 C5:1 A4:2  G4:1 A4:1 G4:1 E4:1  D4:3 E4:1"
    A3 = "E4:1 D4:1 C4:2  A3:2 C4:1 D4:1  E4:2 D4:2  C4:4"
    bars = 16
    buf = np.zeros(int(bars * 4 * beat * SR))
    pos = 0.0
    for sec, phrase in enumerate([A1, A2, B, A3]):
        for name, b in parse(phrase):
            put(buf, pluck(hz(name), min(3.2, b * beat + 1.6)), pos, 0.9)
            if b >= 2:      # 长音后面跟一个高八度的泛音点缀
                put(buf, pluck(hz(name) * 2, 1.4, 0.6), pos + beat * (b - 0.5), 0.22)
            if sec == 2:    # B 段加一支箫
                put(buf, reed(hz(name), b * beat * 0.96, bright=0.25), pos, 0.2)
            pos += b * beat
    roots = ["C2", "C2", "A2", "G2", "C2", "A2", "C2", "C2", "A2", "D3", "C2", "G2", "C2", "A2", "G2", "C2"]
    for bar, r in enumerate(roots):
        t0 = bar * 4 * beat
        f = hz(r) * (1 if r[-1] == "3" else 2)
        put(buf, pluck(f, 3.5, 0.8), t0, 0.5)
        put(buf, pluck(f * 1.5, 2.5, 0.8), t0 + 2 * beat, 0.32)
        if bar % 4 == 3:    # 句尾一串琶音
            for i, n in enumerate(["C4", "D4", "E4", "G4", "A4", "C5"]):
                put(buf, pluck(hz(n), 1.6, 0.7), t0 + 3 * beat + i * 0.11, 0.2)
    t = np.arange(len(buf)) / SR
    period = len(buf) / SR
    pad = (np.sin(2 * np.pi * hz("C3") * t) + 0.7 * np.sin(2 * np.pi * hz("G3") * t)) * (0.6 + 0.4 * np.sin(2 * np.pi * t / period * 4))
    buf = buf / np.max(np.abs(buf)) + 0.05 * pad
    save("music_map", reverb(buf, 1.6, 0.3, loop=True), 0.8)


def music_battle():
    beat = 60 / 132.0
    A = "A4:1 C5:1 D5:1 E5:1  E5:2 D5:1 C5:1  A4:1 C5:1 D5:1 C5:1  A4:4"
    B = "E5:1 G5:1 E5:1 D5:1  C5:2 D5:2  E5:1 D5:1 C5:1 A4:1  G4:2 A4:2"
    bars = 16
    buf = np.zeros(int(bars * 4 * beat * SR))
    big = drum(62, 0.7)
    small = drum(140, 0.25, 1.4)
    rim = noise_band(0.06, 1800, 5000) * np.exp(-t_axis(0.06) * 70)
    for bar in range(bars):
        t0 = bar * 4 * beat
        for b in [0, 1.5, 2, 3.5] if bar % 4 != 3 else [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.25, 3.5, 3.75]:
            put(buf, big, t0 + b * beat, 1.0)
        for e in range(8):
            put(buf, small, t0 + e * 0.5 * beat, 0.28 if e % 2 else 0.4)
        put(buf, rim, t0 + 1 * beat, 0.5)
        put(buf, rim, t0 + 3 * beat, 0.5)
        root = ["A2", "A2", "G2", "A2", "A2", "A2", "G2", "A2", "C3", "C3", "D3", "E3", "A2", "A2", "G2", "A2"][bar]
        for e in range(8):      # 低音弦的顿弓
            x = reed(hz(root), 0.5 * beat * 0.8, vib=0, depth=0, bright=1.0)
            put(buf, x, t0 + e * 0.5 * beat, 0.3 if e % 2 else 0.42)
    pos = 0.0
    for phrase in [A, A, B, A]:
        for name, b in parse(phrase):
            put(buf, reed(hz(name), b * beat * 0.94, vib=6.5, depth=0.008, bright=0.9), pos, 0.38)
            put(buf, pluck(hz(name), 1.2, 1.0), pos, 0.3)
            pos += b * beat
    save("music_battle", reverb(buf, 0.9, 0.18, loop=True), 0.82)


# ───────────── 音效 ─────────────

def sfx():
    d = 0.2
    save("swing", noise_band(d, 900, 2500, (2500, 7000)) * np.sin(np.pi * t_axis(d) / d) ** 2, 0.6)
    d = 0.34
    save("swing_heavy", noise_band(d, 400, 1500, (1800, 5000)) * np.sin(np.pi * t_axis(d) / d) ** 1.5, 0.75)
    d = 0.22
    t = t_axis(d)
    thud = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t * 16) + 50) / SR) * np.exp(-t * 20)
    save("hit", thud + 0.7 * noise_band(d, 500, 3500) * np.exp(-t * 45), 0.85)
    d = 0.55
    t = t_axis(d)
    cl = sum(a * np.sin(2 * np.pi * f * t + f) * np.exp(-t * dd) for f, a, dd in
             [(1180, 1.0, 9), (1873, 0.8, 11), (2954, 0.6, 14), (4120, 0.45, 18), (5630, 0.3, 24)])
    save("clang", reverb(cl + noise_band(d, 3000, 9000) * np.exp(-t * 80) * 0.6, 0.4, 0.2), 0.8)
    d = 0.3
    t = t_axis(d)
    save("bow", pluck(170, d, 0.9) * 0.9 + noise_band(d, 1500, 6000, (800, 3000)) * np.exp(-t * 14) * 0.5, 0.7)
    d = 0.5
    t = t_axis(d)
    save("die", np.sin(2 * np.pi * np.cumsum(85 * np.exp(-t * 9) + 38) / SR) * np.exp(-t * 9) + 0.35 * noise_band(d, 200, 1200) * np.exp(-t * 16), 0.8)
    d = 0.5
    t = t_axis(d)
    save("gate_hit", reverb(drum(55, d, 2.0) + 0.5 * noise_band(d, 150, 900) * np.exp(-t * 14), 0.5, 0.3), 0.9)
    d = 1.4
    t = t_axis(d)
    crash = noise_band(d, 120, 2500, (80, 900)) * np.exp(-t * 3.5) + drum(45, d, 2.0)
    for k in range(9):      # 木板断裂的噼啪
        put(crash, noise_band(0.05, 900, 5000) * np.exp(-t_axis(0.05) * 60), 0.05 + rng.random() * 0.8, 0.8, loop=False)
    save("gate_break", reverb(crash, 0.8, 0.3), 0.92)
    d = 0.09
    save("click", (np.sin(2 * np.pi * 950 * t_axis(d)) + 0.5 * np.sin(2 * np.pi * 1900 * t_axis(d))) * np.exp(-t_axis(d) * 70), 0.45)
    d = 2.0
    t = t_axis(d)
    horn = sum(np.sin(2 * np.pi * 110 * k * t * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))) / k ** 1.3 for k in range(1, 12))
    horn *= np.minimum(t / 0.35, 1.0) * np.minimum((d - t) / 0.5, 1.0) * (0.75 + 0.25 * np.minimum(t / 1.2, 1.0))
    save("horn", reverb(horn, 1.2, 0.35), 0.8)
    save("gong", reverb(gong(98, 3.2), 1.5, 0.35), 0.85)
    buf = np.zeros(int(SR * 2.6))
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        put(buf, pluck(hz(n), 1.6, 0.9), i * 0.16, 0.8, loop=False)
        put(buf, reed(hz(n), 0.3 if i < 3 else 1.1, bright=0.8), i * 0.16, 0.3, loop=False)
    put(buf, gong(196, 2.0), 0.5, 0.35, loop=False)
    save("victory", reverb(buf, 1.2, 0.3), 0.85)
    buf = np.zeros(int(SR * 2.6))
    for i, n in enumerate(["A3", "G3", "E3", "D3"]):
        put(buf, reed(hz(n), 0.75, vib=4.5, bright=0.5), i * 0.5, 0.6, loop=False)
    put(buf, drum(50, 1.0), 1.9, 0.9, loop=False)
    save("defeat", reverb(buf, 1.4, 0.35), 0.8)
    buf = np.zeros(int(SR * 0.9))
    put(buf, pluck(hz("E5"), 0.7, 0.9), 0.0, 0.8, loop=False)
    put(buf, pluck(hz("A5"), 0.8, 0.9), 0.11, 0.8, loop=False)
    save("loot", reverb(buf, 0.6, 0.25), 0.7)
    d = 0.16
    t = t_axis(d)
    save("gallop", np.sin(2 * np.pi * np.cumsum(120 * np.exp(-t * 30) + 60) / SR) * np.exp(-t * 35) + 0.5 * noise_band(d, 300, 1500) * np.exp(-t * 60), 0.5)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sfx()
    music_map()
    music_battle()
