# Project 03：颜色空间肤色分割

对亚洲人脸图像做肤色分割：把 RGB 转换到不同的颜色空间，用各自适合的判决边界选出肤色像素，再用中值滤波去掉孤立噪点。代码只有一个演示脚本 `colorspace_split.py`，通过手动修改文件末尾的 `IMAGE_PATH`、`SPLIT`、`MEDIAN_SIZE` 常量来选择素材和算法。

## 颜色空间与判据

| `SPLIT` 常量 | 颜色空间 | 判决边界 |
| --- | --- | --- |
| `SphereSplit()` | RGB | 以 `avg` 为球心、`thres` 为半径的球 |
| `YCbCrBoxSplit()` | YCbCr（BT.601） | `Y / Cb / Cr` 三轴上的矩形框 |
| `YCbCrEllipseSplit()` | YCbCr | `Cb/Cr` 平面内的旋转椭圆（马氏距离球） |
| `HSVSplit()` | HSV | 色相 / 饱和度 / 明度的矩形框 |
| `LabEllipseSplit()` | CIELAB（D65） | `a*/b*` 平面内的旋转椭圆，`L*` 作亮度门限 |
| `ChromaticitySplit()` | 归一化 RGB | `(r, g) = (R, G)/(R+G+B)` 的矩形框 |

## 运行

```sh
# 依赖：numpy、pillow、matplotlib
python project3/colorspace_split.py
```

脚本末尾的演示参数类似：

```python
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

# MEDIAN_SIZE = 1
MEDIAN_SIZE = 5
```

每次只保留一个常量，其余候选留在注释里。运行后会打印选中比例，并弹出/显示“输入 / 掩膜 / 输出”三联图。

## 素材与 split 选择

原 `public/` 中的 15 张候选图只保留以下 3 张，分别对应三种表现最稳定的判据：

| 图片 | 尺寸 | 选用 split | 原因 |
| --- | --- | --- | --- |
| `asian_1.png` | 512×640 | `YCbCrEllipseSplit` | 灰棚拍、浅色衣服；椭圆在 `Cb/Cr` 上贴合肤色簇，背景误检为 0 |
| `asian_6.png` | 427×640 | `YCbCrBoxSplit` | 低照度侧脸；矩形框保持脸颊与手部，且参数最少 |
| `asian_13.png` | 427×640 | `HSVSplit` | 灰色背景、深色头发与衣服；HSV 的色相/饱和度门限最干净 |

`public/` 中同时保留了：

- `asian_<序号>.png`：输入素材；
- `asian_<序号>_mask.png`：二值掩膜；
- `asian_<序号>_out.png`：只保留肤色像素的输出；
- `compare_asian_<序号>.png`：6 种 split 的报告对比图；
- `split_scores.csv`：候选 split 的选中比例与人脸框/背景指标。

## 算法

BT.601 转换：

$$
Y = 0.299R + 0.587G + 0.114B,\quad
C_b = 128 - 0.168736R - 0.331264G + 0.5B,\quad
C_r = 128 + 0.5R - 0.418688G - 0.081312B
$$

`YCbCrBoxSplit` 使用经典肤色框：`Y >= 40`、`77 <= Cb <= 127`、`133 <= Cr <= 173`。`YCbCrEllipseSplit` 把同一簇肤色写成中心 `(Cb, Cr) = (110, 150)`、轴长 `(26, 20)`、旋转 15° 的椭圆。`HSVSplit` 取色相 0–50°、饱和度 0.10–0.75、明度 0.20–1.00。所有阈值都定义在各 `Split` 类的构造函数中，便于按素材调整。

分割后可选 5×5 中值滤波；滤波以多数票实现，并在边界做 edge padding，避免把贴近图像边缘的实心区域腐蚀掉。
