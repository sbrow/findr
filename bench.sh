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
printf "  fd -a .                      : %8d\n" "$(fd -a . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr                        : %8d\n" "$("$FINDR" "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -H .                   : %8d\n" "$(fd -a -H . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -H                     : %8d\n" "$("$FINDR" -H "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -HI .                  : %8d\n" "$(fd -a -HI . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -HI                    : %8d\n" "$("$FINDR" -HI "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd -a -E .git .              : %8d\n" "$(fd -a -E .git . "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -E .git                : %8d\n" "$("$FINDR" -E .git "$TARGET" 2>/dev/null | wc -l)"
echo

# --- benchmarks ---
echo "=== Benchmarks (hyperfine, 5 runs, 2 warmups) ==="
echo
hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown "$RESULTS_FILE" \
    "fd -a . \"$TARGET\" > /dev/null" \
    "$FINDR \"$TARGET\" > /dev/null" \
    "fd -a -H . \"$TARGET\" > /dev/null" \
    "$FINDR -H \"$TARGET\" > /dev/null" \
    "fd -a -HI . \"$TARGET\" > /dev/null" \
    "$FINDR -HI \"$TARGET\" > /dev/null" \
    "fd -a -E .git . \"$TARGET\" > /dev/null" \
    "$FINDR -E .git \"$TARGET\" > /dev/null"
echo

echo "=== Results written to $RESULTS_FILE ==="
