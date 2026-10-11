// ============================================================
//  Project 04-03 实验报告（单独报告）
//  统一结构：1 实验要求 / 2 实验过程 / 3 扩展实验与性能 / 4 关键代码 / 5 实验结果
//  图片路径以项目根目录为基准（如 "/0403/results/xxx.png"），请与 0403、0404 文件夹放在同一根目录下编译
// ============================================================
#let sigma-chosen = "30"


#set document(title: "Project 04-03 实验报告")
#set page(paper: "a4", margin: (x: 2.2cm, y: 2.4cm), numbering: "1")
#set text(font: ("Times New Roman", "SimSun"), size: 10.5pt, lang: "zh", region: "cn")
#set par(justify: true, leading: 0.8em)

// 一级标题 = Project 标题（不编号，居中，另起一页）；二级 = 节（1, 2, …）；三级 = 小节（1.1, …）；四级 = 小小节（1.1.1, …）
// 每个 Project 内部的节号都从 1 重新开始
#set heading(numbering: (..n) => {
  let p = n.pos()
  if p.len() <= 1 { none } else { numbering("1.1", ..p.slice(1)) }
})
#show heading: set text(font: ("Arial", "SimHei"), weight: "bold")
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  set align(center)
  block(above: 0pt, below: 1.2em, text(size: 18pt, it.body))
}
#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): set block(above: 1.6em, below: 0.9em)
#show heading.where(level: 3): set text(size: 12pt)
#show heading.where(level: 3): set block(above: 1.3em, below: 0.7em)
#show heading.where(level: 4): set text(size: 11pt)
#show heading.where(level: 4): set block(above: 1.1em, below: 0.6em)

#show raw: set text(font: ("Consolas", "Courier New", "SimSun"), size: 0.92em)
#show raw.where(block: true): it => block(
  width: 100%, fill: luma(245), inset: 8pt, radius: 3pt, stroke: 0.4pt + luma(210),
  text(size: 7.8pt, it),
)

#set table(stroke: 0.5pt + luma(120), inset: 6pt)
#show table: set text(size: 9.5pt)
#show table: set block(breakable: false)
#show table.cell.where(y: 0): set text(weight: "bold")
#set figure(gap: 0.8em)
#show figure.caption: set text(size: 9.5pt)
#show figure: set block(above: 1.2em, below: 1.2em)
#set list(indent: 1em)
#set enum(indent: 1em)
#set math.equation(numbering: none)

// 子图辅助：cap("/0403/", "results/xxx.png")[说明文字]
#let cap(base, img, label) = [#image(base + img) #align(center)[#text(size: 8.5pt)[#label]]]

// Project 标题 + 课程 / 组别 / 负责人
#let project-part(id, title, author) = [
  #heading(level: 1, title)
  #align(center)[#text(size: 10.5pt)[课程：数字图像处理 #h(1.5em) 组别：20 #h(1.5em) 负责人：#author]]
  #v(0.4em)
]

#project-part("0403", "Project 04-03：基于从零实现的 2D DFT 进行低通滤波", "Y.Surayya")

== 实验要求
- *(a)* 实现式 (4.3-7) 中的高斯低通滤波器。必须能够指定所得二维函数的尺寸 $M times N$ 以及高斯函数中心的二维位置。
- *(b)* 下载 Fig. 4.11(a)（与 Fig. 4.18(a) 相同）并对其进行低通滤波，得到 Fig. 4.18(c)。

所使用的傅里叶变换来自我们在 Project 04-01 中的自实现，处理链路中不使用 `np.fft`。

除必做项之外，我们还研究了：(i) DFT 是否正确以及其速度如何；(ii) 自实现的 radix-2 FFT 是否比矩阵 DFT 更快；(iii) 高斯滤波器与理想滤波器、巴特沃斯滤波器的对比；(iv) 缓存频谱能为 $sigma$ 扫描带来多大加速；(v) 上述一切能否在其他图像上正常工作。

== 实验过程

=== 理论基础
==== 可分离的 2D DFT

对于一幅尺寸为 $M times N$ 的图像 $f(x,y)$，其二维 DFT 为

$ F(u,v) = sum_(x=0)^(M-1) sum_(y=0)^(N-1) f(x,y) thin e^(-j 2 pi (u x / M + v y / N)). $

由于核是可分离的，该变换等价于先对每一列做一维 DFT，再对每一行做一维 DFT。借助 DFT 矩阵 $W_N (k,n) = e^(-j 2 pi k n slash N)$，可写成

$ F = W_M dot f dot W_N^T, $

这样只需两次矩阵乘法，无需任何像素级循环。

==== 逆 DFT

逆变换与前向变换的区别仅在于指数的符号以及一个因子 $1 slash (M N)$。对输入和输出同时取共轭即可翻转指数符号，因此

$ f = overline("DFT"(overline(F))) / (M N). $

无需单独实现逆变换函数。

==== 中心化

将 $f(x,y)$ 乘以 $(-1)^(x+y)$ 可将直流（DC）分量移至 $(M slash 2, N slash 2)$。对于偶数尺寸的图像，这一步等价于 `fftshift`。滤波器也必须以同一点为中心。

==== 高斯低通滤波器

$ H(u,v) = exp(- (D^2 (u,v)) / (2 sigma^2)), quad D^2 (u,v) = (u - u_0)^2 + (v - v_0)^2. $

参数 $sigma$ 是频域中的宽度。$sigma$ 越大，通过的高频越多（模糊越轻）；$sigma$ 越小，通过的高频越少（模糊越强）。中心 $(u_0, v_0)$ 是一个参数，默认取 `(M//2, N//2)`。

==== 滤波流程

$ f -> times (-1)^(x+y) -> "DFT" -> times H(u,v) -> "IDFT" -> times (-1)^(x+y) -> "Re" -> g(x,y) $

即：乘以 $(-1)^(x+y)$，做 DFT，与 $H(u,v)$ 逐元素相乘，做逆 DFT，再乘以 $(-1)^(x+y)$ 并取实部。

=== 代码组织
#table(
  columns: (auto, 1fr),
  align: (left, left),
  table.header[*文件*][*作用*],
  [`src/dft.py`], [`dft_matrix`、`dft2d`、`idft2d`、`center`、`spectrum`、`filter_freq`（Project 04-01 包）],
  [`src/gaussian_filter.py`], [`gaussian_lowpass(M, N, sigma, center_uv)`：部分 (a)],
  [`src/utils.py`], [`load_image`、`save_fig`、`save_image`：将指向 `data/` 和 `results/` 的路径集中在同一处],
  [`src/main.py`], [部分 (b)：对图像滤波并保存结果],
  [`src/extra.py`], [扩展实验（第 #ref(<sec-03-ext>, supplement: none) 节）],
  [`test/testing_dft.py`], [检验 DFT 是否正确（第 #ref(<sec-03-verify>, supplement: none) 节）],
  [`test/test1_pic.bmp`、`test/test2_pic.bmp`], [额外测试图像（第 #ref(<sec-03-general>, supplement: none) 节）],
)

图像 `Fig0418.jpeg` 存放在 `data/` 中，所有输出写入 `results/`。项目文件夹自成一体、完全独立。

=== DFT 的验证（`test/testing_dft.py`） <sec-03-verify>

在滤波之前，先在真实测试图像上对 DFT 进行了验证。所有图像均以 `float64` 加载，因为 `uint8` 运算会溢出。

- *图像尺寸：* $688 times 688$，灰度范围为 0 到 255。
- *往返测试：* 将 `idft2d(dft2d(f))` 与 $f$ 比较，最大绝对误差为 $1.2 times 10^(-10)$，属于浮点舍入误差水平。
- *中心化频谱：* 对数标度的频谱 $S = log(1 + |F|)$ 的最亮点位于数组中心，能量向边缘递减（#ref(<fig-spectrum>)）。
- *平均值：* 将位于中心的直流分量除以 $M N$ 后与图像均值比较。

```text
forward DFT (8, 8): max error = 1.60e-14  ->  PASS
forward DFT (6, 10): max error = 2.80e-14  ->  PASS
forward DFT (31, 20): max error = 1.45e-12  ->  PASS
speed: 256x256 DFT took 0.0140 s
image: (688, 688) min 0.0 max 255.0
round trip on the image: max error = 1.20e-10  ->  PASS
DC / (M*N): 207.25278233166577
image mean: 207.25278233166577
average value: max error = 0.00e+00  ->  PASS
```

两者一致，从而验证了变换与中心化的正确性。

其中 PASS 的定义为：

```python
def check(name, err, tol=1e-8):
    print(f"{name}: max error = {err:.2e}  ->  {'PASS' if err < tol else 'FAIL'}")
```

#figure(
  image("/0403/results/fig_spectrum.png", width: 78%),
  caption: [fig_spectrum.png：原始图像及其中心化的傅里叶频谱。],
) <fig-spectrum>

=== 部分 (a)：高斯低通滤波器

`gaussian_lowpass(M, N, sigma, center_uv=None)` 利用 `np.indices` 一次性构建完整的 $M times N$ 数组并返回 $exp(-D^2 slash (2 sigma^2))$。尺寸由 `M` 和 `N` 指定，中心由 `center_uv` 指定（默认取数组中央）。

以 $M = N = 688$、$sigma = 30$ 进行验证：

#table(
  columns: (1.4fr, 1fr, 2fr),
  align: (left, left, left),
  table.header[*检查项*][*预期*][*实测*],
  [`H.shape`], [$(688, 688)$], [$(688, 688)$],
  [中心处 $H$], [$1.0$], [$1.0$],
  [角落 $[0, 0]$ 处 $H$], [近似 0], [$7.889 times 10^(-58)$],
)

另外生成了 `center_uv = (100, 200)` 的滤波器，以表明中心可以指定。其最大值出现在 $(100, 200)$ 处。

#figure(
  image("/0403/results/fig01_0403_H_plot.png", width: 52%),
  caption: [fig01_0403_H_plot.png：高斯低通滤波器，$sigma = 30$，已中心化。],
) <fig-H>

=== 部分 (b)：对 Fig. 4.18(a) 的低通滤波


*流程。* 用 `filter_freq(f, H)` 对图像进行滤波，$sigma$ 分别取 5、15、30、80 和 230。将结果与教材中的 Fig. 4.18(c) 对比，选取最接近的一个。

#figure(
  image("/0403/results/fig02_0403_lowpass_comparison.png", width: 82%),
  caption: [fig02_0403_lowpass_comparison.png：原始图像（左）与高斯低通结果（右），$sigma = 30$。],
) <fig-compare>

#figure(
  grid(
    columns: (1fr, 1fr, 1fr),
    column-gutter: 6pt,
    row-gutter: 8pt,
    cap("/0403/", "results/fig03_0403_lowpass_sigma5.png")[$sigma = 5$ \ `fig03_0403_lowpass_sigma5.png`],
    cap("/0403/", "results/fig04_0403_lowpass_sigma15.png")[$sigma = 15$ \ `fig04_0403_lowpass_sigma15.png`],
    cap("/0403/", "results/fig05_0403_lowpass_sigma30.png")[$sigma = 30$ \ `fig05_0403_lowpass_sigma30.png`],
    cap("/0403/", "results/fig06_0403_lowpass_sigma80.png")[$sigma = 80$ \ `fig06_0403_lowpass_sigma80.png`],
    cap("/0403/", "results/fig07_0403_lowpass_sigma230.png")[$sigma = 230$ \ `fig07_0403_lowpass_sigma230.png`],
    cap("/0403/", "data/Fig0418.jpeg")[原始图像 \ `Fig0418.jpeg`],
  ),
  caption: [fig03–07_0403_lowpass_sigma\_\*.png：高斯低通结果（$sigma = 5、15、30、80、230$）与原始图像。],
) <fig-sigmas>

*讨论。*

- *$sigma$ 的作用。* $sigma$ 是 $H$ 在频域中的宽度，因此 $sigma$ 小时只保留低频、模糊较强；$sigma$ 大时结果接近原图。
- *图像为何变模糊。* 边缘、细线条和小字符由高频分量承载。去除高频后，锐利的跳变变为平缓的过渡。
- *无振铃。* 高斯滤波器没有锐利的截止，且其逆变换仍为正的高斯函数，因此不会产生振铃（对比第 #ref(<sec-filters>, supplement: none) 节）。
- *中心化。* $H$ 的中心位于 $(M slash 2, N slash 2)$，与乘以 $(-1)^(x+y)$ 后直流分量的位置相同。若两者不匹配，就会滤除错误的频率。
- *实部输出。* 舍入误差留下的虚部可以忽略，因此最后取实部。

=== 推广到其他图像 <sec-03-general>

在不改动算法的情况下，将同一套代码用于另外两幅测试图像（`test/test1_pic.bmp` 与 `test/test2_pic.bmp`）。输出结果保存在 `test/test1_results/` 与 `test/test2_results/` 中。

#table(
  columns: (1.3fr, 1fr, 3fr, 2fr),
  align: (left, left, left, left),
  table.header[*图像*][*尺寸*][*内容*][*结果*],
  [`test1_pic.bmp`], [$688 times 688$], [《数字图像处理》封面灰度图], [$sigma$ 越小模糊越强，无伪影],
  [`test2_pic.bmp`], [$688 times 688$], [灰度教材测试图；一个头戴图案纸生日帽的幼童], [行为相同],
)

#figure(
  grid(
    columns: (1fr, 1fr),
    column-gutter: 8pt,
    cap("/0403/", "test/test1_results/fig02_0403_lowpass_comparison.png")[`test/test1_results/fig02_0403_lowpass_comparison.png`],
    cap("/0403/", "test/test2_results/fig02_0403_lowpass_comparison.png")[`test/test2_results/fig02_0403_lowpass_comparison.png`],
  ),
  caption: [额外测试图像的低通滤波结果，左：`test1_pic.bmp`，右：`test2_pic.bmp`。（其余结果见 `test/test1_results/` 与 `test/test2_results/` 文件夹）],
) <fig-tests>

由于 DFT 矩阵由图像自身的高度和宽度构建，非正方形尺寸以及非 2 的幂次尺寸都无需填充或缩放即可处理。

== 扩展实验与性能 <sec-03-ext>
由于必做部分较为简单，我们还进一步研究了该方法的行为特性。所有实验位于 `src/extra.py`。每个计时均取 3 次运行中的最佳值以降低噪声。

=== 自实现的 radix-2 FFT 与矩阵 DFT 的对比

*思路。* 矩阵 DFT 的代价约为 $O(n^3)$（对于 $n times n$ 的图像），而 radix-2 FFT 约为 $O(n^2 log n)$。我们沿最后一个轴实现了递归 radix-2 FFT（按偶、奇样本拆分，用旋转因子合并），并先后应用于行与列。它要求尺寸为 2 的幂。

*精度。* FFT 与矩阵 DFT 的偏差最大为 $2.0 times 10^(-11)$（在随机 $64 times 128$ 数组上的最大绝对差）。

*速度。* 在 $n times n$ 随机数组上测得的时间：

#table(
  columns: (1fr, 1.4fr, 1.4fr, 1.4fr),
  align: center,
  table.header[*$n$*][*矩阵 DFT（s）*][*自实现 FFT（s）*][*矩阵 / FFT*],
  [64], [0.0006], [0.0017], [0.34],
  [128], [0.0020], [0.0051], [0.39],
  [256], [0.0124], [0.0162], [0.76],
  [512], [0.0475], [0.0609], [0.78],
  [1024], [0.1988], [0.2868], [0.69],
  [2048], [1.2045], [1.4394], [0.84],
)

双对数坐标下的斜率：矩阵 DFT 为 2.14，FFT 为 1.81。

#figure(
  image("/0403/results/ext1_speed.png", width: 62%),
  caption: [ext1_speed.png：矩阵 DFT 与自实现 radix-2 FFT 的对比。],
) <fig-speed>

*发现。*

- 在所有测试尺寸上矩阵 DFT 都更快（比值均小于 1），因此此处 FFT 并不划算。直到 2048 仍未观察到交叉点。
- FFT 增长更慢（斜率 1.81 对 2.14），因此总体上随着 $n$ 增大，比值从 0.34 上升至 0.84。由此可以预期 FFT 在更大尺寸下会胜出，但我们没有实际测量。
- 矩阵 DFT 的斜率远低于理论值 3。矩阵方法利用了 NumPy 优化过的多线程矩阵乘法，而我们的 FFT 是用 Python 编写的，包含大量小数组操作。FFT 的增长速率更低，但常数开销更高。
- 个别比值存在波动（例如 $n = 1024$ 时为 0.69，低于 $n = 512$ 时的 0.78），我们将其归因于计时噪声，因此只依据总体趋势得出结论。

这也解释了为什么主项目仍采用矩阵 DFT：对于此处使用的图像尺寸，它更简单且并不更慢。

=== 理想、巴特沃斯与高斯低通滤波器 <sec-filters>

三种滤波器均采用相同的截止频率 $D_0 = 30$：理想滤波器（半径 $D_0$ 以内为 1，以外为 0）、2 阶巴特沃斯滤波器，以及 $sigma = D_0$ 的高斯滤波器。

#figure(
  image("/0403/results/ext2_filter_types.png", width: 100%),
  caption: [ext2_filter_types.png：理想、巴特沃斯（$n = 2$）与高斯低通滤波器，截止频率 $D_0 = 30$。],
) <fig-types>

理想滤波器在边缘和大字母周围出现波纹（振铃），巴特沃斯滤波器有轻微振铃，高斯滤波器则完全没有。理想滤波器出现振铃是预期之中的，因为其锐利的截止在空间域对应一个具有振荡旁瓣的 sinc 形核。高斯滤波器没有这样的旁瓣，这正是本项目选用它的原因。

=== $sigma$ 扫描中的频谱缓存

*思路。* 图像的正向 DFT 与 $sigma$ 无关。因此对多个 $sigma$ 值进行扫描时，只需一次正向 DFT，之后每个 $sigma$ 仅需一次乘法与一次逆 DFT。

*结果。* 对 8 个 $sigma$ 值，朴素扫描耗时 1.637 s，缓存扫描耗时 0.998 s，加速比为 *1.64*。两种方法得到的图像完全一致（最大差异为 0.0）。

朴素扫描需要 16 次变换（8 次正向、8 次逆变换），缓存扫描只需 9 次（1 次正向、8 次逆变换）。因此加速比的上限为 $16 slash 9 approx 1.78$。实测值略低，因为构建滤波器、乘法以及去中心化步骤并不会缩短。

同样的思路也让交互式调节 $sigma$ 变得廉价：完成第一次变换后，每尝试一个新的 $sigma$ 只需一次逆 DFT。

== 关键代码
=== `src/dft.py`
```python
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt

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
    F = dft2d(center(f))
    G = F * H
    g = idft2d(G)
    return np.real(center(g))
```

=== `src/gaussian_filter.py`
```python
import numpy as np

def gaussian_lowpass(M, N, sigma, center_uv=None):
    if center_uv is None:
        center_uv = (M // 2, N // 2)
    u0, v0 = center_uv
    u, v = np.indices((M, N))
    D2 = (u - u0)**2 + (v - v0)**2
    return np.exp(-D2 / (2 * sigma**2))
```

=== `src/main.py`（必做部分）
```python
from dft import *
from gaussian_filter import *
from utils import *

f = load_image()
M, N = f.shape
H = gaussian_lowpass(M, N, sigma=30)

g = filter_freq(f, H)

for sigma in [5, 15, 30, 80, 230]:
    g = filter_freq(f, gaussian_lowpass(M, N, sigma))
    save_image(g, f"lowpass_sigma{sigma}.png")
```

=== `src/extra.py`（radix-2 FFT 与缓存扫描）
```python
def fft_last_axis(x):
    n = x.shape[-1]
    if n == 1:
        return x.astype(complex)
    even = fft_last_axis(x[..., 0::2])
    odd = fft_last_axis(x[..., 1::2])
    w = np.exp(-2j * np.pi * np.arange(n // 2) / n)
    return np.concatenate([even + w * odd, even - w * odd], axis=-1)

def fft2d(a):
    return fft_last_axis(fft_last_axis(a).T).T

def sweep_cached():
    Fc = dft2d(center(f))                  # forward DFT only once
    for s in sigmas:
        np.real(center(idft2d(Fc * gaussian_lowpass(M, N, s))))
```

== 实验结果
我们从零实现了可分离矩阵形式的二维 DFT，并以 $1.2 times 10^(-10)$ 的往返误差、正确的中心化频谱和一致的平均值对其进行了验证。实现了尺寸与中心均可指定的高斯低通滤波器，取 $sigma = #sigma-chosen$ 时可复现 Fig. 4.18(c) 的模糊效果。同一套代码无需修改即可用于其他图像。在扩展实验中，自实现的 radix-2 FFT 精度达到 $2 times 10^(-11)$，但在 $2048 times 2048$ 以内比优化过的矩阵 DFT 慢（其增长率表明更大尺寸下它将胜出）；理想滤波器出现高斯滤波器所没有的振铃；缓存频谱使 $sigma$ 扫描获得了 1.64 倍的加速且结果完全一致。
