# Project 04-03: Lowpass Filtering

## Requirements

**(a)** Implement the Gaussian lowpass filter in Eq. (4.3-7). You must be able to specify the size, M x N, of the resulting 2D function. In addition, you must be able to specify where the 2D location of the center of the Gaussian function is.

**(b)** Download Fig. 4.11(a) [this image is the same as Fig. 4.18(a)] and lowpass filter it to obtain Fig. 4.18(c).

The 2D Fourier transform is implemented from scratch (Project 04-01), without `np.fft`.

## File organization

```
0403/
├── main.typ                  # report
├── README.md
├── requirements.txt
├── data/
│   └── Fig0418.jpeg           # test image
├── results/                  # output images of the required run and extensions
├── src/
│   ├── dft.py                # our 2D DFT: dft2d, idft2d, center, spectrum, filter_freq
│   ├── utils.py              # I/O helpers: load_image, save_fig, save_image 
│   ├── gaussian_filter.py    # (a) gaussian_lowpass(M, N, sigma, center_uv)
│   ├── main.py               # (b) filters the image and saves the results
│   └── extra.py              # extension experiments
└── test/
    ├── testing_dft.py        # checks that the DFT is correct
    ├── test1_pic.bmp         # extra test image 1
    ├── test2_pic.bmp         # extra test image 2
    ├── test1_results/        # outputs for test image 1
    └── test2_results/        # outputs for test image 2

## How to run

```bash
pip install -r requirements.txt
python test/testing_dft.py    # 1. check the DFT
python src/main.py            # 2. required results
python src/extra.py           # 3. extensions
```

Run from the `0403/` folder. The image `Fig0418.bmp` comes from the textbook and is not included here.

## Outputs (in `results/`)

| File                                                | Made by      | Content                                     |
| --------------------------------------------------- | ------------ | ------------------------------------------- |
| `fig01_0403_H_plot.png`                           | `main.py`  | the Gaussian filter H(u,v)                  |
| `fig02_0403_lowpass_comparison.png`               | `main.py`  | original vs. lowpass result                 |
| `fig03-07_0403_lowpass_sigma{5,15,30,80,230}.png` | `main.py`  | result for each sigma                       |
| `ext1_speed.png`                                  | `extra.py` | matrix DFT vs. our FFT, time vs. image size |
| `ext2_filter_types.png`                           | `extra.py` | ideal vs. Butterworth vs. Gaussian lowpass  |

The same set of files is also produced for the extra test images and stored in
`test/test1_results/` and `test/test2_results/`.

## Extensions (`extra.py`)

1. **Own radix-2 FFT**, compared with the matrix DFT for speed.
2. **Ideal vs. Butterworth vs. Gaussian** lowpass at the same cutoff.
3. **Cached spectrum**: in a sigma sweep, the forward DFT is computed once and reused.

## Notes

- A smaller sigma gives a more blurred image.
- The filter center defaults to `(M//2, N//2)`, which matches the centered spectrum.
- Image padding is ignored, as allowed by the project description.
