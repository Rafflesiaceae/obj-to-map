#!/usr/bin/env bash
set -eo pipefail

# cd to parent dir of current script
cd "$(dirname "${BASH_SOURCE[0]}")"

nimble build

inpf=./tests/christ-convex-hulls.obj
outf=./tests/christ-convex-hulls.map

./obj_to_map "$inpf" "$outf"
