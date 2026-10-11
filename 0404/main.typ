// ============================================================
//  Project 04-04 实验报告（单独报告）
//  统一结构：1 实验要求 / 2 实验过程 / 3 扩展实验与性能 / 4 关键代码 / 5 实验结果
//  图片路径以项目根目录为基准（如 "/0403/results/xxx.png"），请与 0403、0404 文件夹放在同一根目录下编译
// ============================================================

#set document(title: "Project 04-04 实验报告")
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

#project-part("0404", "Project 04-04：利用低通图像实现高通滤波", "Y.Surayya")

== 实验要求
- *(a)* 将项目 04-03(b) 的结果图像从原图中减去，得到锐化图像，如式 (4.4-14) 所示。所得图像与图 4.26 中的高斯高通结果并不相似，请解释原因。
- *(b)* 调整高斯低通滤波器的方差，使图像相减得到的结果与图 4.26(c) 相似，并解释该结果。

本项目使用的二维傅里叶变换是项目 04-01 中自行实现的版本，处理流程中不使用 `np.fft`。

除必做内容外，我们还研究了：(i) 图像相减是否与频域高通滤波严格等价；(ii) 如何加快 $sigma$ 扫描；(iii) 对每个 $sigma$，高通结果中还保留了多少图像能量；(iv) 高提升滤波；(v) 该方法对其他图像以及非方形、含奇数边长的图像是否同样适用。

== 实验过程

=== 理论基础
==== 通过相减得到高通（式 4.4-14）

非锐化掩模(unsharp mask)是用图像减去它的模糊副本得到的。在频域中，这相当于从原图中减去低通滤波后的图像：

$ f_"hp" (x,y) = f(x,y) - f_"lp" (x,y). $

由于 DFT 是线性的，这等价于用下面的滤波器对 $f$ 滤波：

$ H_"hp" (u,v) = 1 - H_"lp" (u,v). $

取高斯低通 $H_"lp" (u,v) = exp(-frac(D^2, 2 sigma^2))$ 时，对应的高通滤波器在中心处为 0（去掉直流分量），在远离中心处趋近于 1。因为 $H_"lp" (0,0) = 1$，低通图像保留了 $f$ 的均值，所以差图像 $f - f_"lp"$ 的均值为零：平坦区域接近 0，边缘处既有正值也有负值。

==== $sigma$ 的作用

$sigma$ 是高斯函数在频域中的宽度，因此它与教材中高斯滤波器的截止频率 $D_0$ 作用相同。图 4.26 的 (a)、(b)、(c) 三个子图分别对应 $D_0 = 15, 30, 80$ 的高斯高通结果。所以图 4.26(c) 对应较大的 $sigma$，约为 80。

==== 高提升滤波（扩展）

在减去低通图像之前，先把原图乘以常数 $A >= 1$，得到

$ f_"hb" (x,y) = A f(x,y) - f_"lp" (x,y) = (A - 1) f(x,y) + f_"hp" (x,y). $

$A = 1$ 时就是普通的高通图像。$A$ 越大，加回的原图成分越多，结果看起来就像边缘被增强后的原图。

=== 代码组织
#table(
  columns: (auto, 1fr),
  align: left,
  table.header[*文件*][*作用*],
  [`src/dft.py`], [自行实现的二维 DFT:`dft2d`、`idft2d`、`center`、`spectrum`、`filter_freq`（复制自 04-03）],
  [`src/gaussian_filter.py`], [`gaussian_lowpass(M, N, sigma, center_uv)`（复制自 04-03）],
  [`src/utils.py`], [`load_image`、`save_fig`、`save_image`（复制自 04-03）],
  [`src/main.py`], [(a)、(b) 两个必做部分],
  [`src/extra.py`], [扩展实验（第 #ref(<sec-04-ext>, supplement: none) 节）],
  [`test/`], [额外测试图像及其结果（第 #ref(<sec-04-general>, supplement: none) 节）],
)

图像 `Fig0418.jpeg`（尺寸 $688 times 688$）存放在 `data/` 中，所有输出都保存到 `results/`。本文件夹不依赖任何其他项目文件夹。

所有运算都使用 float64。带符号的差图像 $f - g$ 只在显示和保存时才被截断或缩放，绝不在相减之前处理。

=== 部分 (a)：减去 04-03(b) 的结果 <sec-04-a>

*方法。* 用 04-03(b) 中选定的 $sigma$（即 $sigma = 30$）计算低通图像 $g$，再得到高通图像 $f_"hp" = f - g$。

#figure(
  image("/0404/results/fig01_0404_a.png", width: 100%),
  caption: [fig01_0404_a.png：原图、低通结果($sigma = 30$)及其差 $f - g$。],
) <fig-a>

*为什么结果与图 4.26 不相似。*

+ *运算本身是相同的，差异只来自参数和显示。* 第 #ref(<sec-04-equiv>, supplement: none) 节的数值结果表明，$f - g$ 与用 $H_"hp" = 1 - H_"lp"$ 滤波的结果一致，最大误差约为 $1.1 times 10^(-10)$。取相同 $D_0$ 的高斯高通会得到完全相同的图像。因此结果与图 4.26 不同，不是因为"相减"与"高通滤波"是两种不同的运算，而是因为参数与显示方式不同。
+ *$sigma$ 当初是为了另一个目的选的。* 在 04-03(b) 中，选 $sigma = 30$ 是为了让低通图像接近图 4.18(c) 的模糊效果，这对应频域中较窄的低通。把它减掉之后，剩下的是很宽的一段频带，所以 $f - g$ 仍保留了大量图像结构（第 #ref(<sec-04-energy>, supplement: none) 节：约 27% 的图像能量），边缘又粗又亮。图 4.26(c) 对应的 $D_0 = 80$ 要大得多，只留下细边缘（约 15% 的能量）。
+ *显示方式的缩放。* 差图像均值为零且含有负值。线性拉伸(min-max)会把平坦区域显示成中灰色，而把负值截断则显示成黑色。教材中的图是深色背景，因此即使数据完全相同，显示方式也会让外观差别很大。
+ *动态范围。* 保留下来的细节相对于完整的 0 到 255 范围很小，不重新缩放的话图像显得又暗又淡。

=== 部分 (b)：调整 $sigma$

*步骤。* 让低通 $sigma$ 取 15、30、80，分别对应图 4.26(a)、(b)、(c) 的 $D_0$。每个结果用两种方式显示：min-max 线性拉伸，以及把负值截断为黑色。

#figure(
  image("/0404/results/fig02_0404_sigma15.png", width: 95%),
  caption: [fig02_0404_sigma15.png：$sigma = 15$ 时的 $f -$ 低通结果（左：min-max 拉伸；右：负值截断）。],
) <fig-s15>

#figure(
  image("/0404/results/fig03_0404_sigma30.png", width: 95%),
  caption: [fig03_0404_sigma30.png：$sigma = 30$ 时的 $f -$ 低通结果（左：min-max 拉伸；右：负值截断）。],
) <fig-s30>

#figure(
  image("/0404/results/fig04_0404_sigma80.png", width: 95%),
  caption: [fig04_0404_sigma80.png：$sigma = 80$ 时的 $f -$ 低通结果（左：min-max 拉伸；右：负值截断）。],
) <fig-s80>

取 $sigma = 80$ 时的结果与图 4.26(c) 相似：负值截断的显示中背景为暗色，只在大字母、方块等物体的边缘留下细而淡的轮廓，小的结构只剩微弱痕迹。此时高通结果只保留了约 15% 的图像能量（第 #ref(<sec-04-energy>, supplement: none) 节），而 $sigma = 15$ 时为 41%。

*解释。*

- *频域角度。* $sigma$ 越大，高斯低通越宽，$g$ 越接近原图，$f - g$ 就只保留最高的频率。输出又暗又细、边缘微弱，与图 4.26(c) 一致。
- *空域角度。* 频域中很宽的高斯对应空域中很窄的高斯，对图像只有轻微的模糊。减去一个只被轻微模糊的副本，只会留下很窄的边缘过渡。
- *$sigma$ 较小时* 模糊严重，相减后保留的是粗而亮的结构和大部分图像内容，如图 4.26(a)。
- *显示方式。* 截断负值的显示与教材的深色背景一致；min-max 拉伸则因为 0 被映射成中灰而显得发灰。

=== 对其他图像的推广 <sec-04-general>

同样的流程在 `test/` 中的额外测试图像上运行，算法没有任何改动。结果保存在 `test/test_1_results/` 和 `test/test_2_results/` 中，输出文件与 `results/` 相同。

#table(
  columns: (auto, auto, 1fr, 1fr),
  align: left,
  table.header[*图像*][*尺寸*][*内容*][*结果*],
  [`test_1.bmp`], [$688 times 688$], [《数字图像处理》封面灰度图], [$sigma$ 大时只保留细边缘，$sigma$ 小时保留粗结构],
  [`test_2_results.bmp`], [$688 times 688$], [灰度图：一个头戴图案纸生日帽的幼童], [表现相同],
)

#figure(
  grid(
    columns: 2, gutter: 8pt,
    image("/0404/test/test_1_results/fig04_0404_sigma80.png"),
    image("/0404/test/test_2_results/fig04_0404_sigma80.png"),
  ),
  caption: [test/test_1_results/ 与 test/test_2_results/ 中的 fig04_0404_sigma80.png：额外测试图像的高通结果（$sigma = 80$；左：测试图像 1，右：测试图像 2）。],
) <fig-test>

$sigma$ 的变化趋势对每幅图像都相同：$sigma$ 越大，只保留越细的边缘。至于哪个 $sigma$ 看起来像图 4.26(c)，则取决于图像本身：既取决于图像含有多少细节，也取决于图像尺寸（$sigma$ 以频率采样点为单位，同一个 $sigma$ 在不同尺寸的图像中覆盖的频谱比例不同）。我们的两幅测试图像尺寸均为 $688 times 688$，是方形，但边长不是 2 的幂（第 #ref(<sec-04-sizes>, supplement: none) 节另外检验了非方形图像）。

== 扩展实验与性能 <sec-04-ext>
必做内容比较简单，因此我们还研究了该方法的其他性质。所有实验都在 `src/extra.py` 中，每项计时取 3 次运行中的最好值。

=== 相减与直接高通滤波 <sec-04-equiv>

取 $sigma = 30$，用两种方式计算高通：`f - filter_freq(f, H)` 与 `filter_freq(f, 1 - H)`。两者的最大绝对差为 *$1.10 times 10^(-10)$*，处于浮点舍入误差的水平。这证明了减去低通图像与施加 $1 - H$ 是同一种运算，也是第 #ref(<sec-04-a>, supplement: none) 节解释的依据。直接形式只需一次正变换和一次逆变换，不需要再做减法。

=== 更快的 $sigma$ 扫描

正变换与 $sigma$ 无关。对 8 个 $sigma$ 值(5、10、15、20、30、50、80、100)的扫描，朴素方法对每个值都做一次正变换和一次逆变换（共 16 次变换）；缓存方法只算一次中心化频谱，然后对每个 $sigma$ 乘以 $1 - H$ 并做一次逆变换（共 9 次变换）。加速比的上界为 $16 \/ 9 approx 1.78$。

#table(
  columns: (auto, auto),
  align: left,
  table.header[*方法*][*时间（s）*],
  [朴素（每个 $sigma$ 做正变换和逆变换）], [1.786],
  [缓存频谱], [1.121],
  [加速比], [1.59],
)

两种方法最后都做同样的反中心化和取实部，所以比较是公平的。实测加速比 1.59 略低于 1.78，因为构造滤波器、乘法以及反中心化这些步骤并没有被节省。

=== 高通结果中还保留了多少图像？ <sec-04-energy>

为了用数字而不是凭眼睛来选 $sigma$，我们计算了高通之后保留的图像能量比例：

$ E(sigma) = frac(sum f_"hp"^2 (x,y), sum (f(x,y) - overline(f))^2), $

其中减去均值 $overline(f)$ 是因为高通去掉了直流分量。

#table(
  columns: (auto,) + (auto,) * 8,
  align: center,
  table.header[*$sigma$*][*5*][*10*][*15*][*20*][*30*][*50*][*80*][*100*],
  [保留的能量], [0.6929], [0.5185], [0.4147], [0.3485], [0.2693], [0.1988], [0.1471], [0.1219],
)

#figure(
  image("/0404/results/ext_energy.png", width: 70%),
  caption: [ext_energy.png：高通所保留的图像能量比例随 $sigma$ 的变化。],
) <fig-energy>

曲线随 $sigma$ 增大而单调下降，这与"输出越来越暗、越来越淡"的视觉印象一致，并给出了一个描述输出"有多高通"的数字。$sigma = 80$ 时保留的能量为 0.147，约为 $sigma = 15$ 时(0.415)的 0.35 倍。曲线在 $sigma$ 较大时下降变缓：从 $sigma = 50$ 到 100，能量只从 0.199 降到 0.122。

=== 高提升滤波

用 $f_"hb" = A f - f_"lp"$，取 $A = 1, 1.5, 2$，得到保留原图内容并增强边缘的锐化图像。$A = 1$ 就是 (a) 部分的普通高通图像。$A$ 越大，结果越接近边缘被放大的原图。显示时大于 255 的值被截断。

#figure(
  image("/0404/results/ext_highboost.png", width: 95%),
  caption: [ext_highboost.png：高提升滤波($sigma = 30$；$A = 1, 1.5, 2$)。],
) <fig-hb>

$A = 1$ 时结果只含边缘，背景为黑色；随着 $A$ 增大，原图的灰度内容被加回，$A = 2$ 时已经是边缘被增强的原图。因为 $f_"hb" = (A - 1) f + f_"hp"$，$A$ 越大亮区越容易超过 255 而被截断。

=== 其他图像尺寸 <sec-04-sizes>

在一幅非方形的裁剪图（尺寸 $671 times 648$，其中 671 为奇数）上重复了第 #ref(<sec-04-equiv>, supplement: none) 节的等价性检验，最大差值为 *$1.33 times 10^(-10)$*，说明该方法不依赖方形或 2 的幂次的尺寸。对于奇数边长，$(-1)^(x+y)$ 对应的移位量 $M \/ 2$ 不是整数，直流分量不会恰好落在某个整数频率点上，因此中心化只是近似的，需要精确居中时应相应设置滤波器中心；但两种计算方式使用的是同一套线性运算，等价性本身不受影响。

== 关键代码
=== `src/main.py`
```python
from dft import *
from gaussian_filter import *
from utils import *
import numpy as np

f = load_image()
M, N = f.shape

def scale(a):
    return 255 * (a - a.min()) / (a.max() - a.min())

# Part (a): subtract the 04-03(b) lowpass result
fig_idx = 1
sigma_a = 30   # as 04-03(b)
g = filter_freq(f, gaussian_lowpass(M, N, sigma_a))
hp = f - g

plt.figure(figsize=(15, 5))
plt.subplot(1, 3, 1); plt.imshow(f, cmap="gray", vmin=0, vmax=255); plt.title("Original f")
plt.subplot(1, 3, 2); plt.imshow(g, cmap="gray", vmin=0, vmax=255); plt.title(f"Lowpass g, sigma={sigma_a}")
plt.subplot(1, 3, 3); plt.imshow(np.clip(hp, 0, 255), cmap="gray", vmin=0, vmax=255); plt.title("f - g")
save_fig(f"fig{fig_idx:02d}_0404_a.png")
plt.show()
fig_idx += 1

# Part (b): vary sigma
for s in [15, 30, 80]:
    hp = f - filter_freq(f, gaussian_lowpass(M, N, s))

    plt.figure(figsize=(10, 5))
    plt.subplot(1, 2, 1); plt.imshow(scale(hp), cmap="gray"); plt.title(f"min-max scaled, sigma={s}")
    plt.subplot(1, 2, 2); plt.imshow(np.clip(hp, 0, 255), cmap="gray", vmin=0, vmax=255); plt.title(f"negatives clipped, sigma={s}")
    save_fig(f"fig{fig_idx:02d}_0404_sigma{s}.png")
    plt.show()
    fig_idx += 1
```

=== `src/extra.py`（实验核心部分）
```python
# equivalence: f - lowpass  ==  filtering with (1 - H)
H = gaussian_lowpass(M, N, sigma)
hp_subtract = f - filter_freq(f, H)
hp_direct = filter_freq(f, 1 - H)
print(np.max(np.abs(hp_subtract - hp_direct)))

# cached sigma sweep: forward DFT only once
def sweep_cached():
    Fc = dft2d(center(f))
    for s in sigmas:
        np.real(center(idft2d(Fc * (1 - gaussian_lowpass(M, N, s)))))

# energy kept
total = np.sum((f - f.mean()) ** 2)
hp = np.real(center(idft2d(Fc * (1 - gaussian_lowpass(M, N, s)))))
kept = np.sum(hp ** 2) / total

# high-boost
hb = np.clip(A * f - g, 0, 255)
```

== 实验结果
用原图减去高斯低通图像，恰好就是用高斯高通滤波器 $1 - H_"lp"$ 滤波，所以 (a) 部分的结果与图 4.26 不同，只是由于 04-03(b) 中选的 $sigma$（由那里想要的模糊程度决定）以及显示缩放造成的。把 $sigma$ 增大到约 80，就得到了类似图 4.26(c) 的结果：深色背景上又细又淡的边缘。除必做部分外，我们还用数值验证了这种等价性（误差 $1.1 times 10^(-10)$），通过缓存频谱降低了 $sigma$ 扫描的开销（加速比 1.59，上界 1.78），测量了高通中残留的能量随 $sigma$ 的变化（$sigma = 15$ 时 41%，$sigma = 80$ 时 15%），实现了高提升滤波，并确认该方法对其他图像以及非方形、含奇数边长的图像同样适用。
