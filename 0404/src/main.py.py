from dft import *
from gaussian_filter import *
from utils import *
import numpy as np

f = load_image()
M, N = f.shape

def scale(a):
    return 255 * (a - a.min()) / (a.max() - a.min())

# Part_a: subtract the 04‑03(b) lowpass result
fig_idx = 1
sigma_a = 30   # as 04‑03(b)
g = filter_freq(f, gaussian_lowpass(M, N, sigma_a))
hp = f - g


plt.figure(figsize=(15, 5))
plt.subplot(1, 3, 1); plt.imshow(f, cmap="gray", vmin=0, vmax=255); plt.title("Original f")
plt.subplot(1, 3, 2); plt.imshow(g, cmap="gray", vmin=0, vmax=255); plt.title(f"Lowpass g, sigma={sigma_a}")
plt.subplot(1, 3, 3); plt.imshow(np.clip(hp, 0, 255), cmap="gray", vmin=0, vmax=255); plt.title("f - g")
save_fig(f"fig{fig_idx:02d}_0404_a.png")
plt.show()
fig_idx += 1

#  Part_b: varing sigma
for s in [15, 30, 80]:
    hp = f - filter_freq(f, gaussian_lowpass(M, N, s))
    

    plt.figure(figsize=(10, 5))
    plt.subplot(1, 2, 1); plt.imshow(scale(hp), cmap="gray"); plt.title(f"min‑max scaled, sigma={s}")
    plt.subplot(1, 2, 2); plt.imshow(np.clip(hp, 0, 255), cmap="gray", vmin=0, vmax=255); plt.title(f"negatives clipped, sigma={s}")
    save_fig(f"fig{fig_idx:02d}_0404_sigma{s}.png")
    plt.show()
    fig_idx += 1
