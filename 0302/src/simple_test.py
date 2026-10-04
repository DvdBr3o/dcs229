"""Self-tests for histogram_equalization.py"""
import numpy as np

from histogram_equalization import (
    L, compute_histogram, equalization_transform, equalize,
)

# Example 3.5 / Table 3.1: 3-bit (L=8), 64x64 image
NK = [790, 1023, 850, 656, 329, 245, 122, 81]


def textbook_image():
    """Image whose histogram is exactly Table 3.1."""
    pixels = np.concatenate([np.full(n, k, dtype=np.uint8) for k, n in enumerate(NK)])
    return pixels.reshape(64, 64)


def test_histogram_matches_table_3_1():
    img = textbook_image()
    h = compute_histogram(img, levels=8)
    assert h.tolist() == NK
    assert h.sum() == 64 * 64
    assert np.array_equal(h, np.bincount(img.ravel(), minlength=8))


def test_transform_matches_example_3_5():
    # Book: s = 1.33, 3.08, 4.55, 5.67, 6.23, 6.65, 6.86, 7.00 -> 1 3 5 6 6 7 7 7
    T = equalization_transform(compute_histogram(textbook_image(), 8), 8)
    assert T.tolist() == [1, 3, 5, 6, 6, 7, 7, 7]


def test_equalized_histogram_matches_example_3_5():
    # Book: 790@1, 1023@3, 850@5, 985@6 (656+329), 448@7 (245+122+81)
    out, _, _ = equalize(textbook_image(), levels=8)
    h_out = compute_histogram(out, levels=8)
    assert h_out.tolist() == [0, 790, 0, 1023, 0, 850, 985, 448]


def test_general_properties_on_random_image():
    rng = np.random.default_rng(1)
    img = rng.integers(0, L, size=(50, 70), dtype=np.uint8)
    out, T, h = equalize(img)

    assert out.shape == img.shape and out.dtype == np.uint8
    assert h.sum() == img.size
    assert np.all(np.diff(T.astype(int)) >= 0)      # T is monotonic
    assert T[-1] == L - 1                            # T(L-1) = L-1
    assert compute_histogram(out).sum() == img.size  # no pixels lost


def test_dark_image_gets_stretched():
    rng = np.random.default_rng(2)
    img = rng.integers(10, 60, size=(64, 64), dtype=np.uint8)
    out, _, _ = equalize(img)
    assert out.max() - out.min() > img.max() - img.min()


def test_constant_image_maps_to_max():
    img = np.full((16, 16), 42, dtype=np.uint8)
    out, _, _ = equalize(img)
    assert np.all(out == L - 1)


if __name__ == "__main__":
    tests = [f for name, f in sorted(globals().items()) if name.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\nAll {len(tests)} tests passed.")