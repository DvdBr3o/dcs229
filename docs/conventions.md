# DCS229 工程规范（面向 AI 协作）

本文档总结本仓库的目录结构、代码风格、构建方式与实验报告规范，供 AI 助手在修改代码或撰写文档时遵循。**规范以现有代码为准**：当你拿不准时，先找仓库里已有的同类文件作为模板，保持一致，而不是引入新的写法。

> 面向 AI 的入口文件是仓库根目录的 `AGENTS.md`；本文件是它的展开版。

## 适用范围（重要）

各成员的技术栈可能不同，因此文档分成两类：

- **通用规范**（第 1、4、5、6、7 节的报告/资源/流程部分）：与语言、构建工具无关，只要在本仓库做事就适用。
- **C++ / xmake 规范**（第 2、3 节，以及第 4 节的 Catch2 部分）：**仅当选择 C++ + xmake 技术栈时**才适用。若某个子实验用别的技术栈，不必套用 xmake 与 `.clang-format`，只需遵守通用规范，并保持目录**结构**一致（`src/`、`tests/`、`public/`、`main.typ` 等）。

---

## 1. 仓库结构

```
dcs229/
├── common/              # 共享静态库 dcs229.common
│   └── src/
│       ├── Image.cpp
│       └── dcs229/
│           ├── Image.hpp    # RGBA8 统一图像抽象 + 编解码
│           └── Bench.hpp    # 计时辅助
├── 0305/               # 子实验：Laplacian 图像增强
│   ├── src/             # 实现（.cu / .cuh / .hpp / .cpp）
│   ├── tests/           # Catch2 测试与 benchmark
│   │   └── data/        # 测试素材（图片 + README.md）
│   ├── public/          # 报告用图（benchmark 图、原始输出、README.md）
│   ├── main.typ         # 实验报告（Typst）
│   └── xmake.lua
├── 0306/               # 子实验：Unsharp Masking（结构同 0305）
├── project3/           # 综合报告（汇总各子实验）
│   └── main.typ
├── dvdbr3o.typ/        # 共享 Typst 模板包（不要改动其内容）
├── tools/              # 辅助脚本
│   ├── bench_plot.py    # 运行 benchmark 并出图到 <project>/public/
│   └── build_reports.sh # 编译所有 Typst 报告
├── docs/
│   └── conventions.md  # 本规范文档
├── AGENTS.md           # 面向 AI 的仓库入口
├── xmake.lua           # 根构建脚本
├── .clang-format / .clang-tidy
└── .gitignore
```

**约定**

- 子实验目录名即实验编号（`0302`、`0305`、`0306`…）。新增子实验时复制一个现有子实验的目录布局。
- 每个子实验目录固定包含 `src/`、`tests/data/`、`public/`、`main.typ`（采用 C++ + xmake 技术栈时另含 `xmake.lua`）。
- 不在子实验目录下再分一层模块；C++ 共享代码一律进 `common/`。

---

## 2. 构建系统（xmake）

> **适用范围**：仅当子实验采用 C++ + xmake 技术栈时适用。其他技术栈请用各自的构建方式，但保持目录结构一致。

- 构建工具是 **xmake**（`>= 3.1`）。所有目标都用 `xmake build` / `xmake run` 驱动，不要手写 g++ 命令行。
- 根 `xmake.lua` 通过 `includes()` 引入各子目录；新增子实验要在根 `xmake.lua` 加一行 `includes("<编号>")`。
- 子实验的 `xmake.lua` 通常定义三个目标：

  | 目标 | 作用 |
  | --- | --- |
  | `<编号>` | CLI 可执行文件 |
  | `<编号>.tests` | Catch2 测试 |
  | `<编号>.bench` | Catch2 benchmark |

**xmake.lua 写法约定**

- 依赖用 `add_requires("...")` 声明（如 `catch2`、`cli11`、`openmp`、`libspng`、`libjpeg-turbo`）。
- 统一 `set_languages("cxxlatest")`、`set_kind("binary")`（库为 `static`）。
- 依赖 `common`：`add_deps("dcs229.common")`。
- 每个 CUDA 目标加 `add_cugencodes("native")`；需要向量化时加 `add_cxflags("-mavx2")`，CUDA 侧对应 `add_cuflags("-Xcompiler", "-mavx2", {force = true})`。
- 测试数据目录用 `add_defines('DCS229_TEST_DATA_DIR="' .. path.join(os.scriptdir(), "tests", "data") .. '"')` 注入，测试里通过该宏定位素材。
- CLI/bench 目标要加 `set_rundir(path.directory(os.scriptdir()))`，使 `xmake r <编号> <相对路径>` 能按仓库根目录解析路径。

**常用命令**

```sh
xmake f -c -y                      # 重新配置
xmake build                        # 构建全部
xmake build 0305 0305.tests        # 构建指定目标
xmake r 0305 0305/tests/data/board.png 0305/tests/data/board_out.png
xmake run 0305.tests               # 跑测试
xmake run 0305.tests -- "[cuda]"   # 按 tag 过滤
xmake run 0305.bench -- --benchmark-samples 30
```

---

## 3. C++ 代码规范

> **适用范围**：仅当子实验采用 C++（+ xmake）技术栈时适用。

### 3.1 格式化（`.clang-format`）

- 基于 **Google** 风格，但：`UseTab: Always`、`IndentWidth: 4`、`ColumnLimit: 100`、`PointerAlignment: Left`、`SortIncludes: Never`、`IncludeBlocks: Preserve`。
- 提交前对改动的 C++ 文件跑 `clang-format -i <file>`。**不要手工对齐**会被 clang-format 覆盖的内容。
- 注意 clang-format 对 `auto operator=(T&&) noexcept -> T& = default;` 这类声明的对齐可能与直觉不同；如果格式结果难以阅读，可以就地微调但不要违反 ColumnLimit。

### 3.2 语言与惯用法

- 使用 **C++26**（`cxxlatest`）；CUDA 侧用 `-std=c++20`（nvcc 限制）。
- 采用现代风格：`auto` 返回值、`->` 尾置返回类型、`[[nodiscard]]`、`constexpr`、`noexcept`、`concepts`、指定初始化器。
- 类遵循「RAII + 只移动」：删除拷贝构造/赋值，移动构造标记 `noexcept`；CUDA/C 资源用小的 RAII guard（见 `common/src/Image.cpp` 的 `SpngCtx`、`TjHandle`、`BufferOwner`）。
- 错误处理用异常（`std::runtime_error`），消息格式为 `"<动作>: <细节>"`。
- 头文件用 `#pragma once`；测试专用宏、平台宏加 `DCS229_` 前缀（如 `DCS229_ARCH_X86`）。
- include 顺序保持：本文件对应头 → 第三方头 → 标准库；**不要让 clang-format 排序 include**（`SortIncludes: Never` 已固定）。
- 命名：类型 `PascalCase`，函数/变量 `snake_case`，模板参数 `PascalCase`，私有成员 `_leading_underscore`，命名空间 `dcs229` 或 `dcs229::proj<编号>`。
- 每个非平凡实现都写清楚**中文或英文注释说明为什么**，尤其是算法边界（如 SIMD 的 lane 顺序、边界填充策略）。

### 3.3 统一图像抽象

- 所有算子面向 `dcs229::ImageView`：8 位 RGBA、行优先、每像素 4 字节、`size == width * height * 4`。
- 只处理前三个颜色通道，**alpha 原样透传**。
- 解码用 `dcs229::load_image()`（返回 owning 的 `AnyImage`）；不要用返回非拥有 `ImageView` 的 `decode_image()` 跨越语句存活期。
- 编码用 `dcs229::save_image(view, path, quality)`，按扩展名（`.png` / `.jpg` / `.jpeg`）分派。

---

## 4. 测试与基准（Catch2）

> **适用范围**：本节前半（测试覆盖类别、素材约定）是**通用**的——无论用什么技术栈，子实验都应覆盖这些类别、并把素材按约定存放。后半（Catch2 的具体写法）仅当采用 C++ + xmake 技术栈时适用。

**测试覆盖类别（通用，参考 0305/0306 现有测试）**

- **解析解**：常量图不变、边界/alpha 处理、孤立冲激、台阶边缘、棋盘格等可手算的用例；
- **一致性**：所有实现变体与参考实现逐像素一致（SIMD/OpenMP 容差通常 `<= 1`）；含 `1xN`、`Nx1`、`3x3` 等退化尺寸；
- **端到端**：解码 → 处理 → 编码往返（PNG 无损、JPEG 有损容差）；
- **定性行为**：如锐化后平均梯度增大、`amount = 0` 为恒等。

**测试素材（通用）**：放 `tests/data/`，同目录写 `README.md` 说明来源与许可。素材一律存为 **8 位 PNG** 以保证可复现；文件名用 `<name>.png`，处理后输出为 `<name>_out.png`。

**Catch2（仅 C++ + xmake 技术栈）**

- 测试文件放 `<项目>/tests/`，命名为 `<算子>_test.cu`；benchmark 为 `<算子>_bench.cu`。
- **测试与 benchmark 分目标、分文件**：benchmark 用 `BENCHMARK` 宏并打上 `[benchmark]` tag，避免污染常规测试。
- CUDA 测试必须先探测设备（`cudaGetDeviceCount`），无设备时 `SKIP`，**不要**用 `try/catch` 捕获 `SKIP` 抛出的异常。
- 若比较 `std::vector<char>` 像素缓冲，需为该类型提供 Catch2 的 `StringMaker` 特化（否则 Catch2 会把它当字符串导致崩溃/乱码）——见 `0305/tests/Laplacian_test.cu`。

---

## 5. 基准出图（tools/bench_plot.py）

- 出图脚本：`python3 tools/bench_plot.py <项目> [--samples N]`。
- 它运行 `<项目>.bench`（需要先 `xmake build <项目>.bench`），把原始输出存为 `<项目>/public/<项目>_bench.txt`，并渲染 `<项目>/public/<项目>_bench_<WxH>.{svg,png}`。
- 图表约定：柱状图越短越好，柱顶标平均耗时，柱下标相对最快实现的加速比；`cpu scalar / tiled / openmp / simd / cuda` 颜色在脚本 `PALETTE` 中固定，新增变体要在此登记颜色。
- benchmark 数字必须在报告里**注明测量边界**（例如 CUDA 是否含主机↔设备拷贝），避免误读。

---

## 6. 实验报告规范（Typst）

### 6.1 依赖与编译

- 每份报告首行 `#import "../dvdbr3o.typ/src/dvdbr3o.typ": *`，随后 `#show: dvdbr3otypst.with(title: ..., subtitle: ..., author: [代骏泽], xno: [24363012])`。
- 模板包在仓库根目录，报告在子目录，因此**必须用仓库根作为 Typst root**：

  ```sh
  typst compile --root . 0305/main.typ 0305/main.pdf
  tools/build_reports.sh           # 一次性编译全部报告
  tools/build_reports.sh 0305      # 只编译一个
  ```

- 生成的 `main.pdf` 已在 `.gitignore` 中忽略，不要提交。

### 6.2 文档结构（以 `project3/main.typ` 为准）

综合报告用一级标题组织，顺序与命名如下：

```
= 实验概览            # 子实验一览表 + 统一实验框架（共享约定集中讲一次）
= <编号> <主题>       # 例如 = 0302 / = 0305 Laplacian 锐化 / = 0306 Unsharp Masking
    == 实验原理
        === <小节>
    == 实验设计
        === 核心算子
        === CPU w/ scalar
        === CPU w/ <变体名>
        === GPU w/ CUDA
        === 命令行入口
    == 测试与验证
        === Catch2 测试
        === 端到端结果
    == 性能基准
        === 结果分析
    == 实验结论
= 分工说明
```

**撰写约定**

- **以 `project3/main.typ` 为最新的规范范本。** 同目录下独立的 `0305/main.typ`、`0306/main.typ` 是较早期版本，小节命名尚未与综合报告统一（例如用 `== CPU 变体一：标量` 而非 `=== CPU w/ scalar`）。新增/修改报告时遵循本节的规范；若顺手改到独立报告，应向范本看齐。
- 各章**不重复**“实验目的”与共享框架说明（在概览章统一写）。章节直接从“实验原理”开始。
- 子实验章节统一命名 `<编号> <主题>`，编号在前、空格分隔，不加“实验一/二/三”之类序号前缀。
- 实现小节统一用 `XX w/ YY` 命名，且**同一层级内名称要一致**：`CPU w/ scalar`、`CPU w/ cache-friendly tiling`、`CPU w/ OpenMP`、`CPU w/ AVX2 SIMD`、`GPU w/ CUDA`。
- 每个实现小节**必须贴关键代码**（```cpp 代码块），并配一段说明“为什么这样做/关键点是什么”。代码要与仓库实际实现一致。
- 未开展的子实验（如 0302）保留章节骨架：用 `#info[ *状态：待开展。* ... ]` 标注，各小节写 `_（待补充。）_`，并用注释预留图表位置（`// #simple-table(...)`、`// #pair(...)`）。
- “分工说明”章用表格列出每个子实验的负责人；共享基础设施单独说明。

### 6.3 表格与图表（重要）

- **必须用 Typst 表格**：`#simple-table(...)` 辅助函数（在文件顶部定义），**禁止** Markdown 竖线表格（`| a | b |`）——Typst 会把竖线当普通字符原样渲染。
- 图片用文件顶部定义的辅助函数：
  - `#fig("path.png", [caption], width: 92%)` —— 单图；
  - `#pair(a, b, [caption])` —— 左右并排的输入/输出对比图。
- 报告中的图片路径**相对该 `.typ` 文件**：子实验报告用 `tests/data/...`、`public/...`；综合报告用 `../0305/...`、`../0306/...`。
- 每个 `#simple-table` 第一行用 `table.header([列名], ...)` 作为表头。
- 数值/单位/加速比写进表格时，带小数点的比值（如 `1.00x`）用反引号包成代码（`` `1.00x` ``），否则 Typst 可能吞掉小数点。
- 行内代码用反引号，数学公式用 `$ ... $`。Typst 数学符号用点号路径：`plus.minus`（±）、`lt.eq`（≤）、`nabla^2`、`times` 等；**不要**写 LaTeX 风格的 `\pm` / `\le`。
- 中文正文用全角标点；`实验报告` 标题里的换行用 `\`（如 `[DCS229 图像处理 \ 综合实验报告]`）。

### 6.4 图片资源位置

| 资源 | 位置 |
| --- | --- |
| 测试素材（输入） | `<项目>/tests/data/<name>.png` |
| 增强结果（输出） | `<项目>/tests/data/<name>_out.png` |
| benchmark 图 | `<项目>/public/<项目>_bench_<WxH>.{png,svg}` |
| benchmark 原始输出 | `<项目>/public/<项目>_bench.txt` |

生成方式：先 `xmake build <项目>`，对每个素材跑一遍 CLI 输出到 `tests/data/<name>_out.png`；再 `xmake build <项目>.bench` + `python3 tools/bench_plot.py <项目>`。

---

## 7. 提交前检查清单

**通用（任何技术栈）**

1. `tools/build_reports.sh` 能编译全部报告（Typst 报错必须修复）。
2. 若改了实现，同步更新报告中对应的**代码片段、耗时数字与结论**，并重新生成 `public/` 下的图。
3. 不提交 `build/`、`*.pdf`、`compile_commands.json`、`dvdbr3o.typ/` 的本地改动等衍生文件。

**C++ + xmake 技术栈**

4. `clang-format -i` 处理改动过的 C/C++/CUDA 文件。
5. `xmake build` 全绿、无新增警告。
6. `xmake run <项目>.tests` 全通过；涉及 SIMD/OpenMP/CUDA 的改动要确认相应 tag 也跑过。
