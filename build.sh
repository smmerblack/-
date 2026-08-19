#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$project_dir"

make clean
make all

echo "Built: $project_dir/build/BZAdBlocker.dylib"
