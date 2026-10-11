import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import time

# ---------- DFT package ----------
def dft_matrix(N):
    n = np.arange(N)
    k = n.reshape(N, 1)
    return np.exp(-2j * np.pi * k * n / N)

def dft2d(f):
    M, N = f.shape
    return dft_matrix(M) @ f @ dft_matrix(N).T

def idft2d(F):
    M, N = F.shape
    return np.conj(dft2d(np.conj(F))) / (M * N)

def center(f):
    M, N = f.shape
    x, y = np.indices((M, N))
    return f * (-1.0) ** (x + y)

def spectrum(F):
    S = np.log(1 + np.abs(F))
    return 255 * S / S.max()

#Speed test
test = np.random.rand(256, 256)
t = time.time()
dft2d(test)
print("Time:", time.time() - t)

#  Real image 
img = Image.open("Fig0418.jpeg").convert("L")
f = np.array(img, dtype=np.float64)
print(f.shape, f.min(), f.max())

F = dft2d(f)
f_back = np.real(idft2d(F))
print("Round-trip error:", np.max(np.abs(f_back - f)))

F = dft2d(center(f))

plt.figure(figsize=(10, 5))
plt.subplot(1, 2, 1); plt.imshow(f, cmap="gray"); plt.title("Original")
plt.subplot(1, 2, 2); plt.imshow(spectrum(F), cmap="gray"); plt.title("Centered spectrum")


M, N = f.shape
print("Average from spectrum:", F[M//2, N//2].real / (M * N))
print("Average from image:   ", f.mean())


plt.show()
