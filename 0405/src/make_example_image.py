"""Build the Example 4.11 materials.

Example 4.11 uses a 256 x 256 image with a 38 x 42 template that is an exact
copy of a piece of the image, and the template sits in the middle of the
image.  The figures shipped with the supplementary document (4.41a.jpg /
4.41b.png) are a *cropped* version of Fig. 4.41(a): 4.41a.jpg shows only the
"UTK" block and 4.41b.png is the "T" glyph itself (44 x 49).

We reuse those two crops but rearrange them into the layout of the example:

    data/example_a.png  -- 256 x 256 black canvas with the UTK block centred,
                           so that the "T" occupies the middle of the image;
    data/example_b.png  -- the "T" template (a copy of part of the image).

    python src/make_example_image.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from PIL import Image

from utils import data_dir

HERE = os.path.abspath(__file__)

#  The "T" is at (106, 102) of Fig0441a.jpg (row, col); its size is 44 x 49.
T_ROW, T_COL = 106, 102
T_H, T_W = 44, 49
A = B = 256


def main():
    src = np.array(Image.open(os.path.join(data_dir(HERE), "Fig0441a.jpg")).convert("L"),
                   dtype=np.float64)

    #  The UTK block around the T, with a generous margin.
    r0, c0 = 95, 85
    r1, c1 = 160, 180
    block = src[r0:r1, c0:c1]
    tpl = src[T_ROW:T_ROW + T_H, T_COL:T_COL + T_W]

    canvas = np.zeros((A, B), dtype=np.float64)
    br, bc = block.shape
    top = (A - br) // 2
    left = (B - bc) // 2
    canvas[top:top + br, left:left + bc] = block

    Image.fromarray(canvas.astype(np.uint8)).save(os.path.join(data_dir(HERE), "example_a.png"))
    Image.fromarray(tpl.astype(np.uint8)).save(os.path.join(data_dir(HERE), "example_b.png"))

    loc = (top + (T_ROW - r0), left + (T_COL - c0))
    print(f"image    {canvas.shape}  -> data/example_a.png")
    print(f"template {tpl.shape}  -> data/example_b.png")
    print(f"peak (top-left corner of the template): {loc}")
    print("done")


if __name__ == "__main__":
    main()
