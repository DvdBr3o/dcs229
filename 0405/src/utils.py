import os

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt


def _root(module_file):
    """The project folder of the calling module (src/../)."""
    return os.path.dirname(os.path.dirname(os.path.abspath(module_file)))


def results_dir(module_file):
    d = os.path.join(_root(module_file), "results")
    os.makedirs(d, exist_ok=True)
    return d


def data_dir(module_file):
    return os.path.join(_root(module_file), "data")


def load_image(name, module_file):
    """Load data/<name> as a grayscale float64 array (0..255)."""
    path = os.path.join(data_dir(module_file), name)
    return np.array(Image.open(path).convert("L"), dtype=np.float64)


def save_fig(name, module_file, out_dir=None):
    """Save the current matplotlib figure."""
    d = out_dir or results_dir(module_file)
    plt.savefig(os.path.join(d, name), dpi=150, bbox_inches="tight")


def save_image(arr, name, module_file, out_dir=None):
    """Clip to 0-255 and save a raw grayscale image (no axes or titles)."""
    d = out_dir or results_dir(module_file)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(d, name))
