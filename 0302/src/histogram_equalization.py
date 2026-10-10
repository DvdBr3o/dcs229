import os
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

L = 256

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
IMAGE_PATH = os.path.join(BASE_DIR, "fig0308.jpg")


# (a) Histogram calculation
def compute_histogram(img, levels=L):
    """h(r_k) = n_k: number of pixels with intensity r_k."""
    h = np.zeros(levels, dtype=np.int64)
    for v in img.ravel():
        h[v] += 1
    return h


# (b) Histogram equalization
def equalization_transform(hist, levels=L):
    """
    s_k = T(r_k) = (L-1) * sum_{j<=k} p_r(r_j)
    """
    p = hist / hist.sum()
    cdf = np.cumsum(p)
    T = np.round((levels - 1) * cdf).astype(np.uint8)

    return T


def equalize(img, levels=L):
    hist = compute_histogram(img, levels)
    T = equalization_transform(hist, levels)
    out = T[img]

    return out, T, hist


def main():

    # Load image
    img = np.array(
        Image.open(IMAGE_PATH).convert("L"),
        dtype=np.uint8
    )
    # Equalize
    out, T, h_in = equalize(img)
    # Histogram of equalized image
    h_out = compute_histogram(out)
    k = np.arange(L)
    fig, ax = plt.subplots(2, 3, figsize=(15, 8.5))

    # Original image
    ax[0, 0].imshow(
        img,
        cmap="gray",
        vmin=0,
        vmax=255
    )
    ax[0, 0].set_title("(1) Original image")

    # Original histogram
    ax[0, 1].bar(
        k,
        h_in,
        width=1.0,
        color="k"
    )
    ax[0, 1].set_title("(2) Histogram of original")

    # Transformation function
    ax[0, 2].plot(k, T, "k")
    ax[0, 2].plot(
        k,
        k,
        "r--",
        lw=0.8,
        label="identity"
    )
    ax[0, 2].set_title(
        "(3) Transformation function s = T(r)"
    )
    ax[0, 2].legend()

    # Equalized image
    ax[1, 0].imshow(
        out,
        cmap="gray",
        vmin=0,
        vmax=255
    )
    ax[1, 0].set_title("(4) Equalized image")

    # Equalized histogram
    ax[1, 1].bar(
        k,
        h_out,
        width=1.0,
        color="k"
    )
    ax[1, 1].set_title("(5) Histogram of equalized")

    # Log-scale comparison
    ax[1, 2].semilogy(
        k,
        np.maximum(h_in, 1),
        "b",
        lw=1,
        label="original"
    )

    ax[1, 2].semilogy(
        k,
        np.maximum(h_out, 1),
        "r",
        lw=1,
        label="equalized"
    )

    ax[1, 2].set_title(
        "(extra) Both histograms, log scale"
    )
    ax[1, 2].legend()

    for a in (ax[0, 1], ax[1, 1], ax[1, 2]):
        a.set_xlim(0, 255)
        a.set_xlabel("intensity r_k")
        a.set_ylabel("n_k")

    ax[0, 2].set_xlim(0, 255)
    ax[0, 2].set_ylim(0, 255)
    ax[0, 2].set_xlabel("input r")
    ax[0, 2].set_ylabel("output s")

    for a in (ax[0, 0], ax[1, 0]):
        a.axis("off")

    plt.tight_layout()

    plt.savefig(
        os.path.join(BASE_DIR, "results.png"),
        dpi=150
    )

    Image.fromarray(out).save(
        os.path.join(BASE_DIR, "equalized.png")
    )

    plt.show()


if __name__ == "__main__":
    main()