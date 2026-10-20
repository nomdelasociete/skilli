"""Fit the folded glass ribbon to the 2D mark (../ribbon-mask.svg).

    uv run --with numpy --with scipy --with pillow assets/brand/3d/fit_ribbon.py

Needs `rsvg-convert` (librsvg). Prints the parameters to paste into
build_logo.py's `P` and the front-view IoU, and writes fit-check.png
(white = both, blue = SVG only, orange = 3D only).

Model: one flat strip, Z-folded twice. Each fold rolls the strip away from
the viewer around a half-ellipse cross-section (semi-axes a across, b deep);
both folds share the crease direction, so the bands stay parallel. The same
maths as build_logo.fold(), vectorised.
"""
import io
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.optimize import minimize

HERE = Path(__file__).resolve().parent
PX = 2                                   # pixels per SVG unit
W, H = 270 * PX, 264 * PX
R_OUTER, R_INNER = 6.5, 22.0             # free-end corner radii, from the SVG
DOT = (215.0, 209.0, 17.5)
KEYS = ["theta", "x1", "D", "a", "b", "w", "yt", "xmin", "xmax"]
START = [105.5, 89.0, 244.0, 14.7, 55.3, 54.0, 39.8, -418.0, 213.0]


def load_mask():
    png = subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), str(HERE.parent / "ribbon-mask.svg")],
                         check=True, capture_output=True).stdout
    alpha = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA"))[..., 3] > 127
    yy, xx = np.mgrid[0:H, 0:W]
    dot = (xx / PX - DOT[0]) ** 2 + (yy / PX - DOT[1]) ** 2 < (DOT[2] + 2) ** 2
    return alpha & ~dot


def frame(theta):
    t = np.radians(theta)
    c = np.array([np.cos(t), np.sin(t)])
    n = np.array([-np.sin(t), np.cos(t)])
    return c, (-n if n[0] > 0 else n)


def fold_map(P, p):
    c, n = frame(p["theta"])
    ph = np.linspace(0, np.pi, 4000)
    pt, dt = p["a"] * np.sin(ph), p["b"] * (1 - np.cos(ph))
    st = np.concatenate([[0], np.cumsum(np.hypot(np.diff(pt), np.diff(dt)))])
    L = st[-1]
    q1 = np.array([p["x1"], p["yt"]])
    folds = [q1, q1 + p["D"] * n]

    def F(P, k):
        if k == 2:
            return P.copy()
        Q = folds[k]
        s, t = (P - Q) @ n, (P - Q) @ c
        out = P.copy()
        m = (s > 0) & (s <= L)
        out[m] = Q + np.outer(np.interp(s[m], st, pt), n) + np.outer(t[m], c)
        m = s > L
        if m.any():
            Pb = F(P[m], k + 1)
            sb, tb = (Pb - Q) @ n, (Pb - Q) @ c
            out[m] = Q + np.outer(-(sb - L), n) + np.outer(tb, c)
        return out

    return F(P, 0)


def strip_points(p, step=0.35):
    X, Y = np.meshgrid(np.arange(p["xmin"], p["xmax"], step), np.arange(p["yt"], p["yt"] + p["w"], step))
    ok = np.ones(X.shape, bool)
    for x_end, side, r_top, r_bot in ((p["xmax"], -1, R_OUTER, R_INNER), (p["xmin"], 1, R_INNER, R_OUTER)):
        for r, cy, sy in ((r_top, p["yt"] + r_top, 1), (r_bot, p["yt"] + p["w"] - r_bot, -1)):
            cx = x_end + side * r
            corner = (side * (X - cx) < 0) & (sy * (Y - cy) < 0)
            ok &= ~(corner & ((X - cx) ** 2 + (Y - cy) ** 2 > r * r))
    return np.stack([X[ok], Y[ok]], 1)


def raster(p):
    Q = fold_map(strip_points(p), p)
    img = np.zeros((H, W), bool)
    img[np.clip((Q[:, 1] * PX).astype(int), 0, H - 1), np.clip((Q[:, 0] * PX).astype(int), 0, W - 1)] = True
    return img


def main():
    mask = load_mask()

    def cost(v):
        p = dict(zip(KEYS, v))
        if p["a"] < 4 or p["b"] < p["a"] or p["b"] > 90:
            return 1.0
        img = raster(p)
        return 1 - (img & mask).sum() / (img | mask).sum()

    res = minimize(cost, START, method="Nelder-Mead", options={"maxiter": 4000, "xatol": 0.02, "fatol": 1e-7})
    p = dict(zip(KEYS, (round(v, 4) for v in res.x)))
    print(json.dumps(p, indent=1))
    print(f"IoU {1 - res.fun:.4f}")
    img = raster(p)
    vis = np.zeros((H, W, 3), np.uint8)
    vis[mask] = (0, 160, 255)
    vis[img] = (255, 120, 0)
    vis[img & mask] = (235, 235, 235)
    Image.fromarray(vis).save(HERE / "fit-check.png")


if __name__ == "__main__":
    main()
