import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import time

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

def filter_freq(f, H):
    F = dft2d(center(f))              #  center + forward DFT
    G = F * H                         #  element-wise multiply
    g = idft2d(G)                     #  inverse DFT
    return np.real(center(g))         #  un-center, take real part

