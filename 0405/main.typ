// ============================================================
//  Project 04-05 实验报告（单独报告）
//  统一结构：1 实验要求 / 2 实验过程 / 3 扩展实验与性能 / 4 关键代码 / 5 实验结果
//  图片路径以项目根目录为基准（如 "/0405/results/xxx.png"），请与 0403、0404、0405 文件夹放在同一根目录下编译
// ============================================================

#set document(title: "Project 04-05 实验报告")
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

// 子图辅助：cap("/0405/", "results/xxx.png")[说明文字]
#let cap(base, img, label) = [#image(base + img) #align(center)[#text(size: 8.5pt)[#label]]]

// Project 标题 + 课程 / 组别 / 负责人
#let project-part(id, title, author) = [
  #heading(level: 1, title)
  #align(center)[#text(size: 10.5pt)[课程：数字图像处理 #h(1.5em) 组别：20 #h(1.5em) 负责人：#author]]
  #v(0.4em)
]

#project-part("0405", "Project 04-05：频域相关", "代骏泽")

== 实验要求
- 用 DFT 实现二维相关：$ g(x,y) = "IDFT"(F(u,v) dot overline(T(u,v))) $，即把图像与模板都做傅里叶变换，取模板变换的复共轭后相乘，再求傅里叶反变换。
- 复现教材例 4.11（图 4.41）：把模板图 4.41(b) 在图像图 4.41(a) 中定位，显示相关函数图 4.41(e)，并画出通过其最高值的水平灰度剖面图 4.41(f)。

所使用的二维傅里叶变换来自我们在 Project 04-01 中的自实现，处理链路中不使用 `np.fft`。

除必做项之外，我们还研究了：(i) 直接（按定义）相关与 DFT 相关是否一致，以及 DFT 快多少；(ii) 相关的时间如何随图像尺寸增长；(iii) 图像均值不为零时朴素相关为什么会失效；(iv) 同一套代码能否定位另一个模板；(v) 非方形、含奇数边长的图像；(vi) 习题 4.22 与 4.23。

== 实验过程

=== 理论基础
==== 相关的定义

两个函数 $f$ 与 $t$ 的相关（correlation）定义为

$ f(x,y) star t(x,y) = sum_(s,t) f(s,t) thin t(s - x, t - y), $

等价地（对实函数）可写成滑动点积：$g(x,y)$ 是模板 $t$ 平移到 $(x,y)$ 时与原图的点积。相关与卷积的区别只在于：卷积会把模板翻转，相关不会。因此相关适合做“模板匹配”：模板与图中某处完全一致时，相关在该处取最大值。

==== 用 DFT 计算相关

沿用卷积定理的思想（式 4.6.31），相关的傅里叶变换满足

$ cal(F)\{f star t\} = overline(F(u,v)) thin T(u,v), $

教材使用的形式是

$ g(x,y) = "IDFT"( F(u,v) dot overline(T(u,v)) ), $

即对图像取正变换，对模板取正变换后复共轭，二者逐点相乘再做反变换。两种写法只差一个整体共轭，而相关函数关于中心对称的特性使它们得到的峰值位置互为镜像（第 #ref(<sec-05-ex>, supplement: none) 节会给出数值验证）。

==== 零填充与最小尺寸

为了让 DFT 计算的*循环*相关等于*线性*相关，必须先把图像和模板分别零填充到至少

$ P >= A + C - 1, quad Q >= B + D - 1, $

其中 $A times B$ 是图像尺寸、$C times D$ 是模板尺寸。例 4.11 中 $A = B = 256$、$C = 38$、$D = 42$，故 $P = 293$、$Q = 297$。教材把尺寸取整为 $298 times 298$，我们使用精确的最小值。

==== 与频域滤波的区别

频域滤波时要先乘 $(-1)^(x+y)$ 把直流分量搬到中心，滤波器也以中心为准。相关*不是*平移不变的滤波操作，不能这样做：我们直接把零填充后的数组送入 DFT，直流分量留在 $(0,0)$，最后也不做去中心化。这样相关函数的峰值出现在模板左上角所落的位置上，与教材从延拓图像上读出的点是同一个点。

=== 代码组织
#table(
  columns: (auto, 1fr),
  align: left,
  table.header[*文件*][*作用*],
  [`src/dft.py`], [自实现的二维 DFT：`dft2d`、`idft2d`、`center`、`spectrum`（Project 04-01）],
  [`src/correlation.py`], [`pad_to`、`circular_correlate`、`linear_correlate`、`find_target`、`match_at`],
  [`src/utils.py`], [`load_image`、`save_fig`、`save_image`：把指向 `data/` 与 `results/` 的路径集中在同一处],
  [`src/make_example_image.py`], [构造例 4.11 的输入图像与模板],
  [`src/main.py`], [必做部分：定位模板、画相关函数与剖面线],
  [`src/extra.py`], [扩展实验（第 #ref(<sec-05-ext>, supplement: none) 节）],
  [`test/testing_correlation.py`], [验证相关是否正确（第 #ref(<sec-05-verify>, supplement: none) 节）],
  [`test/run_tests.py`], [同一流程在其他测试图像上的运行（第 #ref(<sec-05-general>, supplement: none) 节）],
)

==== 关于素材

附件提供的 `4.41a.jpg` 是图 4.41(a) 的一个*裁剪*——只保留了 “UTK” 三个字母，而 `4.41b.png` 就是其中的 “T” 本身（尺寸 $44 times 49$，不是例 4.11 所说的 $38 times 42$），且并未落在图像正中。为忠实复现例 4.11（256$times$256 图像、模板是图像的复制且位于中部），`make_example_image.py` 把这两个裁剪重新排布为：

- `data/example_a.png`：$256 times 256$ 黑底，把 “UTK” 块放在中央；
- `data/example_b.png`：从 `example_a.png` 中切出的 “T” 模板。

`main.py` 同时处理*两组素材*：重排后的例 4.11 素材（`example_a/b`）与附件原素材（`Fig0441a/b`）。

=== 部分 (a)：定位模板 <sec-05-a>

*流程。* 读入图像 $f$ 与模板 $t$，零填充到 $P times Q = 299 times 304$，按上式求相关 $g$，取最大值的位置即为模板所在处。

#table(
  columns: (auto, auto, auto, auto, auto),
  align: center,
  table.header[*素材*][*图像*][*模板*][*峰值位置*][*峰值 / 均值*],
  [`example_a/b`], [$256 times 256$], [$44 times 49$], [$(106, 97)$], [110.2],
  [`Fig0441a/b`], [$256 times 256$], [$44 times 49$], [$(106, 102)$], [63.7],
)

#figure(
  image("/0405/results/fig02_0405_padded.png", width: 100%),
  caption: [fig02_0405_padded.png：例 4.11 布局下零填充后的图像（左）与模板（右），对应图 4.41(c) 与 (d)。],
) <fig-padded>

#figure(
  grid(
    columns: 2, gutter: 10pt,
    cap("/0405/", "results/fig_ex_a_detect.png")[重排素材],
    cap("/0405/", "results/fig_sup_a_detect.png")[附件素材],
  ),
  caption: [fig_ex_a_detect.png（左）与 fig_sup_a_detect.png（右）：图像 $f$、模板 $t$，以及相关峰值处切出的窗口。两者都与模板逐像素一致。],
) <fig-detect>

#figure(
  grid(
    columns: 2, gutter: 10pt,
    cap("/0405/", "results/fig_ex_e_corr.png")[重排素材],
    cap("/0405/", "results/fig_sup_e_corr.png")[附件素材],
  ),
  caption: [fig_ex_e_corr.png（左）与 fig_sup_e_corr.png（右）：相关函数 $g$ 以图像方式显示（灰度取对数拉伸），红色十字为峰值。对应图 4.41(e)。],
) <fig-corr>

#figure(
  grid(
    columns: 2, gutter: 10pt,
    cap("/0405/", "results/fig_ex_f_profile.png")[重排素材],
    cap("/0405/", "results/fig_sup_f_profile.png")[附件素材],
  ),
  caption: [fig_ex_f_profile.png（左）与 fig_sup_f_profile.png（右）：通过最高值的水平灰度剖面线。对应图 4.41(f)。],
) <fig-profile>

*结果。* 两组素材的相关函数都出现一个*尖锐的单峰*：重排素材的峰/均值比高达 110，附件素材为 63.7，而其它位置的取值都低一个数量级以上（#ref(<fig-profile>) 的剖面线）。峰值处切出的窗口与模板逐像素相同，归一化互相关系数（NCC）为 $1.0000$。这与教材“相关函数的最大值正好出现在模板所在的点上”的结论一致。

*关于显示。* 相关函数大部分区域接近 0，峰值却高出几个数量级，直接按线性灰度显示会几乎全黑。我们把灰度做对数拉伸后再显示（#ref(<fig-corr>) 左），既保留峰值又能看见周围的次级结构；剖面线（#ref(<fig-profile>)）则用原始数值，可以看清主峰与旁瓣的数量级差异。

=== 验证（`test/testing_correlation.py`） <sec-05-verify>

在做定位之前，先验证相关本身的正确性。所有图像以 `float64` 载入。

#table(
  columns: (1.8fr, 1.2fr, auto),
  align: (left, left, left),
  table.header[*检查项*][*最大误差*][*结论*],
  [DFT 往返 $(8 times 8)$], [$1.3 times 10^(-15)$], [PASS],
  [DFT 往返 $(6 times 10)$], [$1.8 times 10^(-15)$], [PASS],
  [随机图的峰位于真实位置], [$0$], [PASS],
  [峰值窗口等于模板], [$0$], [PASS],
  [DFT 相关 $=$ 直接相关], [$3 times 10^(-14)$（相对峰值）], [PASS],
  [端到端 NCC $= 1$], [$2.0 times 10^(-15)$], [PASS],
  [退化尺寸 $(1 times 1)、(1 times 5)、(5 times 1)、(3 times 3)$], [$<= 1.7 times 10^(-16)$], [PASS],
)

“DFT 相关 $=$ 直接相关”是把 DFT 结果与按定义逐窗口点积的结果比较；两者之差相对峰值只有 $3 times 10^(-14)$，属于浮点舍入水平，说明实现与相关的定义一致。

=== 对其他图像的推广 <sec-05-general>

在不改动算法的情况下，把同一套代码用于另外两幅测试图像（`test/test_1.bmp`，即教材字符测试图；`test/test_2.bmp`，戴图案纸生日帽的幼童灰度图）。模板直接从图像中切出，因此真实位置已知。

#table(
  columns: (auto, auto, auto, auto, auto),
  align: center,
  table.header[*图像*][*尺寸*][*模板*][*真实位置*][*找到的位置*],
  [`test_1.bmp`], [$688 times 688$], [$140 times 160$], [$(300, 250)$], [$(300, 250)$],
  [`test_2.bmp`], [$812 times 812$], [$180 times 200$], [$(60, 300)$], [$(60, 300)$],
)

两组都精确找回了模板（NCC $= 1.0000$）。

#figure(
  grid(
    columns: 2, gutter: 10pt,
    cap("/0405/", "test/test_1_results/detection.png")[`test_1.bmp`],
    cap("/0405/", "test/test_2_results/detection.png")[`test_2.bmp`],
  ),
  caption: [test/test_1_results/ 与 test/test_2_results/ 中的 detection.png：绿框为切出模板的真实位置，红框为相关找到的位置，两者重合。],
) <fig-tests>

== 扩展实验与性能 <sec-05-ext>
必做内容比较简单，因此我们还研究了该方法的其他性质。所有实验都在 `src/extra.py` 中，每项计时取 3 次运行中的最好值。

=== 直接相关与 DFT 相关

按定义直接做相关是两层循环的 $O(M N C D)$ 算法。对 $256 times 256$ 的图与 $44 times 49$ 的模板，两者给出相同的结果（最大绝对差 $6 times 10^(-7)$，相对峰值约 $3 times 10^(-14)$），而耗时分别为：

#table(
  columns: (1.6fr, auto, auto),
  align: left,
  table.header[*方法*][*时间（s）*][*加速比*],
  [DFT 相关（两次变换 + 一次逐点乘）], [0.026], [`1.0x`],
  [直接相关（按定义）], [0.318], [`12.2x`],
)

DFT 把相关从 $O(M N C D)$ 降到两次二维变换的成本，模板越大优势越明显。

=== 时间随图像尺寸的增长

在 $n times n$ 随机图上用固定的 $32 times 32$ 模板测时间：

#table(
  columns: (auto,) + (auto,) * 5,
  align: center,
  table.header[*$n$*][*64*][*128*][*256*][*512*][*1024*],
  [时间（s）], [0.002], [0.006], [0.024], [0.088], [0.405],
)

#figure(
  image("/0405/results/ext2_speed.png", width: 62%),
  caption: [ext2_speed.png：DFT 相关的耗时随图像边长的变化（双对数坐标）。],
) <fig-speed>

双对数斜率为 $1.9$：与“两次变换”的预期一致（矩阵 DFT 在 $n times n$ 上约为 $n^3$，但观测到的指数更低，因为归一化后主要受变换本身的增长控制）。

=== 图像均值不为零时的朴素相关

相关函数里的直流项 $overline(F(0,0)) dot T(0,0)$ 与图像均值成正比。当图像整体偏亮（均值较大）时，这一项会压过真正匹配的贡献，使相关最大值跑到“亮块与亮块重叠最多”的位置，而不是模板所在处。把图像*反相*（$255 - f$，变成亮背景）后：

#table(
  columns: (1.6fr, auto, auto),
  align: left,
  table.header[*相关形式*][*峰值位置*][*峰值 / 均值*],
  [朴素相关（教材写法）], [$(293, 302)$，即右下角], [1.4],
  [均值去除后（归一化）], [$(106, 97)$，正确], [很大],
)

#figure(
  image("/0405/results/ext3_normalized.png", width: 96%),
  caption: [ext3_normalized.png：亮背景下朴素相关（左，峰值在角落）与均值去除后相关（右，峰值在物体处）的对比。],
) <fig-norm>

这种做法就是把模板（以及窗口）减去自身均值再相关，即归一化互相关。教材的例子中图像以黑底为主、均值为 5.2，直流项很小，所以朴素相关同样能得到尖锐的单峰（#ref(<fig-profile>) 右）；但对一般图像，均值去除更稳健。

=== 同一个模板、另一个目标

相关只依赖“模板与窗口是否相似”，与模板的内容无关。把模板换成同一个 “UTK” 块里的 “K” 后，同一段代码把它定位到 $(114, 148)$：

#figure(
  image("/0405/results/ext4_two_templates.png", width: 100%),
  caption: [ext4_two_templates.png：同一套相关代码分别定位 “T”（中）与 “K”（右）。],
) <fig-two>

=== 非方形、含奇数边长的图像

在 $190 times 230$ 与 $189 times 229$（含奇数边长）的裁剪图上重复定位，NCC 均为 $1.0000$。相关性由 DFT 矩阵直接按图像的高、宽构造，既不需要方形，也不需要边长是 2 的幂，更不需要把尺寸补到某个“方便”的值；只需要零填充满足 $P >= A + C - 1$ 即可。

=== 习题 4.22 与 4.23 <sec-05-ex>

*习题 4.23（取另一个变换的共轭）。* 用 $overline(F) dot T$ 代替 $F dot overline(T)$，峰值从 $(106, 97)$ 移到 $(193, 207)$，满足

$ (106 + 193 - 1, thin 97 + 207 - 1) = (298, 303) = (P - 1, Q - 1), $

即峰值关于相关数组中心（$(P-1)/2, (Q-1)/2)$ 与原来的峰值镜像对称，峰值大小完全相同（$2.129 times 10^7$）。这是意料之中的：取共轭把相关翻转成关于中心的反射，所以位置镜像、大小不变。这也说明 #ref(<sec-05-a>) 中两种写法只是整体共轭的差别。

*习题 4.22（省去 $(-1)^u$ 因子）。* 如果把定义里 $t(s-x, t-y)$ 的符号处理错，等价于在频域少乘一个 $(-1)^u$。此时峰值跑到 $(282, 97)$（数组顶部），峰值降到 $1.415 times 10^6$，仅为正确值的 $6.6%$——相关已经不能用来定位模板了。

== 关键代码
=== `src/correlation.py`
```python
def pad_to(f, shape):
    """Zero-pad (bottom/right) f to the given (P, Q) shape."""
    P, Q = shape
    M, N = f.shape
    g = np.zeros((P, Q), dtype=np.float64)
    g[:M, :N] = f
    return g

def circular_correlate(f, tpl, pad, subtract_mean=False):
    """g = IDFT{ F * conj(T) } on the zero-padded arrays."""
    fp = pad_to(f, pad)
    tp = pad_to(tpl, pad)
    if subtract_mean:                     # remove the DC term
        tp[: tpl.shape[0], : tpl.shape[1]] -= tpl.mean()
        fp = fp - fp.mean()
    return np.real(idft2d(dft2d(fp) * np.conj(dft2d(tp))))

def linear_correlate(f, tpl, pad, subtract_mean=False):
    """Exact linear correlation; needs P >= M + C - 1, Q >= N + D - 1."""
    M, N = f.shape
    C, D = tpl.shape
    if pad[0] < M + C - 1 or pad[1] < N + D - 1:
        raise ValueError("pad too small")
    return circular_correlate(f, tpl, pad, subtract_mean)

def find_target(corr):
    """Location (row, col) of the maximum: the template's top-left corner."""
    idx = int(np.argmax(corr))
    return idx // corr.shape[1], idx % corr.shape[1]
```

=== `src/main.py`（必做部分）
```python
img = load("example_a.png")               # 256 x 256
tpl = load("example_b.png")               # 44 x 49 template
(M, N), (C, D) = img.shape, tpl.shape
pad = (M + C - 1, N + D - 1)              # 299 x 304, the exact minimum

corr = linear_correlate(img, tpl, pad, subtract_mean=True)
loc  = find_target(corr)                  # -> (106, 97)
win  = match_at(img, tpl, loc, subtract_mean=True)
```

=== `src/extra.py`（扩展与习题）
```python
# Exercise 4.23: exchange the two transforms -> mirrored peak
F = dft2d(pad_to(img, pad)); T = dft2d(pad_to(tpl, pad))
full    = np.real(idft2d(F * np.conj(T)))
swapped = np.real(idft2d(np.conj(F) * T))

# Exercise 4.22: the factor (-1)^u omitted
u = np.arange(pad[0])[:, None]
omitted = np.real(idft2d(F * np.conj(T) * (-1.0) ** u))

# Bright background: the plain correlation is defeated by the DC term
plain = linear_correlate(bright, tpl, pad, subtract_mean=False)
norm  = linear_correlate(bright, tpl, pad, subtract_mean=True)
```

== 实验结果
我们用自实现的 DFT 完成了二维相关，并把模板在图像中定位。按教材式子的形式 $g = "IDFT"(F dot overline(T))$，在例 4.11 的素材上相关函数出现尖锐的单峰（峰值 / 均值 $= 110$），峰值处切出的窗口与模板逐像素相同（NCC $= 1.0000$），复现了图 4.41(c)–(f)。同一套代码在附件提供的素材、教材字符测试图与一幅灰度照片上都精确找回模板，也适用于非方形、含奇数边长的图像。数值上，DFT 相关与按定义逐窗口点积的结果之差相对峰值仅 $3 times 10^(-14)$，而速度快约 12 倍。此外我们验证了习题 4.23（取另一个变换的共轭会把峰值镜像、大小不变）与习题 4.22（丢掉 $(-1)^u$ 因子后峰值降到 6.6%、无法定位），并指出当图像均值较大时朴素相关会被直流项压垮、需要先去除均值。
