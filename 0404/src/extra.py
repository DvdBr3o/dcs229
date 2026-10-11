import time
from dft import *
from gaussian_filter import *
from utils import *


f = load_image()
M, N = f.shape
sigma = 30   # 04-03(b)


def best_time(fn, repeats=3):
    """Run fn several times and keep the fastest time (reduces timing noise)."""
    best = float("inf")
    for _ in range(repeats):
        s = time.time()
        fn()
        best = min(best, time.time() - s)
    return best


#  Extension 1:  "f - lowpass" ?= highpass filter 1 - H
H = gaussian_lowpass(M, N, sigma)
hp_subtract = f - filter_freq(f, H)
hp_direct = filter_freq(f, 1 - H)
print("f - lowpass vs. (1 - H) filter, max difference:", np.max(np.abs(hp_subtract - hp_direct)))


#  Extension 2: faster sigma sweep (compute the forward DFT once) 
sigmas = [5, 10, 15, 20, 30, 50, 80, 100]

def sweep_naive():
    for s in sigmas:
        f - filter_freq(f, gaussian_lowpass(M, N, s))

def sweep_cached():
    Fc = dft2d(center(f))                               
    for s in sigmas:
        np.real(center(idft2d(Fc * (1 - gaussian_lowpass(M, N, s)))))

t_naive = best_time(sweep_naive)
t_cached = best_time(sweep_cached)
print(f"sigma sweep: naive {t_naive:.3f}s, cached {t_cached:.3f}s, speedup {t_naive / t_cached:.2f}x")


#  Extension 3: image remaining in the highpass result
Fc = dft2d(center(f))
total = np.sum((f - f.mean()) ** 2)
kept = []
for s in sigmas:
    hp = np.real(center(idft2d(Fc * (1 - gaussian_lowpass(M, N, s)))))
    kept.append(np.sum(hp ** 2) / total)
    print(f"sigma = {s:3d}: fraction of energy kept = {kept[-1]:.4f}")

plt.figure(figsize=(6, 4))
plt.plot(sigmas, kept, "o-")
plt.xlabel("sigma"); plt.ylabel("fraction of energy kept"); plt.grid(True)
save_fig("ext_energy.png")
plt.close()


#  Extension 4: high-boost filtering, A*f - lowpass 
g = filter_freq(f, H)
plt.figure(figsize=(15, 5))
for i, A in enumerate([1.0, 1.5, 2.0], 1):
    plt.subplot(1, 3, i)
    plt.imshow(np.clip(A * f - g, 0, 255), cmap="gray", vmin=0, vmax=255)
    plt.title(f"A = {A}")
save_fig("ext_highboost.png")
plt.close()


#  Extension 5: non-square, odd-sized image
crop = f[: M - 17, : N - 40]
Hc = gaussian_lowpass(*crop.shape, sigma)
err = np.max(np.abs((crop - filter_freq(crop, Hc)) - filter_freq(crop, 1 - Hc)))
print("crop size", crop.shape, "| f - lowpass vs. (1 - H) filter, max difference:", err)
print("done")
