#!/usr/bin/env python3
"""Render Praxis's live wallpapers: procedural, seamless video loops.

    python tools/live-wallpapers.py [OUT_DIR] [--only NAME ...] [--seconds 16] [--preview]

Every moving thing completes a whole number of cycles per loop, so the last
frame flows straight into the first and mpv can loop the file with no seam.
Output is 1920x1080 H.264 (decoded in hardware by any GPU). --preview writes
one PNG per scene instead of a video. Needs numpy and ffmpeg.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import time

import numpy as np

FPS = 30
OUT_W, OUT_H = 1920, 1080
TAU = float(2 * np.pi)


def lin(hex_color: str) -> np.ndarray:
    """'#rrggbb' -> linear-ish RGB (gamma 2), so glows add up the way light does."""
    h = hex_color.lstrip("#")
    return np.array([(int(h[i:i + 2], 16) / 255) ** 2 for i in (0, 2, 4)], dtype=np.float32)


def blob(acc, cx, cy, r, soft, color, alpha, rim=0.0):
    """Add a soft-edged disc to acc, touching only its bounding box.
    rim > 0 brightens the edge the way out-of-focus (bokeh) highlights look."""
    H, W, _ = acc.shape
    reach = r + 5 * soft
    x0, x1 = max(0, int(cx - reach)), min(W, int(cx + reach) + 2)
    y0, y1 = max(0, int(cy - reach)), min(H, int(cy + reach) + 2)
    if x0 >= x1 or y0 >= y1:
        return
    dx = np.arange(x0, x1, dtype=np.float32) - np.float32(cx)
    dy = np.arange(y0, y1, dtype=np.float32)[:, None] - np.float32(cy)
    d = np.sqrt(dx * dx + dy * dy)
    disc = 0.5 - 0.5 * np.tanh((d - r) / (2 * soft))
    if rim:
        disc = disc * (1 - rim + rim * np.clip(d / r, 0, 1) ** 3)
    acc[y0:y1, x0:x1] += (disc * alpha)[..., None] * color


class Stars:
    """A static star field in a few groups that twinkle out of phase."""

    def __init__(self, rng, W, H, count, y_max, tint="#e2e8f0", groups=4, scale=1.0):
        self.layers, self.twinkle = [], []
        for _ in range(groups):
            layer = np.zeros((H, W, 3), np.float32)
            for _ in range(count // groups):
                bright = rng.uniform(0.15, 1.0) ** 2
                blob(layer, rng.uniform(0, W), rng.uniform(0, y_max), rng.uniform(0.35, 0.9) * scale,
                     0.45 * scale, lin(tint), bright * 1.4)
            self.layers.append(layer)
            self.twinkle.append((int(rng.integers(1, 4)), rng.uniform(0, TAU)))

    def add(self, acc, t):
        for layer, (m, p) in zip(self.layers, self.twinkle):
            acc += layer * np.float32(0.55 + 0.45 * np.sin(TAU * m * t + p))


class Nebula:
    """Deep purple: out-of-focus lights drifting at different depths."""
    size, crf = (960, 540), 20

    def __init__(self):
        W, H = self.size
        rng = np.random.default_rng(11)
        y = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
        x = np.linspace(0, 1, W, dtype=np.float32)[None, :, None]
        self.bg = (lin("#06030d") * (1 - y) + lin("#170b2e") * y
                   + lin("#5b21b6") * 0.30 * np.exp(-((x - 0.15) ** 2 / 0.10 + (y - 0.95) ** 2 / 0.07))
                   + lin("#1e40af") * 0.20 * np.exp(-((x - 0.88) ** 2 / 0.07 + (y - 0.08) ** 2 / 0.05)))
        self.stars = Stars(rng, W, H, 140, H, tint="#ede9fe")
        palette = ["#7c3aed", "#a855f7", "#c084fc", "#6366f1", "#db2777", "#22d3ee"]
        weights = [0.24, 0.22, 0.14, 0.20, 0.12, 0.08]
        s = W / 960
        self.orbs = []
        for _ in range(34):
            depth = rng.uniform(0, 1) ** 1.4                    # 0 = far away, 1 = right in front
            self.orbs.append(dict(
                x=rng.uniform(-0.05, 1.05) * W, y=rng.uniform(-0.05, 1.05) * H,
                r=(4 + 64 * depth) * s, soft=(0.7 + 15 * depth ** 2) * s,
                a=0.85 - 0.62 * depth, col=lin(palette[rng.choice(len(palette), p=weights)]),
                # nearer lights sway further: that difference is the parallax (3D) cue
                ax=(0.006 + 0.05 * depth) * W, ay=(0.006 + 0.035 * depth) * H,
                kx=int(rng.integers(1, 3)), ky=int(rng.integers(1, 3)),
                px=rng.uniform(0, TAU), py=rng.uniform(0, TAU),
                km=int(rng.integers(1, 4)), pm=rng.uniform(0, TAU), depth=depth))
        self.orbs.sort(key=lambda o: o["depth"])

    def frame(self, t):
        acc = self.bg.copy()
        self.stars.add(acc, t)
        for o in self.orbs:
            blob(acc,
                 o["x"] + o["ax"] * np.sin(TAU * o["kx"] * t + o["px"]),
                 o["y"] + o["ay"] * np.sin(TAU * o["ky"] * t + o["py"]),
                 o["r"], o["soft"], o["col"],
                 o["a"] * (0.8 + 0.2 * np.sin(TAU * o["km"] * t + o["pm"])), rim=0.35)
        return acc


def ridge(rng, W, base, amp, octaves=6):
    """A mountain skyline (pixel row per column) from layered sines."""
    x = np.linspace(0, 1, W)
    y = np.zeros(W)
    for o in range(octaves):
        y += amp / (1.9 ** o) * np.sin(TAU * (2 ** o) * rng.uniform(1.2, 2.2) * x + rng.uniform(0, TAU))
    return (base + y).astype(np.float32)


def with_pines(rng, line, count, h_min, h_max):
    """Stand pine-tree silhouettes (narrow triangles) along a skyline."""
    W = line.shape[0]
    top = line.copy()
    xs = np.arange(W, dtype=np.float32)
    for _ in range(count):
        xt, h = rng.uniform(0, W), rng.uniform(h_min, h_max)
        w = h * rng.uniform(0.20, 0.28)
        lo, hi = max(0, int(xt - w)), min(W, int(xt + w) + 1)
        if lo < hi:
            tip = line[min(W - 1, int(xt))] - h * (1 - np.abs(xs[lo:hi] - xt) / w)
            top[lo:hi] = np.minimum(top[lo:hi], tip)
    return top


class Aurora:
    """Forest night: aurora curtains rippling over a mountain ridge and a pine forest."""
    size, crf = (960, 540), 20

    def __init__(self):
        W, H = self.size
        rng = np.random.default_rng(5)
        self.H = H
        self.y = np.arange(H, dtype=np.float32)[:, None]
        self.xn = np.linspace(0, 1, W, dtype=np.float32)[None, :]
        yn = (self.y / H)[..., None]
        far = ridge(rng, W, 0.80 * H, 0.06 * H, octaves=4)[None, :]
        near = with_pines(rng, ridge(rng, W, 0.92 * H, 0.035 * H, octaves=4), 190, 0.014 * H, 0.042 * H)[None, :]
        # night sky, with a faint green airglow just above the mountains
        self.bg = np.broadcast_to(lin("#010302") * (1 - yn) + lin("#0a1d1a") * yn, (H, W, 3)).copy()
        self.bg += lin("#10b981") * 0.10 * np.exp(-np.maximum(far - self.y, 0) / (0.10 * H))[..., None]
        self.stars = Stars(rng, W, H, 260, 0.8 * H)
        self.far_mask = (self.y > far)[..., None]
        self.near_mask = (self.y > near)[..., None]
        # the far ridge catches a little of the aurora's light along its crest
        self.far_img = lin("#091815") + lin("#2f8f73") * 0.22 * np.exp(-np.maximum(self.y - far, 0) / (0.006 * H))[..., None]
        self.near_img = np.broadcast_to(lin("#010403"), (H, W, 3))
        self.curtains = []
        for base, height, strength, lo, hi in ((0.48, 0.30, 1.00, "#34d399", "#8b5cf6"),
                                               (0.30, 0.20, 0.55, "#10b981", "#6366f1")):
            self.curtains.append(dict(
                base=base * H, height=height * H, s=strength, lo=lin(lo), hi=lin(hi),
                waves=[(rng.uniform(0.5, 1.1) * (k + 1), int(rng.choice([-1, 1])) * (k + 1),
                        rng.uniform(0, TAU), 0.08 * H / (k + 1)) for k in range(3)],
                env=(rng.uniform(0.6, 1.2), rng.uniform(0, TAU)),
                rays=[(rng.uniform(18, 40), int(rng.choice([-2, -1, 1, 2])), rng.uniform(0, TAU)) for _ in range(2)]))

    def frame(self, t):
        acc = self.bg.copy()
        self.stars.add(acc, t)
        edge = 0.012 * self.H
        for c in self.curtains:
            yb = c["base"] + sum(a * np.sin(TAU * (k * self.xn + m * t) + p) for k, m, p, a in c["waves"])
            dy = yb - self.y                                    # > 0 above the curtain's lower edge
            up = np.maximum(dy, 0)
            # long glow fading upward, a bright fold along the lower edge, a crisp cut-off below it
            shape = np.where(dy >= 0, np.exp(-up / c["height"]) * (0.65 + 0.7 * np.exp(-up / (0.015 * self.H))),
                             np.exp(-(np.minimum(dy, 0) / edge) ** 2))
            k, p = c["env"]
            env = 0.06 + 0.94 * (0.5 + 0.5 * np.sin(TAU * (k * self.xn + t) + p)) ** 3   # ribbons, not bands
            for kr, mr, pr in c["rays"]:
                env = env * (0.55 + 0.45 * (0.5 + 0.5 * np.sin(TAU * (kr * self.xn + mr * t) + pr)) ** 2)
            mix = np.clip(dy / (c["height"] * 1.4), 0, 1)[..., None]
            acc += (shape * env * c["s"])[..., None] * (c["lo"] * (1 - mix) + c["hi"] * mix)
        acc = np.where(self.far_mask, self.far_img, acc)
        return np.where(self.near_mask, self.near_img, acc)


class Horizon:
    """Charcoal blue: a light grid gliding toward you under a rising planet."""
    size, crf = (1920, 1080), 23
    SX, SZ, CELLS_PER_LOOP = 0.30, 0.40, 8

    def __init__(self):
        W, H = self.size
        rng = np.random.default_rng(3)
        self.hy = hy = int(0.52 * H)
        self.f = 0.6 * W
        yy = np.arange(H, dtype=np.float32)[:, None]
        xx = np.arange(W, dtype=np.float32)[None, :]
        yn = (yy / hy)[..., None]
        sky = (lin("#04060d") * (1 - yn) + lin("#14213f") * yn
               + lin("#2563eb") * 0.35 * np.exp(-((yy - hy) / (0.07 * H)) ** 2)[..., None])
        sky = np.broadcast_to(sky, (H, W, 3)).copy()
        # a lit sphere half-risen over the horizon
        pcx, pcy, pr = 0.70 * W, hy - 0.02 * H, 0.23 * H
        nx, ny = (xx - pcx) / pr, (yy - pcy) / pr
        d = np.sqrt(nx ** 2 + ny ** 2)
        nz = np.sqrt(np.clip(1 - d ** 2, 0, 1))
        light = np.array([-0.62, -0.42, 0.66], np.float32)
        light /= np.linalg.norm(light)
        lam = np.clip(nx * light[0] + ny * light[1] + nz * light[2], 0, 1)
        bands = 1 + 0.10 * np.sin(ny * 21) + 0.05 * np.sin(ny * 53 + 1.3)
        body = lin("#070d1f") + lin("#3b82f6") * 0.55 * (lam ** 1.6 * bands)[..., None]
        inside = (0.5 - 0.5 * np.tanh((d - 1) * pr / 1.2))[..., None]
        halo = np.exp(-np.maximum(d - 1, 0) * pr / (0.03 * H)) * (d > 0.98) * (0.25 + 0.75 * np.clip(-nx - ny, 0, 1))
        self.sky = sky * (1 - inside) + inside * body + halo[..., None] * lin("#60a5fa") * 0.35
        self.stars = Stars(rng, W, hy, 320, hy, scale=1.6)
        for layer in self.stars.layers:                         # no stars in front of the planet
            layer *= 1 - inside[:hy]
        # ground geometry (camera height 1): row v below the horizon sees depth z = f / v
        v = np.arange(1, H - hy + 1, dtype=np.float32)[:, None]
        self.v = v
        self.z = self.f / v
        wx = (xx - W / 2) / v                                   # world X (camera height = 1)
        self.cx = wx / self.SX                                  # ... in grid cells
        # lines toward the sides lean over, so they sit closer together than their
        # horizontal spacing suggests: measure (and fade) them perpendicular to the line
        self.px_x = self.SX * v / np.sqrt(1 + wx * wx)
        self.fade_x = self._smooth(6, 28, self.px_x)            # hide converging lines before they moire
        self.fade_z = self._smooth(4, 18, self.SZ * v * v / self.f)
        self.fog = np.exp(-self.z / 18)
        near_far = np.clip(self.z / 16, 0, 1)[..., None]
        self.line_col = lin("#38bdf8") * (1 - near_far) + lin("#6366f1") * near_far
        self.ground = lin("#02040a") + lin("#2563eb") * 0.42 * np.exp(-v / 30)[..., None]

    @staticmethod
    def _smooth(e0, e1, x):
        s = np.clip((x - e0) / (e1 - e0), 0, 1)
        return s * s * (3 - 2 * s)

    @staticmethod
    def _lines(dist_px, width=1.4):
        # exact pixel coverage of a `width`-px line (a box filter: no shimmer or moire as it
        # slides across pixel centres), plus a soft glow
        core = np.clip(np.minimum(dist_px + 0.5, width / 2) - np.maximum(dist_px - 0.5, -width / 2), 0, 1)
        return core + 0.28 * np.exp(-(dist_px / 4.0) ** 2)

    def frame(self, t):
        acc = self.sky.copy()
        self.stars.add(acc[:self.hy], t)
        cz = (self.z + self.CELLS_PER_LOOP * self.SZ * t) / self.SZ   # depth in cells, scrolling toward us
        dx = np.abs((self.cx + 0.5) % 1 - 0.5) * self.px_x                   # px to the nearest X line
        dz = np.abs((cz + 0.5) % 1 - 0.5) * self.SZ * self.v * self.v / self.f
        grid = np.maximum(self._lines(dx) * self.fade_x, self._lines(dz) * self.fade_z) * self.fog
        acc[self.hy:] = self.ground + grid[..., None] * self.line_col * 0.9
        return acc


SCENES = {"nebula": Nebula, "aurora": Aurora, "horizon": Horizon}


def finish(acc, noise):
    """Tone-map (soft highlight roll-off), back to display gamma, dither, 8-bit."""
    out = np.sqrt(1.0 - np.exp(-acc * 1.3)) * 255.0 + noise
    return np.clip(out, 0, 255).astype(np.uint8)


def render(name, scene, out_dir, seconds, preview):
    W, H = scene.size
    noise = np.random.default_rng(1).uniform(-0.5, 0.5, (H, W, 1)).astype(np.float32)
    if preview:
        path = out_dir / f"{name}.png"
        img = finish(scene.frame(0.0), noise)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                        "-i", "-", "-vf", f"scale={OUT_W}:{OUT_H}:flags=lanczos", "-frames:v", "1", str(path)],
                       input=img.tobytes(), check=True)
        return path
    path = out_dir / f"{name}.mp4"
    frames = seconds * FPS
    scale = [] if (W, H) == (OUT_W, OUT_H) else ["-vf", f"scale={OUT_W}:{OUT_H}:flags=lanczos"]
    ff = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
         "-i", "-", *scale, "-c:v", "libx264", "-preset", "slow", "-crf", str(scene.crf),
         "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.1", "-g", str(FPS * 2),
         "-movflags", "+faststart", "-an", str(path)], stdin=subprocess.PIPE)
    for i in range(frames):
        ff.stdin.write(finish(scene.frame(i / frames), noise).tobytes())
    ff.stdin.close()
    if ff.wait():
        sys.exit(f"ffmpeg failed for {name}")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("out_dir", nargs="?", default=str(pathlib.Path(__file__).resolve().parent.parent
                                                      / "desktop" / "wallpapers" / "live"))
    ap.add_argument("--only", nargs="+", choices=sorted(SCENES))
    ap.add_argument("--seconds", type=int, default=16)
    ap.add_argument("--preview", action="store_true", help="write one PNG per scene instead of a video")
    args = ap.parse_args()
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in args.only or SCENES:
        t0 = time.time()
        path = render(name, SCENES[name](), out_dir, args.seconds, args.preview)
        size = path.stat().st_size / 1e6
        print(f"{name:8s} {path}  {size:.1f} MB  ({time.time() - t0:.0f}s)")


if __name__ == "__main__":
    main()
