"""Correlation by the DFT (Section 4.6.6 / Example 4.11).

    g(x, y) = IDFT{ F(u, v) * conj(T(u, v)) }

The textbook uses this exactly as written.  When the image has a large mean
(the gray characters test pattern, mean ~200), the DC term of F dominates and
the plain correlation is maximised wherever a bright window simply overlaps
many bright pixels -- not necessarily at the template.  Removing the mean of
the template (and, for a fully scale-free score, of the window) removes that
term; this is the usual *normalized* cross-correlation.  Both are provided.
"""
import numpy as np

from dft import dft2d, idft2d


def pad_to(f, shape):
    """Zero-pad (bottom/right) f to the given (P, Q) shape; return the copy."""
    P, Q = shape
    M, N = f.shape
    if (P, Q) == (M, N):
        return f.astype(np.float64, copy=True)
    if P < M or Q < N:
        raise ValueError(f"pad_to: target shape {shape} is smaller than image {f.shape}")
    g = np.zeros((P, Q), dtype=np.float64)
    g[:M, :N] = f
    return g


def circular_correlate(f, tpl, pad, subtract_mean=False):
    """Cross-correlation of f with tpl after zero padding to `pad`.

    No centering (-1)^(x+y) is applied: correlation is not a shift-invariant
    filtering operation, so the origin stays at (0, 0) of the padded arrays.
    """
    P, Q = pad
    fp = pad_to(f, pad)
    tp = pad_to(tpl, pad)
    if subtract_mean:
        #  Remove the DC term of the template (and image): the raw correlation
        #  of a bright image is otherwise dominated by the overlap of bright
        #  regions and can peak away from the true match.
        tp[: tpl.shape[0], : tpl.shape[1]] -= tpl.mean()
        fp = fp - fp.mean()
    return np.real(idft2d(dft2d(fp) * np.conj(dft2d(tp))))


def linear_correlate(f, tpl, pad, subtract_mean=False):
    """Exact linear correlation; pad must satisfy P >= M + C - 1, Q >= N + D - 1."""
    M, N = f.shape
    C, D = tpl.shape
    if pad[0] < M + C - 1 or pad[1] < N + D - 1:
        raise ValueError(
            f"pad {pad} too small for linear correlation of {f.shape} with {tpl.shape}"
        )
    return circular_correlate(f, tpl, pad, subtract_mean)


def find_target(corr):
    """Location (x, y) of the maximum of the correlation array.

    In this convention corr(i, j) = sum_{a,b} f(i + a, j + b) * tpl(a, b), so
    the peak is where the template's top-left corner lands -- the same point
    the textbook reads out of the extended image.
    """
    idx = int(np.argmax(corr))
    return idx // corr.shape[1], idx % corr.shape[1]


def match_at(f, tpl, loc, subtract_mean=False):
    """Cut the tpl-sized window out of f whose top-left corner is `loc`."""
    C, D = tpl.shape
    i, j = loc
    win = f[i:i + C, j:j + D].astype(np.float64, copy=True)
    if subtract_mean:
        win = win - win.mean()
    return win
