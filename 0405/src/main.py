"""Project 04-05, part (a): correlation by the DFT (Example 4.11).

    python src/main.py

Localises the template inside the image with

    g(x, y) = IDFT{ F(u, v) * conj(T(u, v)) },

reproduces Figs. 4.41(c)-(f) and reports how well the found position agrees
with the position the template was cut from.

Two material sets are used:
  * `example_a.png` / `example_b.png` -- the layout of Example 4.11 (a 256x256
    image with the template copy in the middle), built by `make_example_image.py`;
  * `Fig0441a.jpg` / `Fig0441b.png` -- the figures shipped with the
    supplementary document (a cropped Fig. 4.41(a) and its "T" template).
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


def norm_score(a, b):
    return np.sum(a * b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-30)


def run(tag, img_name, tpl_name):
    img, tpl = load(img_name), load(tpl_name)
    (M, N), (C, D) = img.shape, tpl.shape
    #  Example 4.11: P = A + C - 1, Q = B + D - 1 (the exact minimum).
    pad = (M + C - 1, N + D - 1)

    print(f"\n=== {tag}  ({img_name} vs {tpl_name}) ===")
    print(f"image {img.shape}   template {tpl.shape}   padded {pad}")

    res = {}
    for sm in (False, True):
        t0 = time.time()
        corr = linear_correlate(img, tpl, pad, subtract_mean=sm)
        dt = time.time() - t0
        loc = find_target(corr)
        ref = (tpl - tpl.mean()) if sm else tpl
        win = match_at(img, tpl, loc, subtract_mean=sm)
        res[sm] = dict(corr=corr, loc=loc, err=np.max(np.abs(win - ref)),
                       ncc=norm_score(win, ref), t=dt)
        label = "mean-removed" if sm else "plain (textbook)"
        print(f"  {label:16s}: peak {str(loc):>13s}  NCC {res[sm]['ncc']:6.4f}"
              f"  max|win-tpl| {res[sm]['err']:5.1f}  peak/mean {corr[loc] / corr.mean():8.1f}"
              f"  ({dt:.3f} s)")

    corr, loc = res[True]["corr"], res[True]["loc"]

    #  Fig. 4.41(c) / (d): the two zero-padded functions.
    fig = plt.figure(figsize=(10, 5))
    ax = fig.add_subplot(1, 2, 1)
    ax.imshow(pad_to(img, pad), cmap="gray", vmin=0, vmax=255)
    ax.set_title(f"padded image  {pad[0]} x {pad[1]}")
    ax = fig.add_subplot(1, 2, 2)
    ax.imshow(pad_to(tpl, pad), cmap="gray", vmin=0, vmax=255)
    ax.set_title("padded template")
    save_fig(f"fig_{tag}_c_padded.png", HERE)
    if tag == "ex":
        save_fig("fig02_0405_padded.png", HERE)
    plt.close()

    #  Fig. 4.41(e): the correlation function as an image.  The peak is orders
    #  of magnitude above the rest, so the gray scale is stretched with a log
    #  map to make the peak visible (the textbook figure uses the same idea).
    fig, ax = plt.subplots(figsize=(5.4, 5.4))
    disp = np.log1p(corr - corr.min())
    ax.imshow(disp, cmap="gray", vmax=np.percentile(disp, 99.5))
    ax.plot(loc[1], loc[0], "r+", markersize=12, markeredgewidth=1.4)
    ax.set_title("correlation  IDFT{F * conj(T)}   (red + = peak)")
    save_fig(f"fig_{tag}_e_corr.png", HERE)
    plt.close()

    #  Fig. 4.41(f): profile through the highest value.
    fig, ax = plt.subplots(figsize=(8, 3.4))
    ax.plot(corr[loc[0]], "k-", linewidth=0.9)
    ax.axvline(loc[1], color="r", linestyle="--", linewidth=0.8)
    ax.annotate("highest value", xy=(loc[1], corr[loc[0], loc[1]]),
                xytext=(0.06 * corr.shape[1], corr[loc[0]].max() * 0.72),
                arrowprops=dict(arrowstyle="->", linewidth=0.8))
    ax.set_xlabel("horizontal position"); ax.set_ylabel("correlation")
    save_fig(f"fig_{tag}_f_profile.png", HERE)
    plt.close()

    #  Detection panels: image, template and the window the correlation found.
    found = match_at(img, tpl, loc).astype(np.uint8)
    fig, axes = plt.subplots(1, 3, figsize=(11.5, 4.4))
    axes[0].imshow(img, cmap="gray", vmin=0, vmax=255); axes[0].set_title("image f")
    axes[1].imshow(tpl, cmap="gray", vmin=0, vmax=255); axes[1].set_title("template t")
    axes[2].imshow(found, cmap="gray", vmin=0, vmax=255)
    axes[2].set_title(f"window at peak {tuple(loc)}")
    for ax in axes:
        ax.axis("off")
    save_fig(f"fig_{tag}_a_detect.png", HERE)
    plt.close()

    #  Overlay of the found location.
    fig, ax = plt.subplots(figsize=(5.4, 5.4))
    ax.imshow(img, cmap="gray", vmin=0, vmax=255)
    ax.add_patch(plt.Rectangle((loc[1] - 0.5, loc[0] - 0.5), D, C,
                               edgecolor="r", facecolor="none", linewidth=1.5))
    ax.set_title(f"peak at (row, col) = {tuple(loc)}")
    save_fig(f"fig_{tag}_b_overlay.png", HERE)
    plt.close()

    np.save(os.path.join(results_dir(HERE), f"corr_{tag}.npy"), corr)
    return res


def exercises(img_name, tpl_name):
    """Exercises 4.22 (drop (-1)^u) and 4.23 (exchange the transforms)."""
    img, tpl = load(img_name), load(tpl_name)
    (M, N), (C, D) = img.shape, tpl.shape
    pad = (M + C - 1, N + D - 1)
    F = dft2d(pad_to(img, pad))
    T = dft2d(pad_to(tpl, pad))
    full = np.real(idft2d(F * np.conj(T)))        # the textbook form
    swapped = np.real(idft2d(np.conj(F) * T))     # Exercise 4.23
    u = np.arange(pad[0])[:, None]
    omitted = np.real(idft2d(F * np.conj(T) * (-1.0) ** u))   # Exercise 4.22
    return dict(full=find_target(full), swapped=find_target(swapped),
                omitted=find_target(omitted),
                full_corr=full, swapped_corr=swapped, omitted_corr=omitted)


def main():
    ex = run("ex", "example_a.png", "example_b.png")
    run("sup", "Fig0441a.jpg", "Fig0441b.png")

    #  Exercise 4.23 on the textbook material: exchanging the conjugate should
    #  mirror the correlation, i.e. the two peaks must add up to the pad size.
    v = exercises("example_a.png", "example_b.png")
    print("\n=== Exercises 4.22 / 4.23 ===")
    print(f"textbook form (F * conj(T)): peak {v['full']}")
    print(f"swapped  (conj(F) * T)     : peak {v['swapped']}")
    P, Q = v["full_corr"].shape
    print(f"mirror check: full + swapped - 1 = "
          f"{(v['full'][0] + v['swapped'][0] - 1, v['full'][1] + v['swapped'][1] - 1)}"
          f"  (pad size {(P, Q)})")
    print(f"peak of the mirrored form: {v['swapped_corr'].max():.3e}"
          f"  (textbook form {v['full_corr'].max():.3e})")
    print(f"exercise 4.22 (missing (-1)^u) peak: {v['omitted']}"
          f"  value {v['omitted_corr'].max():.3e}"
          f"  / textbook {v['full_corr'].max():.3e}"
          f"  = {v['omitted_corr'].max() / v['full_corr'].max():.3f}")
    print("\ndone")


if __name__ == "__main__":
    main()
