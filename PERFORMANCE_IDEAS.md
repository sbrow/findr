# Performance Ideas

Current state after regex→glob migration. findr beats fd in 3/4 cases.

## Benchmark results (2026-06-17)

| Case | fd | findr | Ratio |
|------|------|-------|-------|
| 1 `-E .jj` | 172ms | 135ms | **1.27x faster** |
| 2 `-H` | 1.184s | 1.097s | **1.08x faster** |
| 3 `-HI` | 1.251s | 1.670s | **1.34x slower** |
| 4 `-E .git` | 274ms | 202ms | **1.36x faster** |

Case 3 (`-HI`) skips gitignore entirely, so it's pure I/O + allocation. System time is 2x fd's (12.1s vs 5.5s), pointing to syscall/allocation overhead.

## Completed

1. **Per-thread result buffers** — each thread accumulates locally, merges once at exit. Eliminates per-result mutex contention.
2. **Lean path join** — `join_path`/`join_path_dir` use stack buffer + `copy` + single alloc instead of `strings.Builder` + `fmt.sbprintf` + `clone`.
3. **Regex→glob migration** — replaced regex NFA with backtracking glob matcher. Eliminated 27% of CPU spent on `add_thread`/`is_ignored`. Biggest win.

## Remaining ideas

1. **Larger getdents buffer** (8KB → 64KB+)
   Fewer syscalls per directory with many entries. Low effort.

2. **Eliminate entry name cloning**
   `strings.clone(name)` in `read_dir_entries` heap-allocates per dirent. Names are valid in the getdents buffer during `process_dir`, so the clone may be unnecessary. Low effort.

3. **Arena allocator per thread**
   Bump allocator for all transient strings, free once at exit. Bigger change, helps everywhere.

4. **Batched channel** (fd's approach)
   Replace global results array with buffered channel of batches. Enables streaming output and sorting like fd does.
