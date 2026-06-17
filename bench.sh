#!/usr/bin/env bash
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$HOME}"
RESULTS_FILE="$BENCH_DIR/bench-results.md"
FINDR="$BENCH_DIR/findr"

echo "=== findr benchmark suite ==="
echo "Target: $TARGET"
echo

# --- pre-flight checks ---
if ! command -v fd &>/dev/null; then
    echo "ERROR: fd is not on PATH" >&2
    exit 1
fi
if ! command -v hyperfine &>/dev/null; then
    echo "ERROR: hyperfine is not on PATH" >&2
    exit 1
fi

# --- build findr if missing or stale ---
NEEDS_BUILD=false
if [[ ! -f "$BENCH_DIR/findr" ]]; then
    NEEDS_BUILD=true
else
    # rebuild if any .odin source is newer than the binary
    if find "$BENCH_DIR" -name '*.odin' -newer "$BENCH_DIR/findr" | grep -q .; then
        NEEDS_BUILD=true
    fi
fi
if $NEEDS_BUILD; then
    echo "Building findr..."
    odin build "$BENCH_DIR" -o:speed -out:"$BENCH_DIR/findr"
fi
echo

# --- file counts ---
echo "=== File counts ==="
printf "  fd -a -E .jj .                : %8d\n" "$(fd -a -E .jj . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -E .jj                  : %8d\n" "$("$FINDR" -E .jj "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -E .git -E .jj -H .     : %8d\n" "$(fd -a -E .git -E .jj -H . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -E .git -E .jj -H       : %8d\n" "$("$FINDR" -E .git -E .jj -H "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -E .git -E .jj -HI .    : %8d\n" "$(fd -a -E .git -E .jj -HI . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -E .git -E .jj -HI      : %8d\n" "$("$FINDR" -E .git -E .jj -HI "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -E .git -E .jj .        : %8d\n" "$(fd -a -E .git -E .jj . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -E .git -E .jj          : %8d\n" "$("$FINDR" -E .git -E .jj "$TARGET" 2>/dev/null | wc -l)"
echo

# --- benchmarks ---
echo "=== Benchmarks (hyperfine, 5 runs, 2 warmups) ==="
echo
hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown "$RESULTS_FILE" \
    "fd -a -E .jj . \"$TARGET\" > /dev/null" \
    "$FINDR -E .jj \"$TARGET\" > /dev/null" \
    "fd -a -E .git -E .jj -H . \"$TARGET\" > /dev/null" \
    "$FINDR -E .git -E .jj -H \"$TARGET\" > /dev/null" \
    "fd -a -E .git -E .jj -HI . \"$TARGET\" > /dev/null" \
    "$FINDR -E .git -E .jj -HI \"$TARGET\" > /dev/null" \
    "fd -a -E .git -E .jj . \"$TARGET\" > /dev/null" \
    "$FINDR -E .git -E .jj \"$TARGET\" > /dev/null"
echo

echo "=== Results written to $RESULTS_FILE ==="
