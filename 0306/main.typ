#import "../dvdbr3o.typ/src/dvdbr3o.typ": *

#show: dvdbr3otypst.with(
  title: [DCS229 图像处理 \ 实验报告],
  subtitle: [Unsharp Masking 图像增强与 GPU 加速],
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

- 掌握 unsharp masking（非锐化掩蔽）的原理及其与 Laplacian 锐化的关系。
- 实现可分离高斯模糊下的高通掩蔽，并用强度参数 `amount` 控制增强程度。
- 在统一的 RGBA8 抽象之上，给出 CPU（标量、分块、OpenMP、AVX2 SIMD）与 CUDA 实现。
- 用 Catch2 单元测试验证算法正确性，并在经典数字图像处理素材上做端到端验证与性能对比。

= 实验原理

== Unsharp Masking

非锐化掩蔽是经典的锐化方法，其核心思想是“原图减去（模糊后的）低频分量得到高频掩蔽，再把掩蔽加回原图”：

$ "mask" = f - "blur"(f) $
$ g = f + "amount" dot "mask" $

其中 $f$ 为输入，$g$ 为输出，`blur` 为低通滤波，`amount` 控制增强强度。当 $"amount" = 0$ 时输出等于输入；`amount` 越大，边缘处过冲/下冲越明显。

把它与 Laplacian 锐化对照，可以发现两者是同一家族的不同实现：Laplacian 锐化显式地对二阶导做加权，而 unsharp masking 用整数 $5$ 的核可以看作对 $f - "blur"(f)$ 的近似——本实验采用的正是 Gonzalez & Woods 中的高斯形式。

== 可分离高斯模糊

本实验用高斯核作为低通滤波器。核的半径取 $r = ceil(3 sigma)$，即覆盖 $plus.minus 3 sigma$ 范围（约 $99.7%$ 的权重），并归一化使权重和为 $1$：

$ G(x) = exp(-x^2 \/ (2 sigma^2)) $

由于高斯核可分离，二维卷积可以拆成水平、垂直两次一维卷积，复杂度从 $O(r^2)$ 降到 $O(2r)$：

$ "blur"(f) = G_x * (G_y * f) $

边界采用“复制填充”（replicate padding）：越界的采样坐标被夹取到最近的边缘像素，避免引入黑边。

== 与 Laplacian 锐化的比较

#simple-table(
  (0.8fr, 1.4fr, 1.4fr),
  table.header([项目], [Laplacian 锐化（0305）], [Unsharp Masking（0306）]),
  [高通来源], [二阶导（$5 times 5$ 型十字核）], [原图 - 高斯模糊],
  [可调参数], [无], [`amount`、`sigma`],
  [计算量], [每像素固定 5 次读取], [随 `sigma` 增长，两次可分离卷积],
  [边界处理], [边界透传], [复制填充],
)

= 实验设计

== 代码结构

#simple-table(
  (1.1fr, 2.4fr),
  table.header([文件], [作用]),
  [`src/UnsharpCore.hpp`], [高斯核构造、核心算子与 CPU 参考实现],
  [`src/Unsharp.cuh`], [水平 / 垂直两个 CUDA kernel 与 host 启动函数],
  [`src/UnsharpCpu.hpp`], [标量 / 分块 / OpenMP / AVX2 四种 CPU 实现],
  [`src/main.cu`], [基于 CLI11 的命令行入口],
  [`tests/Unsharp_test.cu`], [Catch2 正确性测试],
  [`tests/Unsharp_bench.cu`], [Catch2 `BENCHMARK` 性能测试],
)

== 高斯核构造

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

== 核心算子（参考实现）

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

== CPU 变体一：标量

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

== CPU 变体二：分块（tiled）

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

== CPU 变体三：OpenMP

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

== CPU 变体四：AVX2 SIMD

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

== GPU 实现（CUDA）

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

== 命令行入口

`main.cu` 基于 CLI11，除输入/输出外还暴露增强强度与模糊尺度，并对参数做范围校验：

```cpp
CLI::App app {"Unsharp masking image enhancement (CUDA)"};
app.add_option("-a,--amount", amount, "mask strength (>0 sharpens, 0 copies input)")
   ->check(CLI::NonNegativeNumber)->capture_default_str();
app.add_option("-s,--sigma",  sigma,  "Gaussian blur standard deviation in pixels")
   ->check(CLI::PositiveNumber)->capture_default_str();
app.add_option("-q,--quality", quality, "JPEG quality, 1-100")->check(CLI::Range(1, 100));
```

= 测试与验证

== Catch2 测试

共 13 个测试用例、超过 100 万条断言（大图逐像素比较贡献了其中的绝大部分），覆盖：

- *解析解*：高斯核归一化且对称、常量图不变、`amount = 0` 为恒等、alpha 不变；
- *定性行为*：台阶边缘亮侧过冲 / 暗侧下冲、孤立冲激中心变亮而邻域变暗、`amount` 越大增强越强；
- *一致性*：四种 CPU 变体与参考实现逐像素一致（容差 $lt.eq 1$）；
- *GPU*：CUDA 与 CPU 参考实现逐像素一致；
- *端到端*：经典素材图的解码与增强。

== 端到端结果

下面给出经典素材在 unsharp masking 前后对比（左为输入，右为输出）。可以看到电路板走线、羽毛等细节的高频分量被加强，而平坦背景基本不变。

#pair(
  "tests/data/lena.png",
  "tests/data/lena_out.png",
  [Lena：左为输入，右为 unsharp masking 结果],
)

#pair(
  "tests/data/board.png",
  "tests/data/board_out.png",
  [电路板：细密走线与丝印对比度提升],
)

#pair(
  "tests/data/baboon.png",
  "tests/data/baboon_out.png",
  [Baboon：毛发纹理明显更锐利],
)

#pair(
  "tests/data/checkerboard.png",
  "tests/data/checkerboard_out.png",
  [棋盘格：黑白交界两侧出现过冲与下冲],
)

一个值得注意的现象是：在 `amount = 0` 时，输出与输入逐像素完全相等（测试中以 RMSE = 0 验证），说明混合公式与掩蔽计算在数值上是自洽的。

= 性能基准

使用 Catch2 的 `BENCHMARK` 宏，在合成噪声图上重复采样取平均耗时。测试环境为 NVIDIA RTX 4060 Laptop GPU；`sigma = 1.5`、`amount = 1.0`。

#fig(
  "public/0306_bench_256x256.png",
  [256×256 图像上各实现的平均耗时（越低越好，下方标注相对最快实现的加速比）],
  width: 92%,
)

#fig(
  "public/0306_bench_1024x1024.png",
  [1024×1024 图像上各实现的平均耗时],
  width: 92%,
)

== 结果分析

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

与 0305 的 3×3 小核不同，unsharp masking 的计算量随 `sigma` 显著增长（本例核半径 $r = 5$，共 $11$ 个抽头），因此结论也不一样：

- *CUDA* 在这个规模上开始体现优势。虽然同样包含主机 <-> 设备往返，但两次可分离卷积的像素级工作量足以摊平拷贝成本，比最快的 CPU 实现还快约 $4$ 倍。
- *OpenMP* 在 CPU 侧收益最明显（约 $3.7$ 倍），因为两个 pass 都是 embarrassingly parallel。
- *AVX2* 相对标量只有约 $8%$ 的提升：本实现只向量化了水平 pass，而垂直 pass —— 需要跨行 stride 跳读、访存不连续 —— 仍是瓶颈。若要进一步提升，应对垂直方向也做向量化（如转置后按行处理）。
- *分块* 同样未带来收益，说明该算子的瓶颈在计算与跨行访存，而非单纯的行级缓存复用。

= 实验结论

- Unsharp masking 通过“原图 - 高斯模糊”构造高通掩蔽并用 `amount` 调节强度，其边缘过冲/下冲行为与 Laplacian 锐化同属高频增强，但提供了更直观的控制参数。
- 可分离高斯把 $O(r^2)$ 的二维卷积降为两次 $O(r)$ 的一维卷积，是让 CPU/GPU 都能高效实现的关键。
- 四种 CPU 变体与 CUDA 实现均与参考实现数值一致（容差 $lt.eq 1$），验证了优化的正确性。
- 性能上：重内核场景下 CUDA 优势明显；CPU 侧 OpenMP 收益最大，而仅向量化水平 pass 的 AVX2 受限于垂直方向的非连续访存。
