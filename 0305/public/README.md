# 0305 — public results

Benchmark charts for the Laplacian-enhancement implementations.

Each figure compares the CPU variants (scalar / tiled / OpenMP / AVX2 SIMD) and
the CUDA kernel; bars show the mean time over `--benchmark-samples` runs, the
small label above each bar is that mean, and the label below is the speedup
relative to the fastest variant. Lower is better.

| file | content |
| ---- | ------- |
| `0305_bench_256x256.{svg,png}` | all variants on a 256x256 image |
| `0305_bench_1024x1024.{svg,png}` | all variants on a 1024x1024 image |
| `0305_bench.txt` | raw Catch2 benchmark output the figures were parsed from |

Note: the CUDA numbers include the host↔device copies on every call, since the
launcher is a full round-trip; they are not pure kernel timings.

## Regenerate

```sh
xmake build 0305.bench
python3 tools/bench_plot.py 0305 --samples 20
```

The enhanced test images (`tests/data/*_out.png`) are produced by:

```sh
for img in lena baboon board checkerboard; do
  xmake run 0305 0305/tests/data/$img.png 0305/tests/data/${img}_out.png
done
```
