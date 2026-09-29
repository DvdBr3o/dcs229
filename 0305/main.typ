#import "../dvdbr3o.typ/src/dvdbr3o.typ": *

#show: dvdbr3otypst.with(
  title: [DCS229 图像处理 \ 实验报告],
  subtitle: [Laplacian 图像增强与 GPU 加速],
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

= 实验目的

- 掌握 Laplacian 算子的离散形式及其在图像锐化中的作用。
- 在统一的 RGBA8 抽象之上，实现一套与图像格式无关的增强流程。
- 分别给出 CPU（标量、分块、OpenMP、AVX2 SIMD）与 CUDA 实现，并比较其性能。
- 用 Catch2 单元测试验证算法正确性，并用经典数字图像处理素材做端到端验证。

= 实验原理

== Laplacian 算子

连续域中，二维函数 $f(x, y)$ 的 Laplacian 定义为二阶偏导之和：

$ nabla^2 f = (partial^2 f) / (partial x^2) + (partial^2 f) / (partial y^2) $

在数字图像中，常用四邻域（十字）模板对其进行离散化：

$ L = mat(0, 1, 0; 1, -4, 1; 0, 1, 0) $

该模板对图像中的灰度突变（边缘）响应强烈，而在平坦区域响应接近零，因此是一个高通算子。

== 用 Laplacian 做锐化

要让图像变锐，可以把高通分量叠加回原图。本实验采用 Gonzalez & Woods 中的减法形式：

$ g(x, y) = f(x, y) - nabla^2 f(x, y) $

把该式展开，等价于与下面这个 3×3 相关核做卷积：

$ K = mat(0, -1, 0; -1, 5, -1; 0, -1, 0) $

边缘处被减去的 Laplacian 与原值反号，因此亮侧更亮、暗侧更暗，视觉上更锐利。由于 3×3 模板在边界处无法取满四个邻域，本实现将边界像素原样输出，不做处理。

== 统一图像抽象

上游 `common` 模块把 PNG / JPEG 统一解码为 8 位 RGBA、行优先的连续缓冲（`dcs229::ImageView`），并把重采样、编解码等细节全部隐藏。于是本实验的算子只需面向一种内存布局：

- 每个像素 4 字节，字节序为 `R, G, B, A`；
- 第 $i$ 个像素的通道 $c$ 位于字节偏移 $4i + c$；
- 只处理前三个颜色通道，alpha 原样透传。

这样做的好处是，整套增强逻辑对输入是 PNG 还是 JPEG、是灰度还是彩色都不敏感，实现了“格式无关”的抽象。

= 实验设计

== 代码结构

#simple-table(
  (1.1fr, 2.4fr),
  table.header([文件], [作用]),
  [`src/LaplacianCore.hpp`], [模板化的 Laplacian 核心与 CPU 参考实现],
  [`src/Laplacian.cuh`], [CUDA kernel 与 host 启动函数],
  [`src/LaplacianCpu.hpp`], [标量 / 分块 / OpenMP / AVX2 四种 CPU 实现],
  [`src/main.cu`], [基于 CLI11 的命令行入口],
  [`tests/Laplacian_test.cu`], [Catch2 正确性测试],
  [`tests/Laplacian_bench.cu`], [Catch2 `BENCHMARK` 性能测试],
)

== 核心算子（参考实现）

参考实现用模板表达通道类型，并借助 `acc_t` 把 8 位像素提升到宽类型再计算，避免中间结果溢出：

```cpp
template<typename Channel, typename Sampler>
constexpr auto sharpen_channel(const Sampler& at, size_t x, size_t y) noexcept -> Channel {
    using acc_t = /* int（整型通道）或 Channel（浮点通道） */;
    const auto center = static_cast<acc_t>(at(x, y));
    const auto lap    = laplacian_at<Channel>(at, x, y);   // up+down+left+right-4*center
    return clamp_channel<Channel>(center - lap);           // 截断回 [0,255]
}
```

其中 `laplacian_at` 读取十字邻域：

```cpp
template<typename Channel, typename Sampler>
constexpr auto laplacian_at(const Sampler& at, size_t x, size_t y) noexcept {
    const acc_t center = static_cast<acc_t>(at(x, y));
    const acc_t up     = static_cast<acc_t>(at(x, y - 1));
    const acc_t down   = static_cast<acc_t>(at(x, y + 1));
    const acc_t left   = static_cast<acc_t>(at(x - 1, y));
    const acc_t right  = static_cast<acc_t>(at(x + 1, y));
    return static_cast<acc_t>(up + down + left + right - 4 * center);
}
```

== CPU 变体一：标量

最朴素的逐像素实现。先把四条边界整行/整列原样拷贝，再对内部区域做三重循环（行、列、颜色通道），alpha 单独透传：

```cpp
for (size_t y = 1; y + 1 < height; ++y) {
    const auto* above = in + (y - 1) * stride;
    const auto* row   = in + y * stride;
    const auto* below = in + (y + 1) * stride;
    auto*       dst   = out + y * stride;
    for (size_t x = 1; x + 1 < width; ++x) {
        const size_t base = x * 4;
        for (size_t c = 0; c < 3; ++c) {          // 只处理 R/G/B
            const int center = row[base + c];
            const int lap    = above[base + c] + below[base + c]
                             + row[base - 4 + c] + row[base + 4 + c] - 4 * center;
            int value        = center - lap;
            value            = value < 0 ? 0 : (value > 255 ? 255 : value);
            dst[base + c]    = static_cast<unsigned char>(value);
        }
        dst[base + 3] = row[base + 3];             // alpha 原样拷贝
    }
}
```

== CPU 变体二：分块（cache-friendly）

与标量版数学完全相同，只是把内部循环按水平条带 `tile_height` 切分，让三条源行与目标行尽量留在 L1/L2；边界则用一次整缓冲 `std::copy` 处理：

```cpp
std::copy(in, in + stride * height, out);          // 先整体拷贝，保证边界一致
for (size_t tile_y = 1; tile_y + 1 < height; tile_y += tile_height) {
    const size_t y_end = std::min(tile_y + tile_height, height - 1);
    for (size_t y = tile_y; y < y_end; ++y) {
        /* 同标量版的三重循环 */
    }
}
```

== CPU 变体三：OpenMP

把内部行循环并行化。为了避免 `#pragma omp parallel for` 对无符号边界的限制，用带符号的 `long long` 计数，并提前算好上界：

```cpp
const auto last_row = static_cast<long long>(height) - 1;
#if defined(_OPENMP)
#   pragma omp parallel for schedule(static)
#endif
for (long long y = 1; y < last_row; ++y) {
    /* 每一行独立计算，无数据竞争 */
}
```

== CPU 变体四：AVX2 SIMD

每次处理 8 个像素（32 字节）。关键点在于：四个邻域之和最大可达 $4 times 255 = 1020$，超过 8 位，因此必须先 `unpack` 到 16 位再相加；算完 $5 c - sum$ 后用饱和指令截断到 $[0,255]$，最后用 alpha 掩码把原 alpha 混回去：

```cpp
const __m256i center = load(row + base);
const __m256i up     = load(above + base);
const __m256i down   = load(below + base);
const __m256i left   = load(row + base - 4);
const __m256i right  = load(row + base + 4);

// 先扩展到 16 位，再做四路求和
const __m256i c_lo = _mm256_unpacklo_epi8(center, zero);
const __m256i c_hi = _mm256_unpackhi_epi8(center, zero);
const __m256i s_lo = sum16(up, down, left, right, /*high=*/false);
const __m256i s_hi = sum16(up, down, left, right, /*high=*/true);

// value = 5*center - (up + down + left + right)
const __m256i five = _mm256_set1_epi16(5);
__m256i lo = _mm256_sub_epi16(_mm256_mullo_epi16(c_lo, five), s_lo);
__m256i hi = _mm256_sub_epi16(_mm256_mullo_epi16(c_hi, five), s_hi);

// 饱和截断到 [0, 255]
lo = _mm256_min_epi16(_mm256_max_epi16(lo, zero), max);
hi = _mm256_min_epi16(_mm256_max_epi16(hi, zero), max);

const __m256i packed   = _mm256_packus_epi16(lo, hi);
const __m256i alpha_mask = _mm256_set1_epi32(0xFF000000u);
const __m256i blended    = _mm256_blendv_epi8(packed, center, alpha_mask);
_mm256_storeu_si256(reinterpret_cast<__m256i*>(dst + base), blended);
```

> 这里有一个容易踩的坑：`_mm256_unpacklo_epi8` / `unpackhi_epi8` 是*按 128 位通道分别*工作的，因此 `lo` 实际覆盖字节 $\{0..7, 16..23\}$、`hi` 覆盖 $\{8..15, 24..31\}$。`packus_epi16` 再把它们重新交织回原始顺序，所以*不需要*额外的跨通道 `permute`——多加一步 `_mm256_permute4x64_epi64` 反而会把像素顺序打乱。

== GPU 实现（CUDA）

CPU 端同样提供一个 dispatch：若运行时不支持 AVX2 则回退到 `tiled`：

```cpp
if (!__builtin_cpu_supports("avx2")) { tiled(out, in, width, height); return; }
```

GPU 采用“一个线程负责一个内部像素”的映射：线程 $(x,y)$ 读取十字邻域，边界像素直接透传。逐像素计算只依赖相邻内存，访问对显存合并友好：

```cpp
__global__ void _laplacian(unsigned char* out, const unsigned char* image,
                           size_t width, size_t height) {
    const size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    const size_t y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;

    const size_t stride = width * 4;
    const size_t pixel  = (y * width + x) * 4;
    const bool   border = (x == 0 || y == 0 || x + 1 == width || y + 1 == height);
    for (size_t c = 0; c < 3; ++c)
        out[pixel + c] = border ? image[pixel + c]
                                : detail::sharpen_pixel(image, x, y, width, stride, c);
    out[pixel + 3] = image[pixel + 3];   // alpha 透传
}
```

启动时用 $16 times 16$ 的线程块覆盖整幅图：

```cpp
constexpr unsigned block = 16;
const dim3 threads(block, block);
const dim3 grid((width + block - 1) / block, (height + block - 1) / block);
_laplacian<<<grid, threads, 0, stream>>>(dev_out, dev_in, width, height);
```

== 命令行入口

`main.cu` 基于 CLI11，支持位置参数与 `-i/-o` 两种写法，并从输出扩展名自动选择编码器（`.png` / `.jpg` / `.jpeg`）：

```cpp
CLI::App app {"Laplacian image enhancement (CUDA)"};
app.add_option("infile", pos_input, "input image path");
app.add_option("-i,--input", opt_input, "input image path (alternative to positional)");
app.add_option("-o,--output", opt_output, "output image path");
app.add_option("-q,--quality", quality, "JPEG quality, 1-100")->check(CLI::Range(1, 100));
// ...解析后：load_image -> laplacian_sharpen -> save_image
```

= 测试与验证

== Catch2 测试

共 17 个测试用例、超过 7700 条断言，覆盖：

- *解析解*：常量图不变、边界透传、alpha 不变、孤立冲激的已知响应、台阶边缘、棋盘格；
- *一致性*：四种 CPU 变体与参考实现逐字节一致（含 $1times N$、$N times 1$ 等退化尺寸）；
- *端到端*：经典素材图的解码、编码往返（PNG 无损、JPEG 有损容差）；
- *GPU*：CUDA 与 CPU 参考实现逐字节一致。

== 端到端结果

下面给出经典图像处理素材在 Laplacian 增强前后的对比（左为输入，右为输出）。可以看到羽毛、帽檐等细节处的对比度被明显提升，而平坦区域几乎不变。

#pair(
  "tests/data/lena.png",
  "tests/data/lena_out.png",
  [Lena：左为输入，右为 Laplacian 增强结果],
)

#pair(
  "tests/data/board.png",
  "tests/data/board_out.png",
  [电路板：细密走线与丝印在增强后更清晰],
)

#pair(
  "tests/data/baboon.png",
  "tests/data/baboon_out.png",
  [Baboon：毛发纹理的高频成分被放大],
)

#pair(
  "tests/data/checkerboard.png",
  "tests/data/checkerboard_out.png",
  [棋盘格：黑白交界被推向两端并保持图案稳定],
)

= 性能基准

使用 Catch2 的 `BENCHMARK` 宏，在合成噪声图上分别对每种实现重复采样，取平均耗时。测试环境为 NVIDIA RTX 4060 Laptop GPU，CPU 支持 AVX2 与 OpenMP。

#fig(
  "public/0305_bench_256x256.png",
  [256×256 图像上各实现的平均耗时（越低越好，下方标注相对最快实现的加速比）],
  width: 92%,
)

#fig(
  "public/0305_bench_1024x1024.png",
  [1024×1024 图像上各实现的平均耗时],
  width: 92%,
)

== 结果分析

在 1024×1024 上，各实现平均耗时约为：

#simple-table(
  (1.2fr, 1fr, 1fr),
  table.header([实现], [耗时], [相对最快]),
  [CPU SIMD (AVX2)], [441.4 us], [`1.00x`],
  [CPU OpenMP], [453.8 us], [`0.97x`],
  [CPU 标量], [843.5 us], [`0.52x`],
  [CPU 分块], [989.6 us], [`0.45x`],
  [CUDA], [1.182 ms], [`0.37x`],
)

可以观察到：

- 对小核（3×3）、逐像素访存密集的算子，*AVX2 与 OpenMP* 是最有效的加速手段，二者接近内存带宽上限；
- *分块* 在这个规模上没有带来收益，反而因为额外的缓冲区拷贝而略慢于标量版本；
- *CUDA* 的数字包含了每次调用的主机 <-> 设备往返拷贝，属于“朴素端到端”耗时；在这样的小图上拷贝成本占主导，因此并不比 CPU 快。若把图像放大或改为常驻显存，GPU 才会体现出优势。

这也说明：微基准的数字必须在明确的测量边界下解读——本实验测的是完整的“调用一次增强函数”的延迟，而不是纯粹的 kernel 时间。

= 实验结论

- Laplacian 减法形式 $g = f - nabla^2 f$ 能有效增强边缘，且在平坦区近似恒等，符合高通增强的预期。
- 基于统一 RGBA8 抽象的实现对图像格式完全无感，新增一种输入格式无须改动算子。
- 四种 CPU 变体在数值上与参考实现逐字节一致，说明优化没有破坏正确性。
- 在 3×3 小核场景下，向量化（AVX2）与多线程（OpenMP）是性价比最高的优化；GPU 的优势需要更大的图像或避免每次拷贝才能体现。
