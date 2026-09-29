#!/usr/bin/env bash
# Build the 0305 / 0306 Typst reports.
#
# The reports import the shared `dvdbr3o.typ` package at the repository root,
# which sits outside each project directory, so Typst must be run with the
# repository root as its project root.
#
# Usage:
#   tools/build_reports.sh            # build both
#   tools/build_reports.sh 0305       # build one
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

projects=("$@")
if [ ${#projects[@]} -eq 0 ]; then
  projects=(0305 0306 project3)
fi

for project in "${projects[@]}"; do
  if [ ! -f "$project/main.typ" ]; then
    echo "skip: $project/main.typ not found" >&2
    continue
  fi
  echo "typst: $project/main.typ -> $project/main.pdf"
  typst compile --root "$root" "$project/main.typ" "$project/main.pdf"
done

echo "done."
