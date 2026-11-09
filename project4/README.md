
# Project 04：形态学后处理

在项目三的肤色分割结果上，用形态学算法做进一步处理：先对图像做灰度形态学平滑，再调用项目三的分割器得到原始掩膜，然后用二值形态学（开运算、闭运算、孔洞填充、大尺度开运算、连通分量过滤）清理掩膜，最后用边界提取画出肤色区域的轮廓。代码只有一个脚本 `morphology.py`，所有形态学算子都是手写的（只依赖 numpy），项目三的 `colorspace_split.py` 原样复制过来，没有做任何修改。

## 流水线

```
输入图像
  └─ [灰度形态学] 每个通道 开→闭 平滑
  └─ 项目三的颜色空间分割            → 原始掩膜
  └─ [二值形态学] 开运算             去细小噪点、发丝
  └─ [二值形态学] 闭运算             弥合眼睛 / 眼镜 / 嘴唇造成的缝隙
  └─ [二值形态学] 孔洞填充           条件膨胀
  └─ [二值形态学] 大尺度开运算       去掉发丝尖角、细长突起
  └─ [二值形态学] 连通分量过滤       8 邻接，去掉零碎区域
  └─ [二值形态学] 边界提取           β(A) = A − (A ⊖ B)，用于可视化
```

每张图使用项目三为它挑选的分割器：

| 图片             | 尺寸     | 分割器                | 来源       |
| ---------------- | -------- | --------------------- | ---------- |
| `asian_1.png`  | 512×640 | `YCbCrEllipseSplit` | 项目三选用 |
| `asian_6.png`  | 427×640 | `YCbCrBoxSplit`     | 项目三选用 |
| `asian_13.png` | 427×640 | `HSVSplit`          | 项目三选用 |

## 文件结构

```
project4/
├── colorspace_split.py   # 项目三代码，原样复制，不做修改
├── morphology.py         # 本项目：形态学算子、流水线、演示
└── public/
    ├── asian_1.png / asian_6.png / asian_13.png   # 输入素材
    └── morph/                                      # 运行后生成的结果
```

## 运行

```sh
# 依赖：numpy、pillow、matplotlib
python project4/morphology.py            # 处理三张图，结果保存到 project4/public/morph/
python project4/morphology.py --show     # 额外弹出每张图的逐步结果图
```

路径基于脚本所在目录，从任意目录运行都可以。每张图会打印项目三掩膜和流水线每一步之后的统计：

```
asian_1 (YCbCrEllipseSplit)
  project 3 mask   xx.xx% | comps  n | holes  n | boundary  n | corners  x.xx%
  raw mask         ...
  opening          ...
  closing          ...
  fill holes       ...
  shape opening    ...
  components       ...
```

各列依次为：选中像素比例、连通域个数、孔洞个数、边界像素数、四个 80×80 角落被选中的比例（背景误检的代理指标）。

把形态学接到项目三的接口上也很直接，`MorphSplit` 和 `Split` 接口一致：

```python
from PIL import Image
from colorspace_split import YCbCrEllipseSplit, colorspace_split
from morphology import MorphSplit

image = Image.open("public/asian_1.png")
result = colorspace_split(image, MorphSplit(YCbCrEllipseSplit()))
```

## 输出文件

`public/morph/` 中每张图生成 5 个文件（`<name>` 为 `asian_1`、`asian_6`、`asian_13`）：

| 文件                      | 内容                                                                             |
| ------------------------- | -------------------------------------------------------------------------------- |
| `<name>_p3_mask.png`    | 项目三的原始掩膜                                                                 |
| `<name>_morph_mask.png` | 形态学处理后的最终掩膜                                                           |
| `<name>_morph_out.png`  | 只保留肤色像素的输出（用原图，不是平滑后的图）                                   |
| `<name>_steps.png`      | 逐步结果：输入、项目三掩膜、开、闭、孔洞填充、大尺度开、连通分量、边界叠加、输出 |
| `<name>_gray.png`       | 灰度形态学演示：亮度 Y、开→闭平滑、形态学梯度、白顶帽                           |

## 算法

结构元素都是奇数尺寸，原点在中心。二值图像把集合 $A$ 看作 0/1 数组，$B$ 为结构元素。

$$
A \ominus B = \{z \mid (B)_z \subseteq A\},\qquad
A \oplus B = \{z \mid (\hat B)_z \cap A \neq \varnothing\}
$$

$$
A \circ B = (A \ominus B) \oplus B,\qquad
A \bullet B = (A \oplus B) \ominus B,\qquad
\beta(A) = A - (A \ominus B)
$$

**孔洞填充**：从图像边框上的背景像素出发，用 4 邻域十字结构元素对背景做条件膨胀

$$
X_k = (X_{k-1} \oplus B) \cap A^c
$$

直到 $X_k = X_{k-1}$。够不到的背景就是孔洞，结果为 $A \cup \text{孔洞}$。

**连通分量**：`extract_component` 按课件的方法，从种子点出发用 3×3 全 1 结构元素（8 邻接）反复膨胀并与 $A$ 求交；`label_components` 用 BFS 一次标出全部连通域，两者结果等价。`keep_large_components` 只保留面积不小于 `max(min_area, min_ratio × 最大连通域面积)` 的连通域，用相对面积，换分辨率不用重调。

**灰度形态学**：平坦结构元素时腐蚀为最小值滤波、膨胀为最大值滤波，同时支持非平坦结构元素（域外为 $-\infty$）。

$$
g = (f \oplus b) - (f \ominus b)\ \text{（形态学梯度，3×3 全 1）},\qquad
f - (f \circ b)\ \text{（白顶帽）}
$$

`gray_smooth` 先开后闭，用于分割前对 R、G、B 三个通道去除亮噪声和暗噪声。

### 参数

所有半径都是图像短边的比例，换分辨率不用重调：

| 步骤         | 参数                       | 半径（短边 427 / 512）     |
| ------------ | -------------------------- | -------------------------- |
| 灰度平滑     | `smooth_frac = 0.004`    | 2 / 2                      |
| 开运算       | `open_frac = 0.006`      | 3 / 3                      |
| 闭运算       | `close_frac = 0.015`     | 6 / 8                      |
| 大尺度开运算 | `shape_open_frac = 0.02` | 9 / 10                     |
| 连通分量     | `min_ratio = 0.2`        | 保留面积 ≥ 最大连通域 20% |

参数可以通过 `MorphSplit(base, smooth_frac=..., open_frac=..., close_frac=..., shape_open_frac=..., min_ratio=...)` 调整；`shape_open_frac=0` 可关闭大尺度开运算，`smooth_frac=0` 可关闭灰度预处理。

## 实现说明

- **核心算子。** 结构元素按行拆成若干连续行段 `(dy, x0, x1)`，每个行段上的滑动最小/最大值用倍增法计算（整图操作次数为 $O(\log \text{宽度})$），再按 `dy` 平移后合并。二值图像当作 0/1 的 `uint8`，腐蚀 = min、膨胀 = max，所以二值和灰度共用同一套代码。
- **边界处理。** 越界像素按“不影响结果”处理：腐蚀时当作 1，膨胀时当作 0，所以贴着图像边缘的目标不会被腐蚀掉。
- **与项目三的关系。** `MorphSplit` 先对图像做灰度平滑，再调用被包装的 `Split.mask`，最后做二值形态学清理；输出时 `colorspace_split` 把掩膜应用到原图上，所以输出的颜色没有被平滑改动。

## 局限

- 形态学只利用形状信息，修不了颜色判决造成的错误：与肤色接近的浅色衣服、阴影里被漏选的脸部区域，开闭运算都无法恢复。
- `fill_holes` 会填充所有被围住的背景，包括手和下巴之间围出的真实背景缝隙。需要保留这类区域时，可以给孔洞面积设上限，只填充小孔洞。
- 闭运算和大尺度开运算的半径对不同图片的效果不同：半径太大会抹掉手指等细小结构，太小则去不掉发丝尖角。
- 参数仍是手动设定的，换一批素材可能需要重新调整。
