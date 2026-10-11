import os
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the project folder
RESULTS = os.path.join(ROOT, "results")
os.makedirs(RESULTS, exist_ok=True)


def load_image(name="Fig0418.jpeg"):
    """Load data/<name> as a grayscale float64 array."""
    path = os.path.join(ROOT, "data", name)
    return np.array(Image.open(path).convert("L"), dtype=np.float64)


def save_fig(name):
    """Save the current matplotlib figure into results/."""
    plt.savefig(os.path.join(RESULTS, name), dpi=150, bbox_inches="tight")


def save_image(arr, name):
    """Clip to 0-255 and save a raw image (no axes or titles) into results/."""
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(RESULTS, name))
