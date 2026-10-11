"""Project 04-05, extensions.

    python src/extra.py

1. Direct (spatial) correlation vs. DFT correlation: agreement and timing.
2. Where does the time go? -- DFT vs. pixel-wise product vs. padding.
3. Normalised correlation vs. plain correlation: robustness to a bright image.
4. Several objects at once: the number of peaks, and detecting a *different*
   template with the same code.
5. Non-square / odd-sized images (P, Q not a power of two, odd).
"""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

from correlation import find_target, linear_correlate, match_at, pad_to
from dft import dft2d, idft2d
from utils import data_dir, results_dir, save_fig

HERE = os.path.abspath(__file__)


def load(name):
    return np.array(Image.open(os.path.join(data_dir(HERE), name)).convert("L"),
                    dtype=np.float64)


def best_time(fn, repeats=3):
    best = float("inf")
    for _ in range(repeats):
        t = time.time()
        fn()
        best = min(best, time.time() - t)
    return best


def spatial_correlate(img, tpl):
    """Brute-force correlation: the definition Example 4.11 is based on.

    corr(i, j) = sum_{a, b} f_pad(i + a, j + b) * t(a, b),
    where f_pad is f zero-padded to (M + C - 1, N + D - 1).  This is exactly
    what the DFT computes, so the two must agree to rounding error.
    """
    h, w = tpl.shape
    M, N = img.shape
    fp = np.zeros((M + h - 1, N + w - 1))
    fp[:M, :N] = img
    out = np.zeros_like(fp)
    for i in range(fp.shape[0]):
        for j in range(fp.shape[1]):
            #  Skip rows/columns where the window would run past the padding.
            if i + h > fp.shape[0] or j + w > fp.shape[1]:
                continue
            out[i, j] = np.sum(fp[i:i + h, j:j + w] * tpl)
    return out

def ext1_direct_vs_dft():
    img, tpl = load("example_a.png"), load("example_b.png")
    h, w = tpl.shape
    pad = (img.shape[0] + h - 1, img.shape[1] + w - 1)

    corr_dft = linear_correlate(img, tpl, pad)
    t_dft = best_time(lambda: linear_correlate(img, tpl, pad))

    corr_dir = spatial_correlate(img, tpl)
    t_dir = best_time(lambda: spatial_correlate(img, tpl))

    err = np.max(np.abs(corr_dft - corr_dir))
    print(f"[1] DFT vs direct: max difference {err:.3e}   "
          f"DFT {t_dft:.4f}s, direct {t_dir:.4f}s, speedup {t_dir / t_dft:.1f}x")
    return t_dft, t_dir, err


def ext2_sizes():
    """How the DFT method scales, and why padding matters."""
    rng = np.random.default_rng(0)
    ns = [64, 128, 256, 512, 1024]
    ts = []
    for n in ns:
        img = rng.random((n, n))
        tpl = rng.random((32, 32))
        pad = (n + 31, n + 31)
        ts.append(best_time(lambda: linear_correlate(img, tpl, pad)))
    print("[2] DFT correlation time:", {n: round(t, 4) for n, t in zip(ns, ts)})
    slope = np.polyfit(np.log(ns), np.log(ts), 1)[0]
    print(f"    log-log slope = {slope:.2f}  (two transforms -> about n^2 log n)")

    plt.figure(figsize=(6, 4))
    plt.loglog(ns, ts, "o-")
    plt.xlabel("image side n (n x n)")
    plt.ylabel("time (s)")
    plt.grid(True, which="both")
    save_fig("ext2_speed.png", HERE)
    plt.close()
    return ns, ts


def ext3_normalized():
    """Plain vs. normalised correlation on a bright background."""
    img, tpl = load("example_a.png"), load("example_b.png")
    #  Flip the contrast: a bright background defeats the plain correlation.
    bright = 255.0 - img
    h, w = tpl.shape
    pad = (img.shape[0] + h - 1, img.shape[1] + w - 1)

    plain = linear_correlate(bright, tpl, pad, subtract_mean=False)
    norm = linear_correlate(bright, 255.0 - tpl, pad, subtract_mean=True)
    print(f"[3] bright background (contrast inverted): plain peak "
          f"{find_target(plain)}  peak/mean {plain.max() / plain.mean():.1f}")
    print(f"    normalised (template matched to the inverted image) peak "
          f"{find_target(norm)}")

    #  A cleaner demonstration: mean-removed vs plain on a mostly-bright image.
    fig, axes = plt.subplots(1, 2, figsize=(11, 5))
    axes[0].imshow(np.log1p(plain - plain.min()), cmap="gray")
    axes[0].set_title("plain correlation (bright background)")
    axes[1].imshow(linear_correlate(img, tpl, pad, subtract_mean=True), cmap="gray")
    axes[1].set_title("mean-removed correlation")
    save_fig("ext3_normalized.png", HERE)
    plt.close()
    return plain, norm


def ext4_two_templates():
    """The same code locates a *different* template (the "K" instead of the "T")."""
    img = load("example_a.png")
    ys, xs = np.nonzero(img > 128)
    #  The block contains "UTK"; crop the "K" from the right-hand side.
    block = img[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    k_tpl = block[int(0.05 * block.shape[0]):int(0.95 * block.shape[0]),
                  int(0.72 * block.shape[1]):]
    t_tpl = load("example_b.png")

    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    axes[0].imshow(img, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title("image")
    found = []
    for ax, (name, tpl) in zip(axes[1:], (("T", t_tpl), ("K", k_tpl))):
        h, w = tpl.shape
        pad = (img.shape[0] + h - 1, img.shape[1] + w - 1)
        corr = linear_correlate(img, tpl, pad, subtract_mean=True)
        loc = find_target(corr)
        found.append((name, loc))
        ax.imshow(img, cmap="gray", vmin=0, vmax=255)
        ax.add_patch(plt.Rectangle((loc[1] - 0.5, loc[0] - 0.5), w, h,
                                   edgecolor="r", facecolor="none", linewidth=1.5))
        ax.set_title(f'template "{name}" -> peak {tuple(loc)}')
    for ax in axes:
        ax.axis("off")
    save_fig("ext4_two_templates.png", HERE)
    plt.close()
    print(f"[4] same code, two templates: {found}")
    return found, block, k_tpl


def local_maxima(a, threshold, radius):
    """All points equal to the max within a (2*radius+1) neighbourhood."""
    M, N = a.shape
    out = []
    order = np.argsort(a.ravel())[::-1]
    for idx in order:
        i, j = divmod(int(idx), N)
        if a[i, j] < threshold:
            break
        if all((i - p) ** 2 + (j - q) ** 2 > radius ** 2 for p, q in out):
            out.append((i, j))
    return sorted(out)


def ext5_nonsquare():
    """Non-square, odd-sized crop: the transform needs no special casing."""
    img, tpl = load("example_a.png"), load("example_b.png")
    crop = img[30:220, 20:250]               # 190 x 230 (even x even)
    odd = img[31:220, 21:250]                # 189 x 229 (odd x odd)
    for name, c in (("190x230", crop), ("189x229", odd)):
        h, w = tpl.shape
        pad = (c.shape[0] + h - 1, c.shape[1] + w - 1)
        corr = linear_correlate(c, tpl, pad, subtract_mean=True)
        loc = find_target(corr)
        win = match_at(c, tpl, loc, subtract_mean=True)
        ref = tpl - tpl.mean()
        ncc = np.sum(win * ref) / (np.linalg.norm(win) * np.linalg.norm(ref))
        print(f"[5] crop {c.shape}  peak {loc}  NCC {ncc:.4f}")


def main():
    ext1_direct_vs_dft()
    ext2_sizes()
    ext3_normalized()
    ext4_two_templates()
    ext5_nonsquare()
    print("\ndone")


if __name__ == "__main__":
    main()
