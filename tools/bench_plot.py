#!/usr/bin/env python3
"""Run a project's Catch2 benchmark binary and render bar charts into public/.

Usage:
    python3 tools/bench_plot.py 0305
    python3 tools/bench_plot.py 0306 --samples 30

The script:
  1. runs `<project>.bench` with a fixed sample count;
  2. parses Catch2's benchmark table (best/mean/low/high per variant);
  3. writes the raw output to <project>/public/<project>_bench.txt;
  4. renders one grouped bar chart per image size as SVG, and a PNG copy via
     ImageMagick when `magick` is available.

Everything is deterministic given --samples, so the figures can be regenerated
by re-running the script.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BENCH_BIN = REPO_ROOT / "build" / "linux" / "x86_64" / "release"


def run_bench(project: str, samples: int) -> str:
    binary = BENCH_BIN / f"{project}.bench"
    if not binary.exists():
        sys.exit(f"error: {binary} not found; build it with `xmake build {project}.bench`")
    result = subprocess.run(
        [str(binary), "[benchmark]", f"--benchmark-samples={samples}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    # Catch2 exits non-zero in some configurations; we only need the table.
    return result.stdout + result.stderr


# Parse Catch2's benchmark table. The layout is:
#
#   <name>            <samples>   <iterations>   <est run time>
#                     <mean>      <low mean>     <high mean>
#                     <std dev>   <low std dev>  <high std dev>
#
# A benchmark starts on a line that has no leading whitespace and is not a
# table header/separator; the mean is the first token of the following
# indented line.
SIZE_RE = re.compile(r"\((?:(\d+)x(\d+)|(\d+)\s*[x×]\s*(\d+))\)")


def parse_tables(text: str) -> dict[str, list[tuple[str, float]]]:
    """Return {section_title: [(variant, mean_seconds), ...]}."""
    lines = text.splitlines()
    sections: dict[str, list[tuple[str, float]]] = {}
    current: str | None = None

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Section header: a `----` rule followed by a title line and another rule.
        if stripped.startswith("---") and i + 2 < len(lines) and lines[i + 2].strip().startswith("---"):
            current = lines[i + 1].strip()
            sections.setdefault(current, [])
            i += 3
            continue

        # Benchmark name line: starts at column 0, is not a table header, and
        # is followed by an indented line holding the mean duration.
        if (
            current is not None
            and line
            and not line[0].isspace()
            and not stripped.startswith(("benchmark name", "mean", "std dev", "Filters", "~", "Randomness"))
            and not stripped[0].isdigit()
            and i + 1 < len(lines)
            and lines[i + 1][:1].isspace()
        ):
            mean = _parse_duration(lines[i + 1])
            # The row is "name<samples><iterations><est time>"; the name is the
            # first run of non-space characters before the numeric columns.
            name = re.split(r"\s{2,}", stripped)[0].strip()
            if mean is not None and name and not name[0].isdigit():
                sections[current].append((name, mean))
        i += 1

    return {k: v for k, v in sections.items() if v}


_DURATION_RE = re.compile(r"([\d.]+)\s*(ns|us|ms|min|s)\b")
_UNITS = {"ns": 1e-9, "us": 1e-6, "ms": 1e-3, "s": 1.0, "min": 60.0}


def _parse_duration(line: str) -> float | None:
    """Parse the mean from an indented table line, e.g. '  67.6106 us ...'."""
    match = _DURATION_RE.search(line)
    if match is None:
        return None
    return float(match.group(1)) * _UNITS[match.group(2)]


def human(seconds: float) -> str:
    if seconds >= 1.0:
        return f"{seconds:.2f} s"
    if seconds >= 1e-3:
        return f"{seconds * 1e3:.2f} ms"
    if seconds >= 1e-6:
        return f"{seconds * 1e6:.1f} us"
    return f"{seconds * 1e9:.0f} ns"


PALETTE = {
    "cpu scalar": "#4c72b0",
    "cpu tiled": "#55a868",
    "cpu openmp": "#c44e52",
    "cpu simd (avx2)": "#8172b3",
    "cuda": "#ccb974",
}


def render_svg(title: str, rows: list[tuple[str, float]], out_path: Path) -> None:
    width, height = 760, 420
    margin_l, margin_r, margin_t, margin_b = 90, 40, 60, 90
    plot_w = width - margin_l - margin_r
    plot_h = height - margin_t - margin_b

    peak = max(v for _, v in rows) if rows else 1.0
    best = min(v for _, v in rows) if rows else 1.0

    bar_gap = 18
    bar_w = (plot_w - bar_gap * (len(rows) - 1)) / max(len(rows), 1)

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'font-family="DejaVu Sans, sans-serif">'
    )
    parts.append(f'<rect width="{width}" height="{height}" fill="#ffffff"/>')
    parts.append(
        f'<text x="{width / 2}" y="30" text-anchor="middle" font-size="18" font-weight="bold">'
        f"{title}</text>"
    )

    # Axis.
    axis_y = margin_t + plot_h
    parts.append(
        f'<line x1="{margin_l}" y1="{axis_y}" x2="{margin_l + plot_w}" y2="{axis_y}" '
        f'stroke="#333" stroke-width="1"/>'
    )

    for idx, (name, value) in enumerate(rows):
        bar_h = (value / peak) * (plot_h - 10) if peak > 0 else 0
        x = margin_l + idx * (bar_w + bar_gap)
        y = axis_y - bar_h
        color = PALETTE.get(name, "#999999")
        parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_w:.1f}" height="{bar_h:.1f}" fill="{color}"/>')
        parts.append(
            f'<text x="{x + bar_w / 2:.1f}" y="{y - 6:.1f}" text-anchor="middle" font-size="12">'
            f"{human(value)}</text>"
        )
        speedup = best / value if value > 0 else 0
        parts.append(
            f'<text x="{x + bar_w / 2:.1f}" y="{axis_y + 18:.1f}" text-anchor="middle" font-size="11" '
            f'fill="#555">{speedup:.2f}x</text>'
        )
        # Rotated label.
        lx = x + bar_w / 2
        parts.append(
            f'<text x="{lx:.1f}" y="{axis_y + 38:.1f}" text-anchor="end" font-size="12" '
            f'transform="rotate(-30 {lx:.1f} {axis_y + 38:.1f})">{name}</text>'
        )

    parts.append(
        f'<text x="{margin_l}" y="{axis_y + 86}" font-size="11" fill="#777">'
        f"lower is better; labels show speedup vs fastest</text>"
    )
    parts.append("</svg>")
    out_path.write_text("\n".join(parts), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", choices=["0305", "0306"])
    parser.add_argument("--samples", type=int, default=20, help="Catch2 benchmark samples (default 20)")
    args = parser.parse_args()

    out_dir = REPO_ROOT / args.project / "public"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"running {args.project}.bench ({args.samples} samples) ...")
    text = run_bench(args.project, args.samples)
    (out_dir / f"{args.project}_bench.txt").write_text(text, encoding="utf-8")

    tables = parse_tables(text)
    if not tables:
        sys.exit("error: no benchmark tables parsed; see the saved raw output")

    for title, rows in tables.items():
        sizes = SIZE_RE.search(title)
        size = f"{sizes.group(1) or sizes.group(3)}x{sizes.group(2) or sizes.group(4)}" if sizes else "all"
        rows = sorted(rows, key=lambda r: r[1])
        svg_path = out_dir / f"{args.project}_bench_{size}.svg"
        render_svg(f"{args.project}: {title}", rows, svg_path)

        png_path = svg_path.with_suffix(".png")
        if shutil.which("magick"):
            subprocess.run(
                ["magick", "-background", "white", str(svg_path), str(png_path)],
                check=False,
                capture_output=True,
            )
        print(f"  wrote {svg_path.relative_to(REPO_ROOT)}")
        if png_path.exists():
            print(f"  wrote {png_path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
