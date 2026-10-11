"""Project 04-05: checks that the correlation is implemented correctly.

    python test/testing_correlation.py

Every check prints PASS / FAIL.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

import numpy as np
from PIL import Image

from correlation import find_target, linear_correlate, match_at, pad_to
from dft import center, dft2d, idft2d

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")


def check(name, err, tol=1e-8):
    print(f"{name}: error = {err:.2e}  ->  {'PASS' if err < tol else 'FAIL'}")
    return err < tol


def load(name):
    return np.array(Image.open(os.path.join(DATA, name)).convert("L"), dtype=np.float64)


ok = True

#  1. The DFT round trip.
rng = np.random.default_rng(0)
a = rng.random((8, 8))
ok &= check("DFT round trip (8, 8)", np.max(np.abs(idft2d(dft2d(a)) - a)))
a = rng.random((6, 10))
ok &= check("DFT round trip (6, 10)", np.max(np.abs(idft2d(dft2d(a)) - a)))

#  2. Correlation of a random image with a copy of one of its windows must
#     peak exactly at that window and return the window itself.
img = rng.integers(0, 256, (64, 64)).astype(np.float64)
tpl = img[20:32, 15:33]
pad = (img.shape[0] + tpl.shape[0] - 1, img.shape[1] + tpl.shape[1] - 1)
corr = linear_correlate(img, tpl, pad)
loc = find_target(corr)
ok &= check("peak at the true location", 0.0 if loc == (20, 15) else 1.0)
win = match_at(img, tpl, loc)
ok &= check("window at the peak equals the template", np.max(np.abs(win - tpl)))

#  3. The DFT correlation equals the direct (definition) correlation.
#     With the *minimum* padding P = M + C - 1 the wrapped tail of the linear
#     correlation reappears in the last row/column, so the comparison is made
#     on the principal M x N region.
from extra import spatial_correlate  # noqa: E402  (needs the src path above)

img_e, tpl_e = load("example_a.png"), load("example_b.png")
direct = spatial_correlate(img_e, tpl_e)[:256, :256]
dft_corr = linear_correlate(img_e, tpl_e, (299, 304))[:256, :256]
#  Normalise by the peak: the absolute error of a sum of ~2000 terms of
#  magnitude ~6e4 is at the 1e-7 level in float64.
rel = np.max(np.abs(direct - dft_corr)) / dft_corr.max()
ok &= check("DFT correlation == direct correlation", rel, tol=1e-12)

#  4. End to end: the textbook material.
img, tpl = load("example_a.png"), load("example_b.png")
pad = (img.shape[0] + tpl.shape[0] - 1, img.shape[1] + tpl.shape[1] - 1)
corr = linear_correlate(img, tpl, pad, subtract_mean=True)
loc = find_target(corr)
win = match_at(img, tpl, loc, subtract_mean=True)
ref = tpl - tpl.mean()
ncc = np.sum(win * ref) / (np.linalg.norm(win) * np.linalg.norm(ref))
ok &= check("end to end NCC == 1", abs(ncc - 1.0))

#  5. Degenerate sizes: compare only the principal (valid) region, because the
#     minimum padding wraps the tail of the linear correlation.
for shape in [(1, 1), (1, 5), (5, 1), (3, 3)]:
    small = rng.random(shape)
    t = rng.random((2, 2)) if min(shape) >= 2 else rng.random((1, 1))
    p = (shape[0] + t.shape[0] - 1, shape[1] + t.shape[1] - 1)
    c = linear_correlate(small, t, p)[:shape[0], :shape[1]]
    d = spatial_correlate(small, t)[:shape[0], :shape[1]]
    ok &= check(f"degenerate size {shape}, template {t.shape}",
                np.max(np.abs(c - d)))

print("\nALL PASS" if ok else "\nSOME CHECKS FAILED")
