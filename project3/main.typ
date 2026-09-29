#import "../dvdbr3o.typ/src/dvdbr3o.typ": *

#show: dvdbr3otypst.with(
  title: [DCS229 图像处理 \ 综合实验报告],
  subtitle: [Laplacian 锐化、Unsharp Masking 与相关子实验],
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

本报告汇总 DCS229 课程中围绕“图像增强算子在高性能计算平台上的实现与优化”展开的系列实验。所有子实验共用同一套基础设施：由 `common` 模块提供的、与图像格式无关的 RGBA8 统一抽象，以及统一的命令行入口与 Catch2 测试/基准框架。

== 子实验一览

#simple-table(
  (0.8fr, 1.6fr, 1.4fr, 0.9fr),
  table.header([编号], [主题], [核心算子], [负责人]),
  [0305], [Laplacian 图像增强], [$g = f - nabla^2 f$], [代骏泽],
  [0306], [Unsharp Masking 图像增强], [$g = f + "amount" (f - "blur" f)$], [代骏泽],
  [0302], [待定子实验（预留）], [——], [Y.Surayya],
)

== 统一的实验框架

三个子实验共享同一套工程约定，这里统一说明，后续各章不再重复：

- *统一图像抽象*：`common` 把 PNG / JPEG 解码为 8 位 RGBA、行优先的连续缓冲（`dcs229::ImageView`），算子只面向一种内存布局——每像素 4 字节，字节序 `R, G, B, A`，只处理前三个颜色通道、alpha 原样透传。
- *命令行入口*：每个子实验都是一个 CLI11 程序，支持位置参数与 `-i/-o` 两种写法，并按输出扩展名自动选择编码器（`.png` / `.jpg` / `.jpeg`）。
- *测试与基准*：Catch2 单元测试覆盖解析解、CPU 变体一致性、GPU 一致性与端到端流程；性能用 Catch2 `BENCHMARK` 宏测量。
- *多后端实现*：每个算子都提供 CPU 的四种等价实现（标量 / 分块 / OpenMP / AVX2 SIMD）与 CUDA 实现，便于横向比较。

#pagebreak()

= 0302

#info[
  *状态：待开展。* 本子实验由 Y.Surayya 负责，尚在选题 / 设计阶段，以下仅预留章节骨架，内容待后续补充。
]

== 实验原理

_（待补充。）_

== 实验设计

_（待补充。计划沿用本报告的统一框架：RGBA8 抽象、CLI11 入口、Catch2 测试与基准。）_

// 预留：子实验结构表
// #simple-table(
//   (1.1fr, 2.4fr),
//   table.header([文件], [作用]),
//   ...,
// )

== 测试与验证

_（待补充。）_

// 预留：输入 / 输出对比图
// #pair("...", "...", [说明])

== 性能基准

_（待补充。）_

// 预留：benchmark 图
// #fig("public/0302_bench_256x256.png", [说明], width: 92%)

== 实验结论

_（待补充。）_

#pagebreak()


= 0305 Laplacian 锐化

== 实验原理

=== Laplacian 算子

连续域中，二维函数 $f(x, y)$ 的 Laplacian 定义为二阶偏导之和：

$ nabla^2 f = (partial^2 f) / (partial x^2) + (partial^2 f) / (partial y^2) $

在数字图像中，常用四邻域（十字）模板对其进行离散化：

$ L = mat(0, 1, 0; 1, -4, 1; 0, 1, 0) $

该模板对图像中的灰度突变（边缘）响应强烈，而在平坦区域响应接近零，因此是一个高通算子。

=== 用 Laplacian 做锐化

要让图像变锐，可以把高通分量叠加回原图。本实验采用 Gonzalez & Woods 中的减法形式：

$ g(x, y) = f(x, y) - nabla^2 f(x, y) $

把该式展开，等价于与下面这个 3×3 相关核做卷积：

$ K = mat(0, -1, 0; -1, 5, -1; 0, -1, 0) $

边缘处被减去的 Laplacian 与原值反号，因此亮侧更亮、暗侧更暗，视觉上更锐利。由于 3×3 模板在边界处无法取满四个邻域，本实现将边界像素原样输出，不做处理。

== 实验设计

=== 核心算子

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

=== CPU w/ scalar

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

=== CPU w/ cache-friendly tiling

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

=== CPU w/ OpenMP

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

=== CPU w/ AVX2 SIMD

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

=== GPU w/ CUDA

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

=== 命令行入口

`main.cu` 基于 CLI11，支持位置参数与 `-i/-o` 两种写法，并从输出扩展名自动选择编码器：

```cpp
CLI::App app {"Laplacian image enhancement (CUDA)"};
app.add_option("infile", pos_input, "input image path");
app.add_option("-i,--input", opt_input, "input image path (alternative to positional)");
app.add_option("-o,--output", opt_output, "output image path");
app.add_option("-q,--quality", quality, "JPEG quality, 1-100")->check(CLI::Range(1, 100));
// ...解析后：load_image -> laplacian_sharpen -> save_image
```

== 测试与验证

=== Catch2 测试

共 17 个测试用例、超过 7700 条断言，覆盖：

- *解析解*：常量图不变、边界透传、alpha 不变、孤立冲激的已知响应、台阶边缘、棋盘格；
- *一致性*：四种 CPU 变体与参考实现逐字节一致（含 $1times N$、$N times 1$ 等退化尺寸）；
- *端到端*：经典素材图的解码、编码往返（PNG 无损、JPEG 有损容差）；
- *GPU*：CUDA 与 CPU 参考实现逐字节一致。

=== 端到端结果

下面给出经典图像处理素材在 Laplacian 增强前后的对比（左为输入，右为输出）。可以看到羽毛、帽檐等细节处的对比度被明显提升，而平坦区域几乎不变。

#pair(
  "../0305/tests/data/lena.png",
  "../0305/tests/data/lena_out.png",
  [Lena：左为输入，右为 Laplacian 增强结果],
)

#pair(
  "../0305/tests/data/board.png",
  "../0305/tests/data/board_out.png",
  [电路板：细密走线与丝印在增强后更清晰],
)

#pair(
  "../0305/tests/data/baboon.png",
  "../0305/tests/data/baboon_out.png",
  [Baboon：毛发纹理的高频成分被放大],
)

#pair(
  "../0305/tests/data/checkerboard.png",
  "../0305/tests/data/checkerboard_out.png",
  [棋盘格：黑白交界被推向两端并保持图案稳定],
)

== 性能基准

使用 Catch2 的 `BENCHMARK` 宏，在合成噪声图上分别对每种实现重复采样，取平均耗时。测试环境为 NVIDIA RTX 4060 Laptop GPU，CPU 支持 AVX2 与 OpenMP。

#fig(
  "../0305/public/0305_bench_256x256.png",
  [256×256 图像上各实现的平均耗时（越低越好，下方标注相对最快实现的加速比）],
  width: 92%,
)

#fig(
  "../0305/public/0305_bench_1024x1024.png",
  [1024×1024 图像上各实现的平均耗时],
  width: 92%,
)

=== 结果分析

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

这也说明：微基准的数字必须在明确的测量边界下解读——本章测的是完整的“调用一次增强函数”的延迟，而不是纯粹的 kernel 时间。

== 实验结论

- Laplacian 减法形式 $g = f - nabla^2 f$ 能有效增强边缘，且在平坦区近似恒等，符合高通增强的预期。
- 基于统一 RGBA8 抽象的实现对图像格式完全无感，新增一种输入格式无须改动算子。
- 四种 CPU 变体在数值上与参考实现逐字节一致，说明优化没有破坏正确性。
- 在 3×3 小核场景下，向量化（AVX2）与多线程（OpenMP）是性价比最高的优化；GPU 的优势需要更大的图像或避免每次拷贝才能体现。

#pagebreak()

= 0306 Unsharp Masking

== 实验原理

=== Unsharp Masking

非锐化掩蔽是经典的锐化方法，其核心思想是“原图减去（模糊后的）低频分量得到高频掩蔽，再把掩蔽加回原图”：

$ "mask" = f - "blur"(f) $
$ g = f + "amount" dot "mask" $

其中 $f$ 为输入，$g$ 为输出，`blur` 为低通滤波，`amount` 控制增强强度。当 $"amount" = 0$ 时输出等于输入；`amount` 越大，边缘处过冲/下冲越明显。

=== 可分离高斯模糊

本实验用高斯核作为低通滤波器。核的半径取 $r = ceil(3 sigma)$，即覆盖 $plus.minus 3 sigma$ 范围（约 $99.7%$ 的权重），并归一化使权重和为 $1$：

$ G(x) = exp(-x^2 \/ (2 sigma^2)) $

由于高斯核可分离，二维卷积可以拆成水平、垂直两次一维卷积，复杂度从 $O(r^2)$ 降到 $O(2r)$：

$ "blur"(f) = G_x * (G_y * f) $

边界采用“复制填充”（replicate padding）：越界的采样坐标被夹取到最近的边缘像素，避免引入黑边。

=== 与 Laplacian 锐化的比较

#simple-table(
  (0.8fr, 1.4fr, 1.4fr),
  table.header([项目], [Laplacian 锐化（0305）], [Unsharp Masking（0306）]),
  [高通来源], [二阶导（$5 times 5$ 型十字核）], [原图 - 高斯模糊],
  [可调参数], [无], [`amount`、`sigma`],
  [计算量], [每像素固定 5 次读取], [随 `sigma` 增长，两次可分离卷积],
  [边界处理], [边界透传], [复制填充],
)

== 实验设计

=== 高斯核构造

半径取 $ceil(3 sigma)$，权重归一化，并对 $sigma <= 0$ 做退化处理：

```cpp
[[nodiscard]] inline auto gaussian_kernel(float sigma) -> std::vector<float> {
    const float s      = std::max(sigma, 1e-3f);
    const int   radius = std::max(0, static_cast<int>(std::ceil(3.0f * s)));
    const int   size   = 2 * radius + 1;
    const float inv_two_sigma_sq = 1.0f / (2.0f * s * s);

    std::vector<float> kernel(static_cast<size_t>(size));
    float sum = 0.0f;
    for (int i = 0; i < size; ++i) {
        const float x = static_cast<float>(i - radius);
        kernel[i] = std::exp(-(x * x) * inv_two_sigma_sq);
        sum += kernel[i];
    }
    for (auto& weight : kernel) weight /= sum;   // 归一化
    return kernel;
}
```

=== 核心算子

参考实现显式地做水平、垂直两次可分离卷积，再做点式混合。`clamp_index` 实现复制填充，`clamp_channel` 在写回前做 $[0,255]$ 截断：

```cpp
// 水平 pass
for (size_t y = 0; y < h; ++y)
  for (size_t x = 0; x < w; ++x)
    for (size_t c = 0; c < ch; ++c) {
      float acc = 0.0f;
      for (int k = -radius; k <= radius; ++k) {
        const auto sx = clamp_index(static_cast<long long>(x) + k, w);
        acc += kernel[k + radius] * static_cast<float>(src[y * stride + sx * ch + c]);
      }
      tmp[y * stride + x * ch + c] = acc;
    }

// 垂直 pass + 混合
for (...) {
  float acc = 0.0f;
  for (int k = -radius; k <= radius; ++k) {
    const auto sy = clamp_index(static_cast<long long>(y) + k, h);
    acc += kernel[k + radius] * at(tmp, x, sy, c);
  }
  const float f = static_cast<float>(src[y * stride + x * ch + c]);
  dst[y * stride + x * ch + c] = clamp_channel<Channel>(f + amount * (f - acc));
}
```

其中复制填充的实现：

```cpp
[[nodiscard]] inline auto clamp_index(long long index, size_t extent) -> size_t {
    if (index < 0) return 0;
    const auto upper = static_cast<long long>(extent) - 1;
    if (index > upper) return static_cast<size_t>(upper);
    return static_cast<size_t>(index);
}
```

=== CPU w/ scalar

最直接的实现：先跑一遍标量水平高斯，再跑一遍“垂直高斯 + 混合”。两个 pass 都写成独立函数，便于其它变体复用：

```cpp
template<typename Channel>
inline auto blur_h_scalar(const Channel* in, float* out, size_t width, size_t height,
                          size_t channels, size_t stride, const float* taps, int radius) -> void {
    for (size_t y = 0; y < height; ++y)
        for (size_t x = 0; x < width; ++x)
            for (size_t c = 0; c < channels; ++c) {
                float acc = 0.0f;
                for (int k = -radius; k <= radius; ++k) {
                    const auto sx = clamp_index(static_cast<long long>(x) + k, width);
                    acc += taps[k + radius] * static_cast<float>(in[y * stride + sx * channels + c]);
                }
                out[y * stride + x * channels + c] = acc;
            }
}
```

=== CPU w/ cache-friendly tiling

水平 pass 与标量相同，垂直 pass 则按水平条带 `tile_height` 切分，使垂直方向需要反复读取的若干行 float 数据尽量留在缓存里：

```cpp
for (size_t tile_y = 0; tile_y < height; tile_y += tile_height) {
    const size_t y_end = std::min(tile_y + tile_height, height);
    for (size_t y = tile_y; y < y_end; ++y) {
        for (size_t x = 0; x < width; ++x) {
            for (size_t c = 0; c + 1 < 4; ++c) {          // 跳过 alpha
                float acc = 0.0f;
                for (int k = -radius; k <= radius; ++k) {
                    const auto sy = clamp_index(static_cast<long long>(y) + k, height);
                    acc += taps[k + radius] * tmp[sy * width * 4 + x * 4 + c];
                }
                const float f = static_cast<float>(in[y * width * 4 + x * 4 + c]);
                out[y * width * 4 + x * 4 + c] = clamp_channel<unsigned char>(f + amount * (f - acc));
            }
            out[y * width * 4 + x * 4 + 3] = in[y * width * 4 + x * 4 + 3];
        }
    }
}
```

=== CPU w/ OpenMP

两个 pass 的行循环都可以安全并行。用带符号计数并提前算好上界，满足 `parallel for` 的规范形式：

```cpp
const auto last_row = static_cast<long long>(height);
#if defined(_OPENMP)
#   pragma omp parallel for schedule(static)
#endif
for (long long y = 0; y < last_row; ++y) { /* 水平 pass */ }

#if defined(_OPENMP)
#   pragma omp parallel for schedule(static)
#endif
for (long long y = 0; y < last_row; ++y) { /* 垂直 pass + 混合 */ }
```

=== CPU w/ AVX2 SIMD

水平 pass 是瓶颈所在，因此把它向量化：先按通道把整行数据摊平到一个*带复制填充*的 float 缓冲 `row_buf`，再用滑窗对每个抽头做一次向量乘加，每次处理 8 个像素：

```cpp
// 把该行第 c 个通道的像素搬到 row_buf 中间，两端复制填充
for (size_t x = 0; x < width; ++x)
    row_buf[x + radius] = static_cast<float>(src_row[x * 4 + c]);
for (int k = 0; k < radius; ++k) {
    row_buf[radius - 1 - k]          = row_buf[radius];
    row_buf[width + radius + k]      = row_buf[width + radius - 1];
}

// 滑窗乘加，8 像素/次
for (; x + 8 <= width; x += 8) {
    __m256 acc = _mm256_setzero_ps();
    for (int k = -radius; k <= radius; ++k) {
        const auto tap = _mm256_set1_ps(taps[k + radius]);
        const auto v   = _mm256_loadu_ps(row_buf.data() + x + radius + k);
        acc = _mm256_add_ps(acc, _mm256_mul_ps(tap, v));
    }
    float lanes[8];
    _mm256_storeu_ps(lanes, acc);
    for (size_t i = 0; i < 8; ++i) out_row[(x + i) * 4 + c] = lanes[i];
}
```

垂直 pass 仍复用标量版本。运行时不支持 AVX2 时回退到 `tiled`：

```cpp
if (!__builtin_cpu_supports("avx2")) { tiled(out, in, width, height, sigma, amount); return; }
```

=== GPU w/ CUDA

GPU 端用两个 kernel 对应可分离的两步。第一步水平高斯把 RGBA8 转成 float 中间结果：

```cpp
__global__ void _unsharp_blur_h(const unsigned char* __restrict__ in, float* __restrict__ out,
                                size_t width, size_t height, const float* __restrict__ taps, int radius) {
    const size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    const size_t y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= width || y >= height) return;
    const size_t stride = width * 4;
    for (size_t c = 0; c < 4; ++c) {
        float acc = 0.0f;
        for (int k = -radius; k <= radius; ++k) {
            const long long sx = static_cast<long long>(x) + k;
            const size_t cx = sx < 0 ? 0 : (sx >= width ? width - 1 : static_cast<size_t>(sx));
            acc += taps[k + radius] * static_cast<float>(in[y * stride + cx * 4 + c]);
        }
        out[y * stride + x * 4 + c] = acc;
    }
}
```

第二步在垂直高斯之后*就地*完成混合与截断，省去一次全局访存：

```cpp
for (size_t c = 0; c < 3; ++c) {
    float acc = 0.0f;
    for (int k = -radius; k <= radius; ++k) {
        const long long sy = static_cast<long long>(y) + k;
        const size_t cy = sy < 0 ? 0 : (sy >= height ? height - 1 : static_cast<size_t>(sy));
        acc += taps[k + radius] * blurred_h[cy * stride + x * 4 + c];
    }
    const float f     = static_cast<float>(original[y * stride + x * 4 + c]);
    const float value = f + amount * (f - acc);                 // g = f + amount*(f - blur)
    out[y * stride + x * 4 + c] = value <= 0 ? 0 : (value >= 255 ? 255 : value + 0.5f);
}
out[y * stride + x * 4 + 3] = original[y * stride + x * 4 + 3];  // alpha 透传
```

=== 命令行入口

`main.cu` 基于 CLI11，除输入/输出外还暴露增强强度与模糊尺度，并对参数做范围校验：

```cpp
CLI::App app {"Unsharp masking image enhancement (CUDA)"};
app.add_option("-a,--amount", amount, "mask strength (>0 sharpens, 0 copies input)")
   ->check(CLI::NonNegativeNumber)->capture_default_str();
app.add_option("-s,--sigma",  sigma,  "Gaussian blur standard deviation in pixels")
   ->check(CLI::PositiveNumber)->capture_default_str();
app.add_option("-q,--quality", quality, "JPEG quality, 1-100")->check(CLI::Range(1, 100));
```

== 测试与验证

=== Catch2 测试

共 13 个测试用例、超过 100 万条断言（大图逐像素比较贡献了其中的绝大部分），覆盖：

- *解析解*：高斯核归一化且对称、常量图不变、`amount = 0` 为恒等、alpha 不变；
- *定性行为*：台阶边缘亮侧过冲 / 暗侧下冲、孤立冲激中心变亮而邻域变暗、`amount` 越大增强越强；
- *一致性*：四种 CPU 变体与参考实现逐像素一致（容差 $lt.eq 1$）；
- *GPU*：CUDA 与 CPU 参考实现逐像素一致；
- *端到端*：经典素材图的解码与增强。

=== 端到端结果

下面给出经典素材在 unsharp masking 前后对比（左为输入，右为输出）。可以看到电路板走线、羽毛等细节的高频分量被加强，而平坦背景基本不变。

#pair(
  "../0306/tests/data/lena.png",
  "../0306/tests/data/lena_out.png",
  [Lena：左为输入，右为 unsharp masking 结果],
)

#pair(
  "../0306/tests/data/board.png",
  "../0306/tests/data/board_out.png",
  [电路板：细密走线与丝印对比度提升],
)

#pair(
  "../0306/tests/data/baboon.png",
  "../0306/tests/data/baboon_out.png",
  [Baboon：毛发纹理明显更锐利],
)

#pair(
  "../0306/tests/data/checkerboard.png",
  "../0306/tests/data/checkerboard_out.png",
  [棋盘格：黑白交界两侧出现过冲与下冲],
)

一个值得注意的现象是：在 `amount = 0` 时，输出与输入逐像素完全相等（测试中以 RMSE = 0 验证），说明混合公式与掩蔽计算在数值上是自洽的。

== 性能基准

使用 Catch2 的 `BENCHMARK` 宏，在合成噪声图上重复采样取平均耗时。测试环境为 NVIDIA RTX 4060 Laptop GPU；`sigma = 1.5`、`amount = 1.0`。

#fig(
  "../0306/public/0306_bench_256x256.png",
  [256×256 图像上各实现的平均耗时（越低越好，下方标注相对最快实现的加速比）],
  width: 92%,
)

#fig(
  "../0306/public/0306_bench_1024x1024.png",
  [1024×1024 图像上各实现的平均耗时],
  width: 92%,
)

=== 结果分析

在 1024×1024 上，各实现平均耗时约为：

#simple-table(
  (1.2fr, 1fr, 1fr),
  table.header([实现], [耗时], [相对最快]),
  [CUDA], [1.882 ms], [`1.00x`],
  [CPU OpenMP], [7.882 ms], [`0.24x`],
  [CPU SIMD (AVX2)], [27.22 ms], [`0.07x`],
  [CPU 标量], [29.46 ms], [`0.06x`],
  [CPU 分块], [30.84 ms], [`0.06x`],
)

与实验一的 3×3 小核不同，unsharp masking 的计算量随 `sigma` 显著增长（本例核半径 $r = 5$，共 $11$ 个抽头），因此结论也不一样：

- *CUDA* 在这个规模上开始体现优势。虽然同样包含主机 <-> 设备往返，但两次可分离卷积的像素级工作量足以摊平拷贝成本，比最快的 CPU 实现还快约 $4$ 倍。
- *OpenMP* 在 CPU 侧收益最明显（约 $3.7$ 倍），因为两个 pass 都是 embarrassingly parallel。
- *AVX2* 相对标量只有约 $8%$ 的提升：本实现只向量化了水平 pass，而垂直 pass —— 需要跨行 stride 跳读、访存不连续 —— 仍是瓶颈。若要进一步提升，应对垂直方向也做向量化（如转置后按行处理）。
- *分块* 同样未带来收益，说明该算子的瓶颈在计算与跨行访存，而非单纯的行级缓存复用。

== 实验结论

- Unsharp masking 通过“原图 - 高斯模糊”构造高通掩蔽并用 `amount` 调节强度，其边缘过冲/下冲行为与 Laplacian 锐化同属高频增强，但提供了更直观的控制参数。
- 可分离高斯把 $O(r^2)$ 的二维卷积降为两次 $O(r)$ 的一维卷积，是让 CPU/GPU 都能高效实现的关键。
- 四种 CPU 变体与 CUDA 实现均与参考实现数值一致（容差 $lt.eq 1$），验证了优化的正确性。
- 性能上：重内核场景下 CUDA 优势明显；CPU 侧 OpenMP 收益最大，而仅向量化水平 pass 的 AVX2 受限于垂直方向的非连续访存。

#pagebreak()


= 分工说明

本综合报告由以下成员协作完成，各子实验的负责人与具体分工如下：

#simple-table(
  (0.8fr, 2.0fr, 1.2fr, 0.8fr),
  table.header([子实验], [主题], [负责人], [具体分工]),
  [0302], [待定子实验], [Y.Surayya], [all],
  [0305], [Laplacian 图像增强], [代骏泽], [all],
  [0306], [Unsharp Masking], [代骏泽], [all],
)

共享基础设施（`common` 模块的格式无关图像抽象、编解码、统一的测试与基准脚本）由两位成员共同使用与维护。
