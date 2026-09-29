# 0306 — public results

Benchmark charts for the unsharp-masking implementations.

Each figure compares the CPU variants (scalar / tiled / OpenMP / AVX2 SIMD) and
the CUDA kernel; bars show the mean time over `--benchmark-samples` runs, the
small label above each bar is that mean, and the label below is the speedup
relative to the fastest variant. Lower is better.

| file | content |
| ---- | ------- |
| `0306_bench_256x256.{svg,png}` | all variants on a 256x256 image |
| `0306_bench_1024x1024.{svg,png}` | all variants on a 1024x1024 image |
| `0306_bench.txt` | raw Catch2 benchmark output the figures were parsed from |

Note: the CUDA numbers include the host↔device copies on every call, since the
launcher is a full round-trip; they are not pure kernel timings.

## Regenerate

```sh
xmake build 0306.bench
python3 tools/bench_plot.py 0306 --samples 20
```

The enhanced test images (`tests/data/*_out.png`) are produced by:

```sh
for img in lena baboon board checkerboard; do
  xmake run 0306 0306/tests/data/$img.png 0306/tests/data/${img}_out.png
done
```
