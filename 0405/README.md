# Project 04-05: Correlation in the Frequency Domain

## Requirements

Implement 2D correlation by the DFT (Section 4.6.6) and repeat **Example 4.11**
(Fig. 4.41): localise the template Fig. 4.41(b) inside the image Fig. 4.41(a)
with

    g(x, y) = IDFT{ F(u, v) * conj(T(u, v)) },

and show the correlation function together with the grey-level profile through
its highest value.

The 2D Fourier transform is our own implementation (Project 04-01), without
`np.fft`.

## File organization

```
0405/
├── main.typ                  # report
├── README.md
├── requirements.txt
├── data/
│   ├── Fig0441a.jpg          # Fig. 4.41(a): the "UTK" block
│   ├── Fig0441b.png          # Fig. 4.41(b): the "T" template
│   ├── example_a.png         # 256x256 image in the layout of Example 4.11
│   └── example_b.png         # the "T" template, copied from example_a.png
├── results/                  # output figures of the required run
├── src/
│   ├── dft.py                # our 2D DFT: dft2d, idft2d, center, spectrum
│   ├── correlation.py        # pad_to, circular/linear_correlate, find_target
│   ├── utils.py              # load_image, save_fig, save_image
│   ├── make_example_image.py # builds data/example_a.png and example_b.png
│   ├── main.py               # required part: detect the template
│   └── extra.py              # extension experiments
└── test/
    ├── testing_correlation.py # checks that the correlation is correct
    ├── run_tests.py           # same pipeline on extra test images
    ├── test_1.bmp             # extra test image 1
    ├── test_2.bmp             # extra test image 2
    ├── test_1_results/        # outputs for test image 1
    └── test_2_results/        # outputs for test image 2
```

## How to run

```bash
pip install -r requirements.txt
python src/make_example_image.py   # 1. build the Example 4.11 materials
python test/testing_correlation.py # 2. check the correlation
python src/main.py                 # 3. required results
python src/extra.py                # 4. extensions
python test/run_tests.py           # 5. extra test images
```

Run from the `0405/` folder.

## Notes on the material

The figures shipped with the supplementary document are a *crop* of Fig. 4.41(a):
`Fig0441a.jpg` shows only the "UTK" block and `Fig0441b.png` is the "T" glyph
itself (44 x 49, not the 38 x 42 of the example, and not placed in the middle
of the image). `make_example_image.py` re-arranges those two crops into the
layout of the example — a 256 x 256 image with the template copy near the
middle — and also copies `Fig0441a.jpg` / `Fig0441b.png` unchanged, so both
are correlated in `main.py`.

## Outputs (in `results/`)

| File                          | Content                                                    |
| ----------------------------- | ---------------------------------------------------------- |
| `fig02_0405_padded.png`       | Example 4.11 layout: padded image and padded template       |
| `fig_ex_c_padded.png`         | Fig. 4.41(c)/(d): the two zero-padded functions             |
| `fig_ex_e_corr.png`           | Fig. 4.41(e): the correlation function as an image          |
| `fig_ex_f_profile.png`        | Fig. 4.41(f): grey-level profile through the highest value  |
| `fig_ex_a_detect.png`         | image, template and the window found by the correlation     |
| `fig_ex_b_overlay.png`        | image with the detected location marked                     |
| `fig_sup_*`                   | the same set for the document figures                       |
| `ext2_speed.png`              | correlation time vs. image size                             |
| `ext3_normalized.png`         | plain vs. mean-removed correlation on a bright image        |
| `ext4_two_templates.png`      | the same code locating a second template                    |
| `0405_bench.txt`              | raw text output                                             |

The same set of detection files is produced for the extra test images and stored
in `test/test_1_results/` and `test/test_2_results/`.

## Extensions (`extra.py`)

1. **Direct vs. DFT correlation**: the definition and the DFT agree to
   `6e-07` (absolute, on values of order `2e7`); the DFT is ~12x faster.
2. **Scaling**: time vs. image size, log-log slope ~1.9 (two transforms).
3. **Normalised correlation**: on a bright background the plain correlation
   peaks at the corner, the mean-removed one still finds the object.
4. **Other templates**: the same code locates the "K" as well as the "T".
5. **Non-square / odd sizes**: no padding to a power of two is needed.

## Exercises 4.22 / 4.23 (in `main.py`)

- **4.23**: taking the conjugate of the *other* transform mirrors the
  correlation about the pad centre; the two peaks add up to the pad size
  (verified numerically), and the peak value is identical.
- **4.22**: dropping the `(-1)^u` factor moves the peak to the top of the array
  and reduces its value to 6.6% of the correct one — it no longer detects the
  template.

## Notes

- Correlation is *not* a shift-invariant filtering operation, so no `(-1)^(x+y)`
  centering is applied; the DFT runs directly on the zero-padded arrays and the
  peak is where the template's top-left corner lands.
- The minimum padding of Example 4.11 is `P = A + C - 1`, `Q = B + D - 1`
  (293 x 297 for the example); with exactly that padding the wrapped tail of the
  linear correlation reappears in the last row/column, which is harmless because
  only the peak matters.
