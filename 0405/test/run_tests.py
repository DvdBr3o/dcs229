"""Run the same correlation pipeline on extra test images (no algorithm change).

    python test/run_tests.py

For each test image a template is cut out of the image itself (so the true
location is known) and the correlation is asked to find it back.  Results are
written next to this script, in `test_1_results/` and `test_2_results/`.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

from correlation import find_target, linear_correlate, match_at

HERE = os.path.dirname(os.path.abspath(__file__))

#  image file, template cut-out (row, col, height, width), description
CASES = {
    "test_1": ("test_1.bmp", (300, 250, 140, 160), "characters test pattern"),
    "test_2": ("test_2.bmp", (60, 300, 180, 200), "child with a paper hat"),
}


def run(name, fname, box, desc):
    out = os.path.join(HERE, f"{name}_results")
    os.makedirs(out, exist_ok=True)

    img = np.array(Image.open(os.path.join(HERE, fname)).convert("L"), dtype=np.float64)
    r, c, h, w = box
    tpl = img[r:r + h, c:c + w]
    pad = (img.shape[0] + h - 1, img.shape[1] + w - 1)

    corr = linear_correlate(img, tpl, pad, subtract_mean=True)
    loc = find_target(corr)
    ref = tpl - tpl.mean()
    win = match_at(img, tpl, loc, subtract_mean=True)
    ncc = np.sum(win * ref) / (np.linalg.norm(win) * np.linalg.norm(ref))

    print(f"{name}: {desc}  image {img.shape}  template {tpl.shape}")
    print(f"    true {box[:2]}  found {loc}  NCC {ncc:.4f}  peak/mean "
          f"{corr[loc] / corr.std():.1f}")

    Image.fromarray(tpl.astype(np.uint8)).save(os.path.join(out, "template.png"))

    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    axes[0].imshow(img, cmap="gray", vmin=0, vmax=255)
    axes[0].add_patch(plt.Rectangle((c, r), w, h, edgecolor="lime",
                                    facecolor="none", linewidth=1.5))
    axes[0].set_title("image + true location (green)")
    axes[1].imshow(tpl, cmap="gray", vmin=0, vmax=255); axes[1].set_title("template")
    axes[2].imshow(img, cmap="gray", vmin=0, vmax=255)
    axes[2].add_patch(plt.Rectangle((loc[1], loc[0]), w, h, edgecolor="red",
                                    facecolor="none", linewidth=1.5))
    axes[2].set_title(f"found location (red) {tuple(loc)}")
    for ax in axes:
        ax.axis("off")
    fig.savefig(os.path.join(out, "detection.png"), dpi=150, bbox_inches="tight")
    plt.close()

    fig, ax = plt.subplots(figsize=(6, 5))
    ax.imshow(np.log1p(corr - corr.min()), cmap="gray")
    ax.set_title("correlation (log scale)")
    fig.savefig(os.path.join(out, "correlation.png"), dpi=150, bbox_inches="tight")
    plt.close()


def main():
    for name, (fname, box, desc) in CASES.items():
        run(name, fname, box, desc)
    print("done")


if __name__ == "__main__":
    main()
