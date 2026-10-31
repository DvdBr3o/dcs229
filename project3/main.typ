#import "../dvdbr3o.typ/src/dvdbr3o.typ": *

#show: dvdbr3otypst.with(
  title: [DCS229 图像处理 \ 实验报告],
  subtitle: [颜色空间肤色分割与亚洲人脸测试],
  author: [代骏泽],
  xno: [24363012],
)

#let fig(path, caption, width: 100%) = figure(
  image(path, width: width),
  caption: caption,
)

#let pair(before, after, title, width: 46%) = figure(
  grid(
    columns: 2,
    gutter: 2%,
    align(center, image(before, width: 100%)),
    align(center, image(after, width: 100%)),
  ),
  caption: title,
)

#let simple-table(cols, ..items) = table(
  columns: cols,
  inset: 6pt,
  stroke: 0.5pt,
  ..items,
)

= 实验概览

本实验把人脸肤色分割写成“颜色空间 + 判决边界”的组合问题。所有分割器共享同一个 `Split` 接口，输入是一幅 RGB 图像，输出是一个布尔掩膜；`colorspace_split` 再负责把掩膜变成可视结果。这样新增一种颜色空间时，只需增加一个类，不需要改动 I/O 或绘图代码。

实验实现了 6 种判据：RGB 球、YCbCr 矩形框、YCbCr 旋转椭圆、HSV 矩形框、CIELAB 椭圆和归一化 RGB 矩形框。原始素材是 15 张亚洲人脸照片，覆盖不同肤色、光照与背景；经逐一比较后只保留 3 张，分别选用三种表现最稳定的判据：

#simple-table(
  (0.9fr, 1.3fr, 1.7fr, 1.5fr, 1.1fr),
  table.header([素材], [尺寸], [选用 split], [颜色空间], [选中比例]),
  [`asian_1`], [512×640], [`ycbcr-ellipse`], [YCbCr 的 $C_b/C_r$ 椭圆], [`23.46%`],
  [`asian_6`], [427×640], [`ycbcr-box`], [YCbCr 矩形框], [`32.97%`],
  [`asian_13`], [427×640], [`hsv`], [HSV 矩形框], [`14.86%`],
)

= 实验原理

== 为什么需要换颜色空间

在 RGB 中，肤色表现为一条沿原点方向延伸的狭长带：亮度变化会让 $R, G, B$ 同时增大或减小，单纯用“到某个平均色的欧氏距离”很难把肤色与浅色衣服、灰墙或暖色背景区分开。把亮度与色度分开，或把颜色拆成色相、饱和度、明度，肤色才会在低维子空间里聚成一个更紧的簇。

本实验比较的 6 种判据分别对应 5 个颜色空间：

- *RGB*：保留原始三通道，用球或立方体描述肤色；
- *YCbCr*：BT.601 亮度 $Y$ 与色度 $C_b, C_r$ 分离，肤色在 $C_b/C_r$ 平面上聚成斜向椭圆；
- *HSV*：色相 $H$ 描述颜色种类，饱和度 $S$ 与明度 $V$ 描述鲜艳程度和亮度；
- *CIELAB*：$L^*$ 为感知亮度，$a^*$ 为红绿轴、$b^*$ 为黄蓝轴，肤色落在 $a^* > 0, b^* > 0$ 的一小片区域；
- *归一化 RGB*：$r = R \/ (R + G + B)$、$g = G \/ (R + G + B)$，在理想情况下与亮度无关。

== 颜色空间转换

=== YCbCr

采用 BT.601 全范围转换：

$ Y = 0.299 R + 0.587 G + 0.114 B $

$ C_b = 128 - 0.168736 R - 0.331264 G + 0.5 B $

$ C_r = 128 + 0.5 R - 0.418688 G - 0.081312 B $

对亚洲肤色而言，经验范围大致是 $77 lt.eq C_b lt.eq 127$、$133 lt.eq C_r lt.eq 173$，同时要求 $Y$ 不太暗。这个范围在不同白平衡下比 RGB 球稳定得多。

=== HSV

先把 $R, G, B$ 归一化到 $[0, 1]$，令 $M = max(R, G, B)$、$m = min(R, G, B)$、$Delta = M - m$，则

$ H = 60 degree times cases(
  ((G - B) / Delta) mod 6 & "若" M = R,
  (B - R) / Delta + 2 & "若" M = G,
  (R - G) / Delta + 4 & "若" M = B,
) $

$ S = Delta / M, quad V = M $（$M = 0$ 时取 $S = 0$）。

肤色通常落在 $H approx 0 degree$ 到 $50 degree$ 之间；但高光处 $S$ 很小、阴影处 $V$ 很小，因此还需要对 $S$ 和 $V$ 设门限。

=== CIELAB

先把 sRGB 做反 gamma 线性化，再乘 D65 白点下的 RGB→XYZ 矩阵，最后用立方根非线性得到 $L^*$、$a^*$、$b^*$。本实验只使用 $a^*$、$b^*$ 平面上的椭圆，并把 $L^*$ 当作亮度门限，避免把黑发和深色衣服选进来。

=== 归一化 RGB

$ r = R \/ (R + G + B), quad g = G \/ (R + G + B) $

它去掉了整体亮度，但对很暗的像素不稳定（分母接近 0），且不同色相可能投影到同一 $(r, g)$ 点，因此只作为对照。

== 判决边界

- *球*：$sqrt((R - mu_R)^2 + (G - mu_G)^2 + (B - mu_B)^2) < t$。参数少，但把亮度和色度耦合在一起。
- *矩形框*：在每个分量上分别给区间，所有区间同时满足才选中。实现最简单，边界与坐标轴平行。
- *旋转椭圆*：在二维色度平面上，先把坐标旋转 $theta$，再判断 $(u \/ a)^2 + (v \/ b)^2 lt.eq 1$。它比矩形更贴合肤色簇的倾斜方向。
- *中值滤波*：对布尔掩膜做 $5 times 5$ 多数投票，去掉孤立噪点；边界采用 edge padding，避免腐蚀贴近图像边缘的实心区域。

= 实验设计

== 代码结构

#simple-table(
  (1.4fr, 2.7fr),
  table.header([文件], [作用]),
  [`colorspace_split.py`], [颜色空间转换、6 个 `Split` 实现、中值滤波、`colorspace_split` 与三联动图演示],
  [`public/`], [3 张 8 位 RGB PNG 素材、各自 `_mask` / `_out`、报告对比图与评分表],
  [`main.typ`], [本报告],
  [`environment.yml`], [运行依赖（numpy、pillow、matplotlib）],
)

== 统一接口

接口刻意保持很小：`Split` 只要求实现 `mask`，`colorspace_split` 负责把掩膜应用到图像上。RGB 以外的一切都封装在各个 `Split` 内部，因此调用方不需要知道当前用的是哪种颜色空间。

```python
class Split(ABC):
    @abstractmethod
    def mask(self, img: np.ndarray) -> np.ndarray: ...

def colorspace_split(img, split, median_size=None):
    view = np.array(img.convert("RGB"))
    mask = split.mask(view)
    if median_size is not None:
        mask = median_filter_mask(mask, median_size)
    output = np.where(mask[..., None], view, 0).astype(np.uint8)
    return Image.fromarray(output)
```

若输入带 alpha，`colorspace_split` 会把 alpha 原样拼回输出；掩膜本身始终是 $H times W$ 的布尔数组。为突出算法逻辑，下文代码块省略了类型标注与 `super().__init__()`。

== RGB 球：`SphereSplit`

这是原始版本的基线：中心默认取整幅图的平均颜色，半径由 `thres` 控制。它等价于在 RGB 空间里画一个球，球内即“肤色”。

```python
class SphereSplit(Split):
    def __init__(self, avg=None, thres=100):
        self.avg = avg
        self.thres = thres

    def mask(self, img):
        rgb = _as_float_rgb(img)
        avg = self.avg if self.avg is not None else rgb.mean(axis=(0, 1))
        return np.linalg.norm(rgb - avg, axis=-1) < self.thres
```

问题也来自这里：灰墙、白衬衫与肤色在 RGB 中的距离可能很小，只要图像均值偏向背景，球就会把大片背景圈进来。

== YCbCr 矩形框：`YCbCrBoxSplit`

矩形框把 BT.601 的三个分量分别限制在经验区间内，是文献中最常见的肤色检测器。代码只做三次比较的与运算：

```python
class YCbCrBoxSplit(Split):
    def __init__(self, cb_range=(77, 127), cr_range=(133, 173), y_range=(40, 255)):
        self.cb_range, self.cr_range, self.y_range = cb_range, cr_range, y_range

    def mask(self, img):
        y, cb, cr = np.moveaxis(rgb_to_ycbcr(img), -1, 0)
        return ((y >= self.y_range[0]) & (y <= self.y_range[1])
                & (cb >= self.cb_range[0]) & (cb <= self.cb_range[1])
                & (cr >= self.cr_range[0]) & (cr <= self.cr_range[1]))
```

它的优点是参数少、可解释性强；缺点是矩形框的四个角会伸到肤色簇之外，遇到与肤色相近的暖色背景时容易漏选。

== YCbCr 椭圆：`YCbCrEllipseSplit`

椭圆先把 $C_b/C_r$ 坐标旋转 $theta$，再按两个半轴归一化。旋转角让长轴沿着肤色簇的倾斜方向，因此比矩形框更贴合数据：

```python
class YCbCrEllipseSplit(Split):
    def __init__(self, center=(110, 150), axes=(26, 20), rotation=15.0, y_range=(30, 255)):
        self.center, self.axes = center, axes
        self.rotation, self.y_range = rotation, y_range

    def mask(self, img):
        y, cb, cr = np.moveaxis(rgb_to_ycbcr(img), -1, 0)
        theta = np.deg2rad(self.rotation)
        dcb, dcr = cb - self.center[0], cr - self.center[1]
        u = np.cos(theta) * dcb + np.sin(theta) * dcr
        v = -np.sin(theta) * dcb + np.cos(theta) * dcr
        radius = (u / self.axes[0]) ** 2 + (v / self.axes[1]) ** 2
        return (radius <= 1.0) & (y >= self.y_range[0]) & (y <= self.y_range[1])
```

与矩形框相比，多出的两个参数（轴长比与旋转角）换来更紧的边界；在灰棚拍素材 `asian_1` 上，这一点体现得最明显。

== HSV 矩形框：`HSVSplit`

HSV 版本直接对色相、饱和度、明度设区间。色相在红色附近会跨过 $0 degree$，因此提供 `wrap_hue` 选项；本实验的亚洲肤色主要落在 $0 degree$ 到 $50 degree$，默认不需要回绕。

```python
class HSVSplit(Split):
    def __init__(self, hue_range=(0, 50), saturation_range=(0.10, 0.75),
                 value_range=(0.20, 1.0), wrap_hue=False):
        self.hue_range, self.saturation_range = hue_range, saturation_range
        self.value_range, self.wrap_hue = value_range, wrap_hue

    def mask(self, img):
        hue, saturation, value = np.moveaxis(rgb_to_hsv(img), -1, 0)
        if self.wrap_hue:
            hue_ok = (hue >= self.hue_range[0]) | (hue <= self.hue_range[1])
        else:
            hue_ok = (hue >= self.hue_range[0]) & (hue <= self.hue_range[1])
        return (hue_ok
                & (saturation >= self.saturation_range[0]) & (saturation <= self.saturation_range[1])
                & (value >= self.value_range[0]) & (value <= self.value_range[1]))
```

HSV 对“颜色种类”非常直观，适合背景色与肤色差异大的棚拍图；但在低饱和高光与深阴影处，$H$ 和 $S$ 都会变得不稳定。

== CIELAB 椭圆：`LabEllipseSplit`

LAB 版本在 $a^*$、$b^*$ 平面上做与 YCbCr 椭圆相同的旋转椭圆判断，只是把亮度换成 $L^*$ 门限。它的目标是更符合人眼感知的红绿、黄蓝方向：

```python
class LabEllipseSplit(Split):
    def __init__(self, center=(14, 18), axes=(13, 13), rotation=30.0, l_range=(25, 100)):
        self.center, self.axes = center, axes
        self.rotation, self.l_range = rotation, l_range

    def mask(self, img):
        lightness, a, b = np.moveaxis(rgb_to_lab(img), -1, 0)
        theta = np.deg2rad(self.rotation)
        da, db = a - self.center[0], b - self.center[1]
        u = np.cos(theta) * da + np.sin(theta) * db
        v = -np.sin(theta) * da + np.cos(theta) * db
        radius = (u / self.axes[0]) ** 2 + (v / self.axes[1]) ** 2
        return (radius <= 1.0) & (lightness >= self.l_range[0]) & (lightness <= self.l_range[1])
```

实际测试中，固定的 $L^*$ 门限会把侧脸阴影和额头高光切掉，候选对比图里的 LAB 结果因此常出现黑色空洞。

== 归一化 RGB：`ChromaticitySplit`

归一化 RGB 只使用 $r, g$ 两个分量，另外用 $R + G + B$ 的和排除非常暗的像素。代码与矩形框同构：

```python
class ChromaticitySplit(Split):
    def __init__(self, r_range=(0.33, 0.48), g_range=(0.28, 0.40), min_sum=30.0):
        self.r_range, self.g_range, self.min_sum = r_range, g_range, min_sum

    def mask(self, img):
        rgb = _as_float_rgb(img)
        r, g = np.moveaxis(rgb_to_chromaticity(rgb), -1, 0)
        return ((rgb.sum(axis=-1) >= self.min_sum)
                & (r >= self.r_range[0]) & (r <= self.r_range[1])
                & (g >= self.g_range[0]) & (g <= self.g_range[1]))
```

它对整体亮度不敏感，但会把与肤色色度接近的浅色衣服、灰色背景一起选进来，这一点在 `asian_1` 与 `asian_13` 上很明显。

== 中值滤波与演示脚本

后处理用 $5 times 5$ 的多数投票实现。没有直接调用 Pillow 的 `MedianFilter`，因为后者在边界补零，会把贴着图像边缘的实心区域腐蚀掉：

```python
def median_filter_mask(mask, size=5):
    if size <= 1:
        return mask
    pad = size // 2
    padded = np.pad(mask.astype(np.uint8), pad, mode="edge")
    windows = np.lib.stride_tricks.sliding_window_view(padded, (size, size))
    return windows.mean(axis=(-1, -2)) > 0.5
```

演示脚本不设命令行参数，而是在文件末尾手动修改三个常量；每次只保留一个，其余候选写在注释里：

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

这样脚本本身只有一条演示路径，不需要 CLI、批量出图或单元测试代码。`main()` 读取图片、生成掩膜与结果，然后用 Matplotlib 画“输入 / 掩膜 / 输出”三联图：

```python
image = Image.open(IMAGE_PATH)
mask = SPLIT.mask(np.array(image.convert("RGB")))
result = colorspace_split(image, SPLIT, MEDIAN_SIZE)

fig, axes = plt.subplots(1, 3, figsize=(12, 5))
axes[0].imshow(image);       axes[0].set_title("input")
axes[1].imshow(mask, cmap="gray"); axes[1].set_title("mask")
axes[2].imshow(result);      axes[2].set_title(type(SPLIT).__name__)
plt.show()
```

= 演示与结果

== 三联图演示

在仓库根目录运行 `python project3/colorspace_split.py`，会打印当前素材、split 名称与选中比例，并显示三联图。报告中的三张输入 / 输出对与 6 种候选对比图，是在临时目录里切换上述常量后一次性生成的，生成代码不保留在仓库中。

对保留的 3 张素材分别用选定 split 处理，得到输入 / 输出对比。输出中肤色保留原色，其余像素置黑；报告素材生成时，掩膜与输出图另存为 PNG。素材均来自 Pexels，遵循 Pexels License，摄影者与原始页面见 `public/README.md`。

#pair(
  "public/asian_1.png",
  "public/asian_1_out.png",
  [asian_1：左为输入，右为 `ycbcr-ellipse` 输出。灰色背景与浅色衣服被完全去掉],
)

#pair(
  "public/asian_6.png",
  "public/asian_6_out.png",
  [asian_6：左为输入，右为 `ycbcr-box` 输出。低照度侧脸的脸颊、手部与袖子被保留],
)

#pair(
  "public/asian_13.png",
  "public/asian_13_out.png",
  [asian_13：左为输入，右为 `hsv` 输出。灰色背景、黑色头发与衣服均未选入],
)

== 候选 split 对比

对每张素材都跑完 6 种 split，图题中的星号标出最终选用的方案。三个对比图的输入、参数与滤波尺寸完全一致，只改变 `Split` 类。

#fig(
  "public/compare_asian_1.png",
  [asian_1 的 6 种 split 对比。RGB 球与归一化 RGB 把浅色衣服选入；YCbCr 框、YCbCr 椭圆、HSV 与 LAB 的背景都干净],
  width: 100%,
)

#fig(
  "public/compare_asian_6.png",
  [asian_6 的 6 种 split 对比。低照度下 RGB 球的中心偏向背景，几乎整幅图被选中；YCbCr 框在保持脸颊的同时把背景压到较低比例],
  width: 100%,
)

#fig(
  "public/compare_asian_13.png",
  [asian_13 的 6 种 split 对比。单色灰背景上 YCbCr 框、YCbCr 椭圆与 HSV 都只留下人脸和颈部；LAB 因亮度门限出现空洞],
  width: 100%,
)

为了不只依赖肉眼，临时出图脚本还计算两个代理指标：人脸框覆盖率（近似衡量肤色被保留的比例）和四角背景误检率（四个 $80 times 80$ 角落中被选中的比例）。人脸框是手工给出的近似矩形，只用于相对比较，不参与分割。完整结果在 `public/split_scores.csv`，汇总如下（选中比例后面的括号依次为人脸框覆盖率和四角误检率）：

#simple-table(
  (1.0fr, 1.3fr, 1.05fr, 1.05fr, 1.05fr),
  table.header([素材], [split], [选中比例], [人脸框], [四角误检]),
  [asian_1], [sphere], [`75.38%`], [`69.77%`], [`86.66%`],
  [], [ycbcr-box], [`23.24%`], [`75.56%`], [`0.00%`],
  [], [*ycbcr-ellipse*], [`23.46%`], [`77.23%`], [`0.00%`],
  [], [hsv], [`23.30%`], [`76.12%`], [`0.00%`],
  [], [lab], [`22.18%`], [`71.85%`], [`0.00%`],
  [], [chromaticity], [`49.28%`], [`87.39%`], [`36.34%`],
  [asian_6], [sphere], [`82.57%`], [`49.22%`], [`97.21%`],
  [], [*ycbcr-box*], [`32.97%`], [`84.30%`], [`8.82%`],
  [], [ycbcr-ellipse], [`30.84%`], [`82.97%`], [`8.68%`],
  [], [hsv], [`41.83%`], [`84.03%`], [`10.33%`],
  [], [lab], [`21.06%`], [`66.98%`], [`6.27%`],
  [], [chromaticity], [`55.56%`], [`91.93%`], [`13.50%`],
  [asian_13], [sphere], [`60.76%`], [`42.59%`], [`50.30%`],
  [], [ycbcr-box], [`14.82%`], [`41.06%`], [`0.00%`],
  [], [ycbcr-ellipse], [`14.77%`], [`41.02%`], [`0.00%`],
  [], [*hsv*], [`14.86%`], [`41.72%`], [`0.00%`],
  [], [lab], [`11.56%`], [`31.30%`], [`0.00%`],
  [], [chromaticity], [`62.88%`], [`59.80%`], [`49.35%`],
)

=== 结果分析

- *asian_1（灰棚拍、浅色针织衫）*：RGB 球选中了 `75.38%` 的像素，四角误检高达 `86.66%`——它把整片灰背景和浅色衣服都圈进了球；归一化 RGB 也把衣服留下（`49.28%`，四角 `36.34%`）。一旦换到 YCbCr 或 HSV，四角误检立即降到 `0.00%`。在三个背景干净的方案中，YCbCr 椭圆的人脸框覆盖率最高（`77.23%`），因此选它。YCbCr 框与 HSV 只低约 1 个百分点，说明在这种理想光线下三种色度判据几乎等价。
- *asian_6（低照度、深色背景、托腮）*：RGB 球把背景和暗部一起选中，四角误检 `97.21%`，几乎失去分割意义。YCbCr 框的选中比例为 `32.97%`，人脸框覆盖率 `84.30%`；椭圆略低（`82.97%`），HSV 的总选中比例更高（`41.83%`），LAB 虽然四角误检最低（`6.27%`），但人脸覆盖率只有 `66.98%`，脸颊和额头被切成空洞。综合保留与背景抑制，矩形框在该图最均衡，且参数最少。
- *asian_13（灰色影棚、黑发黑衫、眼镜）*：背景是中性灰，YCbCr 框、椭圆、HSV 与 LAB 的四角误检都为 `0.00%`。HSV 的人脸框覆盖率最高（`41.72%`），LAB 因 $L^*$ 门限只有 `31.30%`，YCbCr 框与椭圆分别为 `41.06%`、`41.02%`。因此该图选 HSV；它的总选中比例也最低（`14.86%`）。
- *为什么没有选 LAB 或归一化 RGB*：LAB 的固定 $L^*$ 门限会在侧光与阴影处切掉肤色，造成“人脸内部空洞”，这在 `asian_6`、`asian_13` 以及原始 15 张候选中未保留的户外素材上都很明显；归一化 RGB 虽然亮度不变，却把浅色衣服和灰背景投影到与肤色相近的 $(r, g)$ 区域，四角误检常超过 `35%`。它们适合作为对照，不适合作为默认方案。
- *为什么 RGB 球会失败*：`SphereSplit` 以整幅图的平均色为中心，背景占比大时中心被拉向背景；半径 `100` 又足以覆盖很大一片 RGB 空间。它不是“肤色检测器”，只是“颜色接近平均值的区域检测器”。

= 实验结论

- 在保留原有 `Split` 抽象与 `colorspace_split(img, split)` 调用的前提下，新增了 YCbCr 框、YCbCr 椭圆、HSV、CIELAB 与归一化 RGB 五类判据，总计 6 种可切换实现；演示脚本通过手动切换 `SPLIT` 常量选择，代码路径不变。
- 15 张素材经比较后保留 3 张，分别选用三种不同判据：`asian_1` 用 `ycbcr-ellipse`，`asian_6` 用 `ycbcr-box`，`asian_13` 用 `hsv`。与 RGB 球相比，四角背景误检从 `86.66%`、`97.21%`、`50.30%` 降到 `0.00%`、`8.82%`、`0.00%`。
- 结论是：没有一种颜色空间在所有场景下都最好。灰棚拍、浅色衣服适合在 YCbCr 色度平面用椭圆；低照度侧脸用矩形框更稳；背景与肤色色相差异大的单色背景用 HSV 最直接。固定阈值的代价是换一批素材仍可能需要调参，后续可以引入人脸检测或空间先验、按图像自适应阈值，并用连通域与形态学操作进一步清理残留噪点。

= 分工说明

#simple-table(
  (1.2fr, 2.0fr),
  table.header([成员], [负责内容]),
  [代骏泽], [具体代码实现与算法设计],
  [YULDASHOVA SURAYYA], [代码框架与实验报告撰写],
)
