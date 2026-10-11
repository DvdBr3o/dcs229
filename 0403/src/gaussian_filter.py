import numpy as np

def gaussian_lowpass(M, N, sigma, center_uv=None):
    if center_uv is None:
        center_uv = (M // 2, N // 2)  
    u0, v0 = center_uv

    u, v = np.indices((M, N))
    D2 = (u - u0)**2 + (v - v0)**2
    H = np.exp(-D2 / (2 * sigma**2))
    return H