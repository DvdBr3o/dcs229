# AGENTS.md

本仓库是 DCS229 图像处理课程的一系列子实验，核心工作是「图像增强算子在 CPU/GPU 上的实现、测试、基准与实验报告」。

与 AI 助手协作时，请先读 `docs/conventions.md`——那里有完整的目录结构、代码风格、构建方式与报告规范。本文件只列最关键的约束。

## 适用范围（重要）

各成员的技术栈可能不同，因此把约定分成两部分：

- **通用约定**：只要你在本仓库做事就适用——报告、图片资源、素材来源与许可、分工登记等。与用什么语言/构建工具无关。
- **C++ / xmake 约定**：**仅当**你选择用 C++ + xmake 这条技术路线时才适用。若某个子实验用的是别的技术栈（例如另一种语言、另一套构建），不必套用 xmake 与 `.clang-format` 那套，只需遵守通用约定，并与现有目录布局保持一致的“结构”（`src/`、`public/`、`main.typ` 等）。

## 通用约定（任何技术栈）

- **报告用 Typst**：依赖根目录的 `dvdbr3o.typ` 模板包，编译必须带 `--root .`（或用 `tools/build_reports.sh`）。
- **Typst 表格必须用 `#simple-table(...)`**，禁止 Markdown 竖线表格（`| ... |`）——会被原样当字符渲染。
- **报告结构以 `project3/main.typ` 为范本**：章节命名、`XX w/ YY` 小节、`#fig`/`#pair` 用法、分工表等，详见 `docs/conventions.md` 第 6 节。
- **图片资源位置固定**：测试素材（输入）放 `<项目>/tests/data/<name>.png`，增强结果放 `<项目>/tests/data/<name>_out.png`，报告用图放 `<项目>/public/`。
- **测试素材**：存成 8 位 PNG 以保证可复现，并在 `tests/data/README.md` 注明来源与许可。
- **不要改动** `dvdbr3o.typ/`（外部模板包，视为只读）与 `build/` 等衍生目录。

## C++ / xmake 约定（仅在使用该技术栈时）

- **构建用 xmake**：不要手写 g++ 命令。`xmake build` 构建、`xmake run <target>` 运行。
- **代码风格**：C++26（CUDA 侧 C++20），TAB 缩进、列宽 100，`.clang-format`（基于 Google）。改完 C/C++/CUDA 文件跑 `clang-format -i`。
- **统一图像抽象**：所有算子面向 `dcs229::ImageView`（8 位 RGBA、行优先、4 字节/像素，`size == w*h*4`）。只处理 RGB，alpha 原样透传。解码用 `load_image()`，编码用 `save_image()`。
- **测试用 Catch2**：解析解 + 所有实现一致性（含退化尺寸）+ 端到端。CUDA 测试先探测设备、无设备则 `SKIP`（不要用 `try/catch` 捕 SKIP）。
- 每个算子提供这些实现：**参考实现**、**CPU w/ scalar / cache-friendly tiling / OpenMP / AVX2 SIMD**、**GPU w/ CUDA**。

## 目录速览

| 路径 | 内容 |
| --- | --- |
| `common/` | 共享静态库 `dcs229.common`：RGBA8 图像抽象、PNG/JPEG 编解码、计时辅助 |
| `0305/ 0306/` | 各子实验：`src/` 实现、`tests/`（含 `data/`）、`public/`（报告图）、`main.typ`、`xmake.lua` |
| `project3/main.typ` | 综合报告，按章节汇总各子实验 |
| `dvdbr3o.typ/` | 共享 Typst 模板包（只读） |
| `tools/` | `bench_plot.py`（基准出图）、`build_reports.sh`（编译报告） |
| `docs/conventions.md` | 完整规范（先读这个） |

## 子实验结构

每个子实验（`<编号>`）的目录布局为 `src/`、`tests/`（含 `data/`）、`public/`、`main.typ`。

采用 C++ + xmake 技术栈时，提供三个目标：

- `<编号>`：CLI 可执行文件（基于 CLI11，位置参数或 `-i/-o`，按输出扩展名选编码器）。
- `<编号>.tests`：Catch2 测试（tag：`[<算子>]`、`[cpu]`、`[cuda]`、`[data]`、`[encode]`）。
- `<编号>.bench`：Catch2 `BENCHMARK`（文件需 `[benchmark]` tag）。

## 常用命令

```sh
# —— C++ / xmake 技术栈 ——
xmake f -c -y                       # 重新配置
xmake build                         # 构建全部
xmake build 0305 0305.tests         # 构建指定目标
xmake run 0305.tests                # 跑测试
xmake run 0305.tests -- "[cpu]"     # 按 tag 过滤
xmake run 0305.bench -- --benchmark-samples 30

# 端到端出图：对每个素材跑一遍 CLI
xmake r 0305 0305/tests/data/board.png 0305/tests/data/board_out.png

# benchmark 出图到 <项目>/public/
xmake build 0305.bench && python3 tools/bench_plot.py 0305 --samples 20

# —— 通用：编译报告 ——
tools/build_reports.sh              # 全部
typst compile --root . 0305/main.typ 0305/main.pdf   # 单个
```

## 新增一个子实验时

1. 按现有子实验建立目录布局（`src/`、`tests/data/`、`public/`、`main.typ`）。
2. 在 `project3/main.typ` 增加一个 `<编号> <主题>` 章节，并在概览表、分工表登记。
3. 测试素材存 8 位 PNG 到 `tests/data/` 并写 `README.md` 注明来源与许可。
4. 若采用 C++ + xmake 技术栈：在根 `xmake.lua` 加 `includes("<编号>")`，并按上文配置三个目标。

## 提交前

- 通用：`tools/build_reports.sh` 能编译全部报告；报告里的代码片段/数字与实现一致。
- 通用：不提交 `build/`、`*.pdf`、`compile_commands.json`。
- C++ / xmake 技术栈：`clang-format -i` 改动文件；`xmake build` 无新警告；`xmake run <项目>.tests` 全绿；改了实现就重新生成 `public/` 图表。
