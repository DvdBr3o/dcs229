from dft import *
from gaussian_filter import *
from utils import *

f = load_image()
M, N = f.shape

H = gaussian_lowpass(M, N, sigma=30)
print(H.shape)
print(H[M//2, N//2])
print(H[0, 0])

plt.imshow(H, cmap="gray")
plt.title("Gaussian lowpass H(u,v)")
save_fig("fig01_0403_H_plot.png")
plt.show()

g = filter_freq(f, H)
plt.figure(figsize=(10, 5))
plt.subplot(1, 2, 1); plt.imshow(f, cmap="gray", vmin=0, vmax=255); plt.title("Original")
plt.subplot(1, 2, 2); plt.imshow(g, cmap="gray", vmin=0, vmax=255); plt.title("Lowpass, sigma=30")
save_fig("fig02_0403_lowpass_comparison.png")
plt.show()

fig_idx = 3
sigma_list = [5, 15, 30, 80, 230]
for sigma in sigma_list:
    g = filter_freq(f, gaussian_lowpass(M, N, sigma))
    fname = f"fig{fig_idx:02d}_0403_lowpass_sigma{sigma}.png"
    save_image(g, fname)
    fig_idx += 1