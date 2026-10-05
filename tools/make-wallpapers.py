#!/usr/bin/env python3
"""make-wallpapers.py [OUT_DIR] [--size WxH] [--only NAME…]

Renders the Praxis still wallpapers — original, procedural, deterministic
(fixed seeds), so anyone can regenerate them from this file. numpy + Pillow.
Film grain is added on purpose: it dithers the gradients so they don't band
on 8-bit screens. Two of them (oled-black, contours) are mostly true black,
which an OLED panel draws with its pixels off.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageFilter

W, H = 3840, 2160


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def ramp(stops, t):
    """Piecewise-linear colour ramp: stops = [(pos, '#hex'), …], t = array in 0..1."""
    t = np.clip(t, 0, 1)[..., None]
    pos = [p for p, _ in stops]
    cols = [hexrgb(c) for _, c in stops]
    out = np.zeros(t.shape[:-1] + (3,), np.float32)
    for i in range(len(stops) - 1):
        a, b = pos[i], pos[i + 1]
        m = (t[..., 0] >= a) & (t[..., 0] <= b)
        f = ((t - a) / max(b - a, 1e-6))
        seg = cols[i] * (1 - f) + cols[i + 1] * f
        out[m] = seg[m]
    out[t[..., 0] < pos[0]] = cols[0]
    out[t[..., 0] > pos[-1]] = cols[-1]
    return out


def noise(w, h, cell, rng):
    """Smooth value noise in 0..1: a random grid of `cell`-pixel cells, bicubic-upscaled
    in 32-bit float (an 8-bit grid would quantise into visible steps and streaks)."""
    gw, gh = max(2, w // cell + 2), max(2, h // cell + 2)
    g = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray(g, mode="F").resize((gw * cell, gh * cell), Image.BICUBIC)
    return np.clip(np.asarray(img, np.float32)[:h, :w], 0, 1)


def fbm(w, h, cell, rng, octaves=5, gain=0.5):
    total, amp, norm = np.zeros((h, w), np.float32), 1.0, 0.0
    for _ in range(octaves):
        total += amp * noise(w, h, max(2, int(cell)), rng)
        norm += amp
        amp *= gain
        cell /= 2
    return total / norm


def ridge1d(w, base, amp, cell, rng, octaves=5):
    """A 1-D skyline/ridge: y(x) in pixels."""
    n = fbm(w, 4, cell, rng, octaves)[1]
    return base + amp * (n - 0.5) * 2


def glow(img, cx, cy, r, color, strength=1.0):
    y, x = np.ogrid[:img.shape[0], :img.shape[1]]
    d2 = ((x - cx) ** 2 + (y - cy) ** 2) / (r * r)
    img += (np.exp(-d2) * strength)[..., None] * hexrgb(color)


def vignette(img, amount=0.35):
    y, x = np.ogrid[:img.shape[0], :img.shape[1]]
    d = np.sqrt(((x - img.shape[1] / 2) / (img.shape[1] / 2)) ** 2 + ((y - img.shape[0] / 2) / (img.shape[0] / 2)) ** 2) / math.sqrt(2)
    img *= (1 - amount * np.clip(d, 0, 1) ** 2)[..., None]


def finish(img, rng, grain=0.012):
    img = img + rng.normal(0, grain, img.shape[:2])[..., None].astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.0) * 255 + 0.5).astype(np.uint8))


def sky(h, w, stops):
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None] * np.ones((1, w), np.float32)
    return ramp(stops, t)


def layer_fill(img, ridge, color, soft=2.0):
    """Paint everything below ridge(x) with color (anti-aliased edge)."""
    y = np.arange(img.shape[0], dtype=np.float32)[:, None]
    a = np.clip((y - ridge[None, :]) / soft + 0.5, 0, 1)[..., None]
    img[:] = img * (1 - a) + hexrgb(color) * a if isinstance(color, str) else img * (1 - a) + color * a


# ── the wallpapers ───────────────────────────────────────────────────────────
def dusk_horizon(rng):
    img = sky(H, W, [(0, "#0b1026"), (0.38, "#2a1b4d"), (0.62, "#8e3f6e"), (0.74, "#e0795f"), (0.80, "#f5b26b")])
    glow(img, W * 0.68, H * 0.76, H * 0.22, "#ffc98a", 0.55)
    glow(img, W * 0.68, H * 0.76, H * 0.06, "#fff1d6", 0.8)
    for i, (base, amp, col) in enumerate([(0.74, 0.05, "#5a2a55"), (0.79, 0.06, "#3a1c42"), (0.86, 0.07, "#241430"), (0.94, 0.05, "#120a1c")]):
        layer_fill(img, ridge1d(W, H * base, H * amp, int(W * (0.24 - i * 0.04)), rng), col, 2.5)
    vignette(img, 0.25)
    return finish(img, rng)


def aurora_still(rng):
    img = sky(H, W, [(0, "#01030a"), (0.6, "#06142a"), (1, "#0b2238")])
    n = 2600                                                     # stars
    xs, ys = rng.integers(0, W, n), rng.integers(0, int(H * 0.85), n)
    stars = np.zeros((H, W), np.float32)
    stars[ys, xs] = rng.random(n) ** 3 * 1.4
    stars = np.asarray(Image.fromarray((np.clip(stars, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1)), np.float32) / 255 * 3
    img += stars[..., None] * hexrgb("#dfe8ff")
    y = np.arange(H, dtype=np.float32)[:, None]
    x = np.arange(W, dtype=np.float32)[None, :]
    for k, (yy, strength, tall) in enumerate([(0.50, 0.85, 0.26), (0.36, 0.35, 0.18)]):
        path = (H * yy + H * 0.05 * np.sin(x / W * math.tau * 0.7 + 2.1 * k)
                + (fbm(W, 4, W // 3, rng)[1][None, :] - 0.5) * H * 0.16)
        rays = fbm(W, 4, max(8, W // 160), rng, 3)[2][None, :] ** 2   # vertical curtain folds
        d = (path - y) / (H * tall)                                  # 0 at the lower edge, 1 near the top
        curtain = np.where(d > 0, np.exp(-d * 1.4), np.exp(-((y - path) / (H * 0.015)) ** 2))
        curtain *= 0.35 + 1.3 * rays
        col = ramp([(0, "#43ff9e"), (0.35, "#2fd6c2"), (0.75, "#5b7bff"), (1, "#b06bff")], np.clip(d, 0, 1))
        img += (curtain * strength)[..., None] * col * 0.7
    glow(img, W * 0.5, H * 0.95, H * 0.35, "#0f3b3a", 0.25)      # faint green on the horizon
    layer_fill(img, ridge1d(W, H * 0.86, H * 0.05, W // 8, rng), "#020306", 2.0)
    layer_fill(img, ridge1d(W, H * 0.93, H * 0.035, W // 13, rng), "#000000", 2.0)
    return finish(img, rng, 0.010)


def dunes(rng):
    img = sky(H, W, [(0, "#f3d9b1"), (0.35, "#f2b98a"), (0.55, "#ea9566")])
    glow(img, W * 0.25, H * 0.42, H * 0.25, "#fff2d8", 0.45)
    x = np.arange(W, dtype=np.float32)
    for i in range(6):
        base = H * (0.50 + i * 0.09)
        ridge = base + H * 0.05 * np.sin(x / W * math.tau * (0.6 + i * 0.25) + i * 1.3) + ridge1d(W, 0, H * 0.035, W // 3, rng)
        slope = np.gradient(ridge)
        lit = 0.5 + 0.5 * np.tanh(slope / (np.std(slope) * 1.5 + 1e-6))   # faces toward the sun are lighter
        top, bottom = ramp([(0, "#e3a06a"), (1, "#a65a35")], np.full(W, i / 6)), ramp([(0, "#c97f4f"), (1, "#5b2c1c")], np.full(W, i / 6))
        layer = np.zeros((H, W, 3), np.float32)
        yy = np.arange(H, dtype=np.float32)[:, None]
        depth = np.clip((yy - ridge[None, :]) / (H * 0.12), 0, 1)[..., None]
        shade = (lit[None, :, None] * 0.22 + 0.78)
        layer[:] = (top[None, :, :] * (1 - depth) + bottom[None, :, :] * depth) * shade
        a = np.clip((yy - ridge[None, :]) / 2 + 0.5, 0, 1)[..., None]
        img = img * (1 - a) + layer * a
    vignette(img, 0.2)
    return finish(img, rng)


def glacier(rng):
    img = np.zeros((H, W, 3), np.float32) + hexrgb("#08142a")
    for cx, cy, r, col, s in [(0.18, 0.25, 0.55, "#1d4e89", 0.9), (0.75, 0.2, 0.45, "#58c4dd", 0.55), (0.6, 0.75, 0.6, "#2a7ab0", 0.7),
                              (0.35, 0.65, 0.35, "#9bdcff", 0.35), (0.9, 0.85, 0.4, "#123766", 0.8)]:
        glow(img, W * cx, H * cy, H * r, col, s)
    warp = fbm(W, H, W // 6, rng, 4)
    img *= (0.85 + 0.3 * warp)[..., None]
    # a soft diagonal light streak
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    d = (x * 0.55 - y + H * 0.15) / (H * 0.18)
    img += (np.exp(-d * d) * 0.18)[..., None] * hexrgb("#d8f3ff")
    vignette(img, 0.3)
    return finish(img, rng)


def contours(rng):
    img = np.zeros((H, W, 3), np.float32) + hexrgb("#030507")
    hgt = fbm(W, H, W // 3, rng, 5)
    levels = hgt * 28
    frac = np.abs(levels - np.round(levels))
    # line width from the local gradient so lines stay ~1.4 px everywhere
    gy, gx = np.gradient(levels)
    lw = np.sqrt(gx * gx + gy * gy) * 1.8 + 1e-4
    line = np.clip(1 - frac / lw, 0, 1)
    major = (np.round(levels) % 5 == 0)
    col = np.where(major[..., None], hexrgb("#7dcfff"), hexrgb("#3d7fa8"))
    strength = np.where(major, 1.0, 0.6) * (0.6 + 0.9 * hgt)
    img += (line * strength)[..., None] * col
    glow(img, W * 0.72, H * 0.3, H * 0.5, "#0e3350", 0.35)
    vignette(img, 0.5)
    return finish(img, rng, 0.006)


def bloom(rng):
    img = sky(H, W, [(0, "#140a1f"), (1, "#1f0c2c")])
    for _ in range(46):
        cx, cy = rng.random() * W, rng.random() * H
        r = H * (0.03 + rng.random() ** 2 * 0.22)
        col = ["#ff6fb5", "#b47aff", "#6c8bff", "#ff9e7a", "#59d0ff"][rng.integers(0, 5)]
        glow(img, cx, cy, r, col, 0.08 + rng.random() * 0.22)
    vignette(img, 0.35)
    return finish(img, rng, 0.014)


def midnight_waves(rng):
    img = sky(H, W, [(0, "#040714"), (0.5, "#0b1a33"), (0.6, "#16375a")])
    glow(img, W * 0.78, H * 0.2, H * 0.045, "#f4f1e3", 0.95)
    glow(img, W * 0.78, H * 0.2, H * 0.28, "#3d6b9c", 0.22)
    x = np.arange(W, dtype=np.float32)
    y = np.arange(H, dtype=np.float32)[:, None]
    cols = ["#163757", "#11304d", "#0d2743", "#0a1f37", "#071629", "#040d1a"]
    path = np.exp(-((x[None, :] - W * 0.78) / (W * 0.09)) ** 2)       # the moon's path on the water
    for i, c in enumerate(cols):
        base = H * (0.60 + i * 0.07)
        ridge = (base + H * 0.0025 * (i + 1) * np.sin(x / W * math.tau * (9 + 3 * i) + i * 1.7)
                 + ridge1d(W, 0, H * 0.003 * (i + 1), W // 40, rng))           # long, low swells
        layer_fill(img, ridge, c, 1.4)
        sparkle = (fbm(W, 4, max(4, W // 300), rng, 2)[2] > 0.62)[None, :]      # broken, glittering crests
        glints = np.exp(-((y - ridge[None, :] - 3) / 3.5) ** 2) * path * sparkle * 0.45
        img += glints[..., None] * hexrgb("#c9def2")
    return finish(img, rng)


def oled_black(rng):
    img = np.zeros((H, W, 3), np.float32)
    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None]
    for k, (yy, col, s) in enumerate([(0.70, "#7aa2f7", 0.9), (0.73, "#bb9af7", 0.6)]):
        c = H * yy - H * 0.10 * np.sin((x / W) * math.pi * 1.1 + k * 0.4) * (x / W)
        d = (y - c) / (H * (0.006 + 0.002 * k))
        band = np.exp(-d * d) * s + np.exp(-((y - c) / (H * 0.07)) ** 2) * 0.10 * s
        fade = np.clip(np.sin(np.clip(x / W, 0, 1) * math.pi), 0, 1) ** 0.8
        img += (band * fade)[..., None] * hexrgb(col)
    return finish(img, rng, 0.004)


def misty_ridges(rng):
    img = sky(H, W, [(0, "#dfe9e4"), (0.5, "#cddbd2"), (1, "#b9cbbf")])
    glow(img, W * 0.3, H * 0.26, H * 0.22, "#fffdf2", 0.12)
    cols = ["#a8bdb0", "#8fa898", "#71907f", "#557664", "#3b5c4b", "#243f33", "#13261e"]
    for i, c in enumerate(cols):
        ridge = ridge1d(W, H * (0.40 + i * 0.075), H * (0.075 - i * 0.004), int(W * (0.36 - i * 0.04)), rng, 6)
        layer_fill(img, ridge, c, 2.0)
        if i < len(cols) - 1:   # fog pooling in the valley
            y = np.arange(H, dtype=np.float32)[:, None]
            fog = np.clip(1 - (y - ridge[None, :]) / (H * 0.08), 0, 1) * (y > ridge[None, :]) * 0.35
            img = img * (1 - fog[..., None]) + hexrgb("#e6efea") * fog[..., None]
    return finish(img, rng, 0.010)


def ember(rng):
    img = sky(H, W, [(0, "#050203"), (0.7, "#1a0806"), (1, "#3a0f08")])
    smoke = fbm(W, H, W // 5, rng, 5)
    img += (np.clip(smoke - 0.45, 0, 1) * 0.35)[..., None] * hexrgb("#6b1b0c") * np.linspace(0.2, 1, H, dtype=np.float32)[:, None, None]
    glow(img, W * 0.5, H * 1.05, H * 0.55, "#7a2310", 0.45)          # embers' glow from below
    for _ in range(220):
        cy = H * (0.30 + rng.random() ** 0.6 * 0.70)
        r = 3 + rng.random() ** 3 * 16
        glow(img, rng.random() * W, cy, r * 3, ["#ff8a3d", "#ffb347", "#ff5a2a"][rng.integers(0, 3)], 0.25 + rng.random() * 0.6)
    vignette(img, 0.4)
    return finish(img, rng, 0.010)


ALL = {
    "dusk-horizon": dusk_horizon, "aurora-still": aurora_still, "dunes": dunes, "glacier": glacier,
    "contours": contours, "bloom": bloom, "midnight-waves": midnight_waves, "oled-black": oled_black,
    "misty-ridges": misty_ridges, "ember": ember,
}

if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "desktop", "wallpapers")
    if "--size" in args:
        W, H = map(int, args[args.index("--size") + 1].split("x"))
    only = args[args.index("--only") + 1:] if "--only" in args else list(ALL)
    os.makedirs(out, exist_ok=True)
    for i, name in enumerate(ALL):
        if name not in only:
            continue
        img = ALL[name](np.random.default_rng(1000 + i))
        path = os.path.join(out, name + ".jpg")
        img.save(path, quality=90, subsampling=0, optimize=True, progressive=True)
        print(f"{name:16} {os.path.getsize(path) / 1e6:.1f} MB  {path}")
