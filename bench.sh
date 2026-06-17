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
printf "  findr --ignored             : %8d\n" "$("$FINDR" --ignored "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd . -t f --exclude .git    : %8d\n" "$(fd . -t f --exclude .git "$TARGET" 2>/dev/null | wc -l)"
printf "  findr --no-hidden           : %8d\n" "$("$FINDR" --no-hidden "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd . -H -t f --exclude .git : %8d\n" "$(fd . -H -t f --exclude .git "$TARGET" 2>/dev/null | wc -l)"
printf "  findr (respect)             : %8d\n" "$("$FINDR" "$TARGET" 2>/dev/null | wc -l)"
echo
printf "  fd . -HI -t f --exclude .git: %8d\n" "$(fd . -HI -t f --exclude .git "$TARGET" 2>/dev/null | wc -l)"
printf "  findr -I (all)              : %8d\n" "$("$FINDR" -I "$TARGET" 2>/dev/null | wc -l)"
echo

# --- benchmarks ---
echo "=== Benchmarks (hyperfine, 5 runs, 2 warmups) ==="
echo
hyperfine \
    --warmup 2 \
    --runs 5 \
    --export-markdown "$RESULTS_FILE" \
    "$FINDR --ignored \"$TARGET\" > /dev/null" \
    "fd . -t f --exclude .git \"$TARGET\" > /dev/null" \
    "$FINDR --no-hidden \"$TARGET\" > /dev/null" \
    "fd . -H -t f --exclude .git \"$TARGET\" > /dev/null" \
    "$FINDR \"$TARGET\" > /dev/null" \
    "fd . -HI -t f --exclude .git \"$TARGET\" > /dev/null" \
    "$FINDR -I \"$TARGET\" > /dev/null"
echo

echo "=== Results written to $RESULTS_FILE ==="
