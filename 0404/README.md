# Project 04-04: Highpass Filtering Using a Lowpass Image

## Requirements

**(a)** Subtract your image in Project 04-03(b) from the original to obtain a sharpened image, as in Eq. (4.4-14). You will note that the resulting image does not resemble the Gaussian highpass results in Fig. 4.26. Explain why this is so.

**(b)** Adjust the variance of your Gaussian lowpass filter until the result obtained by image subtraction looks similar to Fig. 4.26(c). Explain your result.

The 2D Fourier transform is our own implementation (Project 04-01), without `np.fft`.

## File organization

```
0404/
├── main.typ   
├── README.md
├── requirements.txt
├── data/
│   └── Fig0418.jpeg          # test image
├── results/                  # output images for Fig0418.jpeg
├── src/
│   ├── dft.py                # our 2D DFT 
│   ├── gaussian_filter.py    # gaussian_lowpass 
│   ├── utils.py              # load_image(), save_fig(), save_image() 
│   ├── main.py               # parts (a) and (b)
│   └── extra.py              # extension experiments
└── test/                     # extra test images and their results
    ├── test_1.bmp
    ├── test_2_results.bmp
    ├── test_1_results/
    └── test_2_results/
```

`dft.py`, `gaussian_filter.py` and `utils.py` are copies of the 04-03 files, so this folder does not depend on any other folder.

## How to run

```bash
pip install -r requirements.txt
python src/main.py      # required results
python src/extra.py     # extensions
```

Run from the `0404/` folder. The image `Fig0418.jpeg` comes from the textbook and is not included here.

## Outputs (in `results/`)

| File | Made by | Content |
|---|---|---|
| `fig01_0404_a.png` | `main.py` | part (a): original, lowpass, and f - lowpass |
| `fig02_0404_sigma15.png` | `main.py` | part (b): sigma = 15, two display styles |
| `fig03_0404_sigma30.png` | `main.py` | part (b): sigma = 30, two display styles |
| `fig04_0404_sigma80.png` | `main.py` | part (b): sigma = 80, two display styles |
| `ext_energy.png` | `extra.py` | fraction of image energy kept by the highpass vs. sigma |
| `ext_highboost.png` | `extra.py` | high-boost filtering with A = 1, 1.5, 2 |

## Extra test images (`test/`)

The same pipeline was also run on other test images. Each `test_N_results/` folder holds the same set of output files as `results/`, produced for that image.

## Extensions (`extra.py`)

1. **Equivalence check:** `f - lowpass` gives the same image as filtering with `1 - H` (printed difference should be around 1e-11).
2. **Faster sigma sweep:** the forward DFT is computed once and reused for every sigma.
3. **Energy kept:** a number showing how much of the image remains after the highpass, for each sigma.
4. **High-boost filtering:** `A·f - lowpass` with A = 1, 1.5, 2.
5. **Other image sizes:** the same equivalence check on a non-square, odd-sized crop.

## Notes

- Fig. 4.26 uses D0 = 15, 30, 80. In our filter, sigma plays the same role as D0, so Fig. 4.26(c) corresponds to a large sigma (about 80).
- A larger sigma leaves only the finest detail in `f - lowpass` (thin, faint edges on a dark background).
- The difference image has negative values, so it is shown two ways: min-max scaled, and with negatives clipped to black.
