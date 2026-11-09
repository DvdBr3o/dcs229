"""Project 4: morphological post-processing of the Project 3 skin masks.

Pipeline (each image uses the segmenter chosen for it in Project 3):

    input image
      -> grayscale open/close smoothing of each channel
      -> Project 3 color-space segmentation (raw mask)
      -> binary opening (noise, hair strands)
      -> binary closing (gaps from eyes, glasses, lips)
      -> hole filling (conditional dilation)
      -> large opening (hair tips, thin protrusions)
      -> connected-component filtering (8-connectivity)
      -> boundary extraction (visualization only)

Usage:
    python project4/morphology.py           # process the three images -> project4/public/morph/
    python project4/morphology.py --show    # also display the figures
"""

from __future__ import annotations

import sys
from collections import OrderedDict, deque
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

from colorspace_split import HSVSplit, Split, YCbCrBoxSplit, YCbCrEllipseSplit, rgb_to_ycbcr


# Structuring elements (odd size, origin at the center)
def disk(radius: int) -> np.ndarray:
    y, x = np.ogrid[-radius:radius + 1, -radius:radius + 1]
    return x * x + y * y <= radius * radius


def square(size: int) -> np.ndarray:
    return np.ones((size, size), dtype=bool)


def cross() -> np.ndarray:
    """3x3 cross (4-neighborhood), used for hole filling."""
    se = np.zeros((3, 3), dtype=bool)
    se[1, :] = True
    se[:, 1] = True
    return se


# ---------------------------------------------------------------------------
# Core: erosion/dilation with flat structuring elements (min/max filters).
# The SE is split into row runs (dy, x0, x1); each run's sliding min/max uses
# the doubling method, then the runs are shifted by dy and merged. 
# Binary masks are 0/1 uint8 (erosion = min, dilation = max), so binary and gray share code.
# Out-of-image pixels never affect the result (1 for erosion, 0 for dilation).
# ---------------------------------------------------------------------------


def _shift(a: np.ndarray, dy: int, dx: int, fill) -> np.ndarray:
    """out[y, x] = a[y + dy, x + dx]; out-of-bounds filled with `fill`."""
    h, w = a.shape
    out = np.full_like(a, fill)
    if abs(dy) >= h or abs(dx) >= w:
        return out
    ys_dst, ys_src = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs_dst, xs_src = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[ys_dst, xs_dst] = a[ys_src, xs_src]
    return out


def _runs(se: np.ndarray) -> list[tuple[int, int, int]]:
    """Split the SE into contiguous row runs (dy, x0, x1) relative to the center."""
    if se.ndim != 2 or se.shape[0] % 2 == 0 or se.shape[1] % 2 == 0:
        raise ValueError(f"structuring element must be 2D with odd size, got shape {se.shape}")
    cy, cx = se.shape[0] // 2, se.shape[1] // 2
    runs = []
    for i in range(se.shape[0]):
        cols = np.flatnonzero(se[i])
        if cols.size == 0:
            continue
        start = prev = cols[0]
        for c in cols[1:]:
            if c != prev + 1:
                runs.append((i - cy, int(start - cx), int(prev - cx)))
                start = c
            prev = c
        runs.append((i - cy, int(start - cx), int(prev - cx)))
    return runs


def _run_extreme(f: np.ndarray, x0: int, x1: int, ext, fill) -> np.ndarray:
    """out[y, x] = ext(f[y, x+x0 .. x+x1]) via the doubling method."""
    w = x1 - x0 + 1
    pad = max(abs(x0), abs(x1))  # pad with the identity so edge windows are correct
    cur = np.pad(f, ((0, 0), (pad, pad)), mode="constant", constant_values=fill)
    size = 1
    while size * 2 <= w:
        cur = ext(cur, _shift(cur, 0, size, fill))
        size *= 2
    if size < w:
        cur = ext(cur, _shift(cur, 0, w - size, fill))
    cur = _shift(cur, 0, x0, fill)
    return cur[:, pad:cur.shape[1] - pad]


def _flat_filter(f: np.ndarray, se: np.ndarray, erode_mode: bool, lo, hi) -> np.ndarray:
    se = np.asarray(se, dtype=bool)
    if erode_mode:  # (f ⊖ b)(x) = min_{s in b} f(x+s)
        ext, fill = np.minimum, hi
    else:  # (f ⊕ b)(x) = max_{s in b} f(x-s): max with the reflected b
        ext, fill = np.maximum, lo
        se = se[::-1, ::-1]
    out = np.full_like(f, fill)
    cache: dict[tuple[int, int], np.ndarray] = {}
    for dy, x0, x1 in _runs(se):
        key = (x0, x1)
        if key not in cache:
            cache[key] = _run_extreme(f, x0, x1, ext, fill)
        out = ext(out, _shift(cache[key], dy, 0, fill))
    return out


# ---------------------------------------------------------------------------
# Binary morphology
# ---------------------------------------------------------------------------


def erode(mask: np.ndarray, se: np.ndarray) -> np.ndarray:
    """A ⊖ B = {z | (B)_z ⊆ A}"""
    return _flat_filter(mask.astype(np.uint8), se, True, 0, 1).astype(bool)


def dilate(mask: np.ndarray, se: np.ndarray) -> np.ndarray:
    """A ⊕ B = {z | (B^)_z ∩ A ≠ ∅}"""
    return _flat_filter(mask.astype(np.uint8), se, False, 0, 1).astype(bool)


def opening(mask: np.ndarray, se: np.ndarray) -> np.ndarray:
    """(A ⊖ B) ⊕ B: removes small specks and thin bridges."""
    return dilate(erode(mask, se), se)


def closing(mask: np.ndarray, se: np.ndarray) -> np.ndarray:
    """(A ⊕ B) ⊖ B: bridges narrow gaps and fills small holes."""
    return erode(dilate(mask, se), se)


def boundary(mask: np.ndarray, se: np.ndarray | None = None) -> np.ndarray:
    """β(A) = A - (A ⊖ B)."""
    se = square(3) if se is None else se
    return mask & ~erode(mask, se)


def reconstruct(marker: np.ndarray, mask: np.ndarray, se: np.ndarray) -> np.ndarray:
    """Conditional dilation X_k = (X_{k-1} ⊕ B) ∩ mask until it stops changing.
    Hole filling and component extraction both use it."""
    x = marker & mask
    while True:
        nxt = dilate(x, se) & mask
        if np.array_equal(nxt, x):
            return x
        x = nxt


def fill_holes(mask: np.ndarray) -> np.ndarray:
    """Flood the background from the image border (4-connected); whatever
    the flood cannot reach is a hole, and the result is A ∪ holes."""
    bg = ~mask
    marker = np.zeros_like(mask)
    marker[0, :], marker[-1, :], marker[:, 0], marker[:, -1] = True, True, True, True
    reached = reconstruct(marker & bg, bg, cross())
    return ~reached


def extract_component(mask: np.ndarray, seed: tuple[int, int]) -> np.ndarray:
    """Component containing `seed`: repeated 3x3 dilation (8-connectivity) ∩ A."""
    marker = np.zeros_like(mask)
    marker[seed] = True
    return reconstruct(marker, mask, square(3))


def label_components(mask: np.ndarray) -> tuple[np.ndarray, list[int]]:
    """8-connected labeling by BFS. Returns (label image, areas); labels start at 1.
    Same result as extract_component, but labels everything in one pass."""
    h, w = mask.shape
    pw = w + 2
    padded = np.zeros((h + 2, pw), dtype=bool)
    padded[1:-1, 1:-1] = mask
    flat = padded.ravel()
    labels = np.zeros(flat.size, dtype=np.int32)
    offsets = (-pw - 1, -pw, -pw + 1, -1, 1, pw - 1, pw, pw + 1)
    areas: list[int] = []
    for start in np.flatnonzero(flat):
        if labels[start]:
            continue
        lab = len(areas) + 1
        labels[start] = lab
        q, count = deque([start]), 0
        while q:
            p = q.popleft()
            count += 1
            for o in offsets:
                n = p + o
                if flat[n] and not labels[n]:
                    labels[n] = lab
                    q.append(n)
        areas.append(count)
    return labels.reshape(h + 2, pw)[1:-1, 1:-1], areas


def keep_large_components(mask: np.ndarray, min_ratio: float = 0.2, min_area: int = 0) -> np.ndarray:
    """Keep components with area >= max(min_area, min_ratio * largest area)."""
    labels, areas = label_components(mask)
    if not areas:
        return mask.copy()
    thr = max(min_area, min_ratio * max(areas))
    keep = np.array([False] + [a >= thr for a in areas])
    return keep[labels]


# ---------------------------------------------------------------------------
# Grayscale morphology (b: flat bool SE, or non-flat float SE with -inf outside)
# ---------------------------------------------------------------------------


def gray_erode(f: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Flat: min f(x+s, y+t). Non-flat: min [f(x+s, y+t) - b(s, t)]."""
    f = f.astype(np.float32)
    if b.dtype == bool:
        return _flat_filter(f, b, True, -np.inf, np.inf)
    out = np.full_like(f, np.inf)
    cy, cx = b.shape[0] // 2, b.shape[1] // 2
    for i, j in zip(*np.nonzero(np.isfinite(b))):
        out = np.minimum(out, _shift(f, i - cy, j - cx, np.inf) - np.float32(b[i, j]))
    return out


def gray_dilate(f: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Flat: max f(x-s, y-t). Non-flat: max [f(x-s, y-t) + b(s, t)]."""
    f = f.astype(np.float32)
    if b.dtype == bool:
        return _flat_filter(f, b, False, -np.inf, np.inf)
    out = np.full_like(f, -np.inf)
    cy, cx = b.shape[0] // 2, b.shape[1] // 2
    for i, j in zip(*np.nonzero(np.isfinite(b))):
        out = np.maximum(out, _shift(f, -(i - cy), -(j - cx), -np.inf) + np.float32(b[i, j]))
    return out


def gray_opening(f: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Removes bright details smaller than the SE."""
    return gray_dilate(gray_erode(f, b), b)


def gray_closing(f: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Removes dark details smaller than the SE."""
    return gray_erode(gray_dilate(f, b), b)


def gray_smooth(f: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Opening then closing: removes both bright and dark noise."""
    return gray_closing(gray_opening(f, b), b)


def gray_gradient(f: np.ndarray, b: np.ndarray | None = None) -> np.ndarray:
    """(f ⊕ b) - (f ⊖ b), 3x3 by default."""
    b = square(3) if b is None else b
    return gray_dilate(f, b) - gray_erode(f, b)


def top_hat(f: np.ndarray, b: np.ndarray, white: bool = True) -> np.ndarray:
    """White top-hat f - (f ∘ b), or black bottom-hat (f • b) - f."""
    return f - gray_opening(f, b) if white else gray_closing(f, b) - f


# ---------------------------------------------------------------------------
# Pipeline and Split wrapper
# ---------------------------------------------------------------------------


def _r(frac: float, unit: int) -> int:
    return max(1, int(round(frac * unit)))


def smooth_image(rgb: np.ndarray, radius: int) -> np.ndarray:
    """Grayscale open/close smoothing of each RGB channel."""
    if radius <= 0:
        return rgb
    b = disk(radius)
    out = np.stack([gray_smooth(rgb[..., c], b) for c in range(3)], axis=-1)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def clean_mask_stages(
    mask: np.ndarray,
    open_frac: float = 0.006,
    close_frac: float = 0.015,
    shape_open_frac: float = 0.02,
    min_ratio: float = 0.2,
) -> "OrderedDict[str, np.ndarray]":
    """Mask after each step (last item = final result).
    Radii are fractions of the image's short side, so they scale with resolution."""
    unit = min(mask.shape)
    stages: OrderedDict[str, np.ndarray] = OrderedDict()
    stages["raw mask"] = mask
    m = opening(mask, disk(_r(open_frac, unit)))
    stages["opening"] = m
    m = closing(m, disk(_r(close_frac, unit)))
    stages["closing"] = m
    m = fill_holes(m)
    stages["fill holes"] = m
    if shape_open_frac > 0:  # optional: larger opening removes hair tips and thin protrusions
        m = opening(m, disk(_r(shape_open_frac, unit)))
        stages["shape opening"] = m
    m = keep_large_components(m, min_ratio=min_ratio)
    stages["components"] = m
    return stages


def clean_mask(mask: np.ndarray, **kwargs) -> np.ndarray:
    return next(reversed(clean_mask_stages(mask, **kwargs).values()))


class MorphSplit(Split):
    """Wraps a Project 3 Split: gray smoothing, then segmentation, then binary cleanup."""

    def __init__(self, base: Split, smooth_frac: float = 0.004, **kwargs) -> None:
        self.base = base
        self.smooth_frac = smooth_frac
        self.kwargs = kwargs

    def preprocess(self, img: np.ndarray) -> np.ndarray:
        return smooth_image(img, _r(self.smooth_frac, min(img.shape[:2])) if self.smooth_frac > 0 else 0)

    def mask(self, img: np.ndarray) -> np.ndarray:
        return clean_mask(self.base.mask(self.preprocess(img)), **self.kwargs)


# ---------------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------------

PROJECT_DIR = Path(__file__).resolve().parent
OUT_DIR = PROJECT_DIR / "public" / "morph"

# Segmenter chosen for each image in Project 3
CASES: dict[str, Split] = {
    "asian_1": YCbCrEllipseSplit(),
    "asian_6": YCbCrBoxSplit(),
    "asian_13": HSVSplit(),
}


def count_components(mask: np.ndarray) -> int:
    return len(label_components(mask)[1])


def count_holes(mask: np.ndarray) -> int:
    return count_components(fill_holes(mask) & ~mask)


def corner_fp(mask: np.ndarray, k: int = 80) -> float:
    """Fraction of the four k x k corners selected (background false-positive proxy)."""
    c = np.concatenate([mask[:k, :k].ravel(), mask[:k, -k:].ravel(),
                        mask[-k:, :k].ravel(), mask[-k:, -k:].ravel()])
    return float(c.mean())


def describe(mask: np.ndarray) -> str:
    return (f"{mask.mean():6.2%} | comps {count_components(mask):3d} | holes {count_holes(mask):3d} | "
            f"boundary {int(boundary(mask).sum()):5d} | corners {corner_fp(mask):6.2%}")


def overlay_boundary(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
    out = rgb.copy()
    out[dilate(boundary(mask), square(3))] = (255, 0, 0)
    return out


def run_case(name: str, base: Split, show: bool = False) -> None:
    image = Image.open(PROJECT_DIR / "public" / f"{name}.png").convert("RGB")
    rgb = np.array(image)
    morph = MorphSplit(base)

    smoothed = morph.preprocess(rgb)
    raw = base.mask(rgb)  # Project 3 result
    stages = clean_mask_stages(base.mask(smoothed))
    final = next(reversed(stages.values()))
    out = np.where(final[..., None], rgb, 0).astype(np.uint8)

    print(f"\n{name} ({type(base).__name__})")
    print(f"  {'project 3 mask':16s} {describe(raw)}")
    for key, m in stages.items():
        print(f"  {key:16s} {describe(m)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    Image.fromarray(raw.astype(np.uint8) * 255).save(OUT_DIR / f"{name}_p3_mask.png")
    Image.fromarray(final.astype(np.uint8) * 255).save(OUT_DIR / f"{name}_morph_mask.png")
    Image.fromarray(out).save(OUT_DIR / f"{name}_morph_out.png")

    # Figure 1: step-by-step results
    panels = [(rgb, "input"), (raw, "project 3 mask")]
    panels += [(m, k) for k, m in stages.items() if k != "raw mask"]
    panels += [(overlay_boundary(rgb, final), "boundary β(A)=A-(A⊖B)"), (out, "output")]
    cols = 4
    rows = -(-len(panels) // cols)
    fig, axes = plt.subplots(rows, cols, figsize=(4 * cols, 5 * rows))
    for ax in axes.ravel():
        ax.axis("off")
    for ax, (im, title) in zip(axes.ravel(), panels):
        ax.imshow(im, cmap="gray" if im.ndim == 2 else None)
        ax.set_title(title)
    fig.suptitle(f"{name} — {type(base).__name__}")
    fig.tight_layout()
    fig.savefig(OUT_DIR / f"{name}_steps.png", dpi=110, bbox_inches="tight")

    # Figure 2: grayscale morphology (smoothing, gradient, top-hat)
    y = rgb_to_ycbcr(rgb)[..., 0]
    unit = min(y.shape)
    ys = gray_smooth(y, disk(_r(0.004, unit)))
    gray_panels = [
        (y, "Y (luma)"),
        (ys, "open→close smoothing"),
        (gray_gradient(ys), "morphological gradient (3x3)"),
        (top_hat(y, disk(_r(0.03, unit)), white=True), "white top-hat"),
    ]
    fig2, axes2 = plt.subplots(1, 4, figsize=(16, 5))
    for ax, (im, title) in zip(axes2, gray_panels):
        ax.imshow(im, cmap="gray")
        ax.set_title(title)
        ax.axis("off")
    fig2.tight_layout()
    fig2.savefig(OUT_DIR / f"{name}_gray.png", dpi=110, bbox_inches="tight")

    if show:
        plt.show()
    plt.close("all")


def main() -> None:
    show = "--show" in sys.argv
    for name, base in CASES.items():
        run_case(name, base, show)


if __name__ == "__main__":
    main()
