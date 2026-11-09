# Project 03 素材与报告用图

原 `public/` 中的 15 张亚洲人脸候选图经比较后只保留 3 张；每张对应 `colorspace_split.py` 中手动选择的最优 split。

## 素材与来源

| 文件 | 内容 | 尺寸 | 选用 split | 摄影者 | 原始页面 |
| --- | --- | --- | --- | --- | --- |
| `asian_1.png` | 年轻女性，灰色棚拍背景 | 512×640 | `YCbCrEllipseSplit` | BYB BYB | <https://www.pexels.com/photo/19999456/> |
| `asian_6.png` | 东亚女性，深色背景托腮 | 427×640 | `YCbCrBoxSplit` | Tokuo Nobuhiro | <https://www.pexels.com/photo/11464447/> |
| `asian_13.png` | 东亚男性，眼镜，灰色背景 | 427×640 | `HSVSplit` | Huy Nguyễn | <https://www.pexels.com/photo/31052395/> |

全部图片来自 [Pexels](https://www.pexels.com/)，遵循 [Pexels License](https://www.pexels.com/license/)：可免费用于商业和非商业用途、可修改、无需署名。图片中人物仅为素材模特，不得用于暗示其认可本实验或任何产品。

- 下载日期：2026-10-29。
- 统一缩放为长边 640 px（LANCZOS），转换为 **8 位 RGB PNG**，并去除 EXIF 等元数据。

## 文件

| 文件 | 内容 |
| --- | --- |
| `asian_<序号>.png` | 输入素材 |
| `asian_<序号>_mask.png` | 二值掩膜（白 = 肤色） |
| `asian_<序号>_out.png` | 肤色区域，其余置黑 |
| `compare_asian_<序号>.png` | 6 种 split 的候选对比图（`*` 为选定方案） |
| `split_scores.csv` | 每种 split 的选中比例、人脸框覆盖率、四角背景误检率 |

`compare_asian_*.png` 与 `split_scores.csv` 是报告用的临时产物；演示脚本本身只负责单张图片的三联图，不包含批量出图代码。指标中的人脸框是手工给出的近似矩形，只用于相对比较，不参与分割；背景误检率取图像四角的 80×80 区域。
