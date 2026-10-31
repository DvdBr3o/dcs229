"""亚洲人脸肤色分割演示。

用法：手动修改下面「演示参数」里的 IMAGE_PATH / SPLIT 常量，然后运行
``python project3/colorspace_split.py``。每次只保留一个常量，其余候选写在注释里。

推荐组合：
    asian_1.png  -> YCbCrEllipseSplit()
    asian_6.png  -> YCbCrBoxSplit()
    asian_13.png -> HSVSplit()
"""

from abc import ABC, abstractmethod
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


# ---------------------------------------------------------------------------
# 颜色空间转换
# ---------------------------------------------------------------------------


def _as_float_rgb(img: np.ndarray) -> np.ndarray:
    """返回 (H, W, 3) 的 float32 RGB 数组。"""
    rgb = np.asarray(img)
    if rgb.ndim == 2:
        rgb = np.repeat(rgb[..., None], 3, axis=-1)
    if rgb.shape[-1] == 4:
        rgb = rgb[..., :3]
    if rgb.shape[-1] != 3:
        raise ValueError(f"expected 3 or 4 channels, got shape {rgb.shape}")
    return rgb.astype(np.float32, copy=False)


def rgb_to_ycbcr(img: np.ndarray) -> np.ndarray:
    """BT.601 全范围 YCbCr。"""
    rgb = _as_float_rgb(img)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b
    return np.stack((y, cb, cr), axis=-1)


def rgb_to_hsv(img: np.ndarray) -> np.ndarray:
    """HSV，色相为角度 [0, 360)，饱和度/明度为 [0, 1]。"""
    rgb = _as_float_rgb(img) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    maximum = rgb.max(axis=-1)
    minimum = rgb.min(axis=-1)
    delta = maximum - minimum

    hue = np.zeros_like(maximum)
    nonzero = delta > 1e-8
    red = nonzero & (maximum == r)
    green = nonzero & (maximum == g)
    blue = nonzero & (maximum == b)
    hue[red] = ((g[red] - b[red]) / delta[red]) % 6.0
    hue[green] = (b[green] - r[green]) / delta[green] + 2.0
    hue[blue] = (r[blue] - g[blue]) / delta[blue] + 4.0
    hue *= 60.0

    saturation = np.zeros_like(maximum)
    np.divide(delta, maximum, out=saturation, where=maximum > 1e-8)
    return np.stack((hue, saturation, maximum), axis=-1)


def _srgb_to_linear(channel: np.ndarray) -> np.ndarray:
    return np.where(
        channel <= 0.04045,
        channel / 12.92,
        ((channel + 0.055) / 1.055) ** 2.4,
    )


def rgb_to_lab(img: np.ndarray) -> np.ndarray:
    """CIELAB（D65 白点）。"""
    rgb = _as_float_rgb(img) / 255.0
    linear = _srgb_to_linear(rgb)
    r, g, b = linear[..., 0], linear[..., 1], linear[..., 2]
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    x /= 0.95047
    y /= 1.00000
    z /= 1.08883

    epsilon = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    fx = np.where(x > epsilon, np.cbrt(x), (kappa * x + 16.0) / 116.0)
    fy = np.where(y > epsilon, np.cbrt(y), (kappa * y + 16.0) / 116.0)
    fz = np.where(z > epsilon, np.cbrt(z), (kappa * z + 16.0) / 116.0)

    lightness = 116.0 * fy - 16.0
    a = 500.0 * (fx - fy)
    bb = 200.0 * (fy - fz)
    return np.stack((lightness, a, bb), axis=-1)


def rgb_to_chromaticity(img: np.ndarray) -> np.ndarray:
    """归一化 RGB 色度 (r, g) = (R, G) / (R + G + B)。"""
    rgb = _as_float_rgb(img)
    total = rgb.sum(axis=-1, keepdims=True)
    return np.divide(rgb[..., :2], total, out=np.zeros_like(rgb[..., :2]), where=total > 1e-6)


# ---------------------------------------------------------------------------
# 分割判据
# ---------------------------------------------------------------------------


class Split(ABC):
    @abstractmethod
    def mask(self, img: np.ndarray) -> np.ndarray: ...


class SphereSplit(Split):
    """RGB 欧氏球：||p - avg|| < thres。"""

    def __init__(self, avg: np.ndarray | None = None, thres: float = 100) -> None:
        self.avg = avg
        self.thres = thres

    def mask(self, img: np.ndarray) -> np.ndarray:
        rgb = _as_float_rgb(img)
        avg = self.avg if self.avg is not None else rgb.mean(axis=(0, 1))
        return np.linalg.norm(rgb - avg, axis=-1) < self.thres


class YCbCrBoxSplit(Split):
    """YCbCr 矩形框。"""

    def __init__(
        self,
        cb_range: tuple[float, float] = (77, 127),
        cr_range: tuple[float, float] = (133, 173),
        y_range: tuple[float, float] = (40, 255),
    ) -> None:
        self.cb_range = cb_range
        self.cr_range = cr_range
        self.y_range = y_range

    def mask(self, img: np.ndarray) -> np.ndarray:
        y, cb, cr = np.moveaxis(rgb_to_ycbcr(img), -1, 0)
        return (
            (y >= self.y_range[0])
            & (y <= self.y_range[1])
            & (cb >= self.cb_range[0])
            & (cb <= self.cb_range[1])
            & (cr >= self.cr_range[0])
            & (cr <= self.cr_range[1])
        )


class YCbCrEllipseSplit(Split):
    """Cb/Cr 平面内的旋转椭圆。"""

    def __init__(
        self,
        center: tuple[float, float] = (110, 150),
        axes: tuple[float, float] = (26, 20),
        rotation: float = 15.0,
        y_range: tuple[float, float] = (30, 255),
    ) -> None:
        self.center = center
        self.axes = axes
        self.rotation = rotation
        self.y_range = y_range

    def mask(self, img: np.ndarray) -> np.ndarray:
        y, cb, cr = np.moveaxis(rgb_to_ycbcr(img), -1, 0)
        theta = np.deg2rad(self.rotation)
        cos_t, sin_t = np.cos(theta), np.sin(theta)
        dcb = cb - self.center[0]
        dcr = cr - self.center[1]
        u = cos_t * dcb + sin_t * dcr
        v = -sin_t * dcb + cos_t * dcr
        radius = (u / self.axes[0]) ** 2 + (v / self.axes[1]) ** 2
        return (radius <= 1.0) & (y >= self.y_range[0]) & (y <= self.y_range[1])


class HSVSplit(Split):
    """HSV 矩形框。"""

    def __init__(
        self,
        hue_range: tuple[float, float] = (0, 50),
        saturation_range: tuple[float, float] = (0.10, 0.75),
        value_range: tuple[float, float] = (0.20, 1.0),
    ) -> None:
        self.hue_range = hue_range
        self.saturation_range = saturation_range
        self.value_range = value_range

    def mask(self, img: np.ndarray) -> np.ndarray:
        hue, saturation, value = np.moveaxis(rgb_to_hsv(img), -1, 0)
        return (
            (hue >= self.hue_range[0])
            & (hue <= self.hue_range[1])
            & (saturation >= self.saturation_range[0])
            & (saturation <= self.saturation_range[1])
            & (value >= self.value_range[0])
            & (value <= self.value_range[1])
        )


class LabEllipseSplit(Split):
    """CIELAB a*/b* 平面内的旋转椭圆。"""

    def __init__(
        self,
        center: tuple[float, float] = (14, 18),
        axes: tuple[float, float] = (13, 13),
        rotation: float = 30.0,
        l_range: tuple[float, float] = (25, 100),
    ) -> None:
        self.center = center
        self.axes = axes
        self.rotation = rotation
        self.l_range = l_range

    def mask(self, img: np.ndarray) -> np.ndarray:
        lightness, a, bb = np.moveaxis(rgb_to_lab(img), -1, 0)
        theta = np.deg2rad(self.rotation)
        cos_t, sin_t = np.cos(theta), np.sin(theta)
        da = a - self.center[0]
        db = bb - self.center[1]
        u = cos_t * da + sin_t * db
        v = -sin_t * da + cos_t * db
        radius = (u / self.axes[0]) ** 2 + (v / self.axes[1]) ** 2
        return (radius <= 1.0) & (lightness >= self.l_range[0]) & (lightness <= self.l_range[1])


class ChromaticitySplit(Split):
    """归一化 RGB 矩形框。"""

    def __init__(
        self,
        r_range: tuple[float, float] = (0.33, 0.48),
        g_range: tuple[float, float] = (0.28, 0.40),
        min_sum: float = 30.0,
    ) -> None:
        self.r_range = r_range
        self.g_range = g_range
        self.min_sum = min_sum

    def mask(self, img: np.ndarray) -> np.ndarray:
        rgb = _as_float_rgb(img)
        r, g = np.moveaxis(rgb_to_chromaticity(rgb), -1, 0)
        return (
            (rgb.sum(axis=-1) >= self.min_sum)
            & (r >= self.r_range[0])
            & (r <= self.r_range[1])
            & (g >= self.g_range[0])
            & (g <= self.g_range[1])
        )


# ---------------------------------------------------------------------------
# 后处理与输出
# ---------------------------------------------------------------------------


def median_filter_mask(mask: np.ndarray, size: int = 5) -> np.ndarray:
    """5x5 多数投票中值滤波；边界采用 edge padding。"""
    if size <= 1:
        return mask
    if size % 2 == 0:
        raise ValueError(f"median size must be odd, got {size}")
    pad = size // 2
    padded = np.pad(mask.astype(np.uint8), pad, mode="edge")
    windows = np.lib.stride_tricks.sliding_window_view(padded, (size, size))
    return windows.mean(axis=(-1, -2)) > 0.5


def colorspace_split(
    img: Image.Image,
    split: Split,
    median_size: int | None = None,
) -> Image.Image:
    """掩膜外的像素置黑；alpha 原样透传。"""
    view = np.array(img.convert("RGB"))
    has_alpha = img.mode in ("RGBA", "LA") or "transparency" in img.info
    mask = split.mask(view)
    if median_size is not None:
        mask = median_filter_mask(mask, median_size)
    output = np.where(mask[..., None], view, 0).astype(np.uint8)
    if not has_alpha:
        return Image.fromarray(output)
    alpha = np.array(img.convert("RGBA"))[..., 3]
    return Image.fromarray(np.dstack((output, alpha)))


# ---------------------------------------------------------------------------
# 演示参数：手动修改这里；每次只保留一个常量，其余候选留在注释里
# ---------------------------------------------------------------------------

# asian_6.png 对应 YCbCrBoxSplit()，asian_13.png 对应 HSVSplit()
PROJECT_DIR = Path(__file__).resolve().parent
# IMAGE_PATH = PROJECT_DIR / "public/asian_6.png"
# IMAGE_PATH = PROJECT_DIR / "public/asian_13.png"
IMAGE_PATH = PROJECT_DIR / "public/asian_1.png"

# SPLIT = SphereSplit()
# SPLIT = YCbCrBoxSplit()
# SPLIT = HSVSplit()
# SPLIT = LabEllipseSplit()
# SPLIT = ChromaticitySplit()
SPLIT = YCbCrEllipseSplit()

# MEDIAN_SIZE = 1  # 关闭中值滤波
MEDIAN_SIZE = 5


def main() -> None:
    image = Image.open(IMAGE_PATH)
    rgb = np.array(image.convert("RGB"))
    mask = SPLIT.mask(rgb)
    if MEDIAN_SIZE > 1:
        mask = median_filter_mask(mask, MEDIAN_SIZE)
    result = colorspace_split(image, SPLIT, MEDIAN_SIZE)

    split_name = type(SPLIT).__name__
    print(f"{IMAGE_PATH} | {split_name} | {mask.mean():.2%} pixels selected")

    fig, axes = plt.subplots(1, 3, figsize=(12, 5))
    axes[0].imshow(image)
    axes[0].set_title("input")
    axes[1].imshow(mask, cmap="gray")
    axes[1].set_title("mask")
    axes[2].imshow(result)
    axes[2].set_title(f"{split_name} output")
    for ax in axes:
        ax.axis("off")
    fig.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
