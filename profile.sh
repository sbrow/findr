#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building findr-prof..."
odin build "$DIR" -debug -out:"$DIR/findr-prof"

echo "Running profiler..."
"$DIR/findr-prof" -E .git -E .jj -HI ~/git.verticalaxion.com

echo
echo "Spall trace: $DIR/findr.spall"
