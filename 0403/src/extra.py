import time
from dft import *
from gaussian_filter import *
from utils import *

f = load_image()
M, N = f.shape


def best_time(fn, *args, repeats=3):
    best = float("inf")
    for _ in range(repeats):
        s = time.time()
        fn(*args)
        best = min(best, time.time() - s)
    return best


#  Extension 1: own radix-2 FFT vs matrix DFT 
def fft_last_axis(x):
    n = x.shape[-1]
    if n == 1:
        return x.astype(complex)
    even = fft_last_axis(x[..., 0::2])
    odd = fft_last_axis(x[..., 1::2])
    w = np.exp(-2j * np.pi * np.arange(n // 2) / n)   
    return np.concatenate([even + w * odd, even - w * odd], axis=-1)

def fft2d(a):
    return fft_last_axis(fft_last_axis(a).T).T            # rows, then columns

t = np.random.rand(64, 128)
print("FFT vs matrix DFT error:", np.max(np.abs(fft2d(t) - dft2d(t))))

sizes = [64, 128, 256, 512, 1024, 2048]
t_mat, t_fft = [], []
for n in sizes:
    a = np.random.rand(n, n)
    t_mat.append(best_time(dft2d, a))
    t_fft.append(best_time(fft2d, a))
    print(f"{n}: matrix {t_mat[-1]:.4f}s  fft {t_fft[-1]:.4f}s  matrix/fft = {t_mat[-1] / t_fft[-1]:.2f}")

print("slope matrix:", np.polyfit(np.log(sizes), np.log(t_mat), 1)[0])
print("slope fft:   ", np.polyfit(np.log(sizes), np.log(t_fft), 1)[0])

plt.figure(figsize=(6, 4))
plt.loglog(sizes, t_mat, "o-", label="matrix DFT")
plt.loglog(sizes, t_fft, "s-", label="own radix-2 FFT")
plt.xlabel("image size n (n x n)"); plt.ylabel("time (s)"); plt.legend(); plt.grid(True, which="both")
save_fig("ext1_speed.png")
plt.close()


#  Extension 2: ideal vs Butterworth vs Gaussian 
u, v = np.indices((M, N))
D = np.sqrt((u - M // 2) ** 2 + (v - N // 2) ** 2)
D0 = 30

filters = {"Ideal": (D <= D0).astype(float),
           "Butterworth (n=2)": 1 / (1 + (D / D0) ** 4),
           "Gaussian": gaussian_lowpass(M, N, D0)}

plt.figure(figsize=(15, 5))
for i, (name, H) in enumerate(filters.items(), 1):
    plt.subplot(1, 3, i)
    plt.imshow(filter_freq(f, H), cmap="gray", vmin=0, vmax=255)
    plt.title(f"{name}, D0={D0}")
save_fig("ext2_filter_types.png")
plt.close()


#Extension 3: cached spectrum in a sigma sweep
sigmas = [5, 10, 15, 20, 30, 50, 80, 100]

def sweep_naive():
    for s in sigmas:
        filter_freq(f, gaussian_lowpass(M, N, s))

def sweep_cached():
    Fc = dft2d(center(f))                                 # forward DFT only once
    for s in sigmas:
        np.real(center(idft2d(Fc * gaussian_lowpass(M, N, s))))   # same final steps as filter_freq

t_naive = best_time(sweep_naive)
t_cached = best_time(sweep_cached)
print(f"sigma sweep: naive {t_naive:.3f}s, cached {t_cached:.3f}s, speedup {t_naive / t_cached:.2f}x")

# same result?
Fc = dft2d(center(f))
g1 = filter_freq(f, gaussian_lowpass(M, N, 30))
g2 = np.real(center(idft2d(Fc * gaussian_lowpass(M, N, 30))))
print("cached vs naive max difference:", np.max(np.abs(g1 - g2)))
print("done")
