# Performance Ideas

Current state after regex→glob migration + 32KB getdents + skip gitignore in .All mode + inline entry processing. findr beats fd in 3/4 cases.

## Benchmark results (2026-06-17, post-inline-processing)

| Case | fd | findr | Ratio |
|------|------|-------|-------|
| 1 `-E .jj` | 187ms | 150ms | **1.25x faster** |
| 2 `-H` | 1.242s | 1.136s | **1.09x faster** |
| 3 `-HI` | 1.708s | 1.612s | **1.06x slower** |
| 4 `-E .git` | 306ms | 242ms | **1.26x faster** |

Case 3 (`-HI`) wall time is now close to parity. User time dropped 38% (6.9s → 4.3s) from eliminating entry name clones, but system time rose 38% (8.2s → 11.3s) from the `openat(".git")` probe overhead.

## Completed

1. **Per-thread result buffers** — each thread accumulates locally, merges once at exit. Eliminates per-result mutex contention.
2. **Lean path join** — `join_path`/`join_path_dir` use stack buffer + `copy` + single alloc instead of `strings.Builder` + `fmt.sbprintf` + `clone`.
3. **Regex→glob migration** — replaced regex NFA with backtracking glob matcher. Eliminated 27% of CPU spent on `add_thread`/`is_ignored`. Biggest win.
4. **32KB getdents buffer** — bumped from 8KB. Marginal improvement, within noise.
5. **Skip gitignore loading in .All mode** — eliminated thousands of unnecessary file opens/parses in `-HI`. Cut system time 34% (12.4s → 8.2s).
6. **Fixed-size threads slice** — replaced `[dynamic]^thread.Thread` with `[]^thread.Thread` since thread count is known upfront.
7. **Inline entry processing** — merged `read_dir_entries` into `process_dir`. Entry names consumed directly from getdents buffer via `dirent_name(d)` views. Eliminated millions of `strings.clone`/`delete` pairs. User time dropped 38% in `-HI` case.

## fd vs findr architecture comparison

| Aspect | fd (ignore crate) | findr |
|--------|-------------------|-------|
| Syscall | `libc::readdir` | raw `getdents64` |
| Entry names | Clones into owned `PathBuf` per entry | Zero-copy view from getdents buffer |
| `.git` detection | `stat(".git")` per directory | `openat(fd, ".git")` probe per directory |
| Gitignore setup | Before entry iteration | Before entry iteration |
| Path traversal | Full paths | Full paths |
| Glob matching | globset stratification (literals→hash, complex→regex) | Backtracking token matcher |

## Known problems

1. **`openat(".git")` probe regression** — The inline processing refactor replaced a free dirent-name scan with a paid `openat` syscall per directory (~280K directories = 280K syscalls, most returning ENOENT). User time dropped from clone elimination, but system time rose from the probe, roughly canceling out. The old code detected `.git` for free while scanning entries; the new code needs `.git` info before processing, forcing the probe.

   Fixes to explore:
   - **Skip probe in `.All` mode** — gitignore context is irrelevant, so `has_git` is unused. Eliminates ~280K ENOENT probes in `-HI` case. Low effort.
   - **Two-pass over first getdents batch** — scan first batch for `.git`, set up context, then process all batches. `.git` virtually always appears in the first batch. Risk: not guaranteed.
   - **Lazy context reset** — process entries optimistically, reset context if `.git` found mid-scan. Complex, entries already processed with wrong context.

2. **Allocator efficiency gap** — findr still allocates 1-3 heap strings per entry (`join_path` results, work item paths). fd does the same but benefits from Rust's allocator. Odin's default allocator may have higher per-allocation overhead.

## Remaining ideas

1. **Skip `has_git_dir` probe in `.All` mode**
   Trivial guard. Directly addresses the system-time regression in the `-HI` case.

2. **Arena allocator per thread**
   Bump allocator for all transient strings (result paths, work item paths), free once at exit. Would address the allocator efficiency gap. Bigger change, helps everywhere.

3. **Batched channel** (fd's approach)
   Replace global results array with buffered channel of batches. Enables streaming output and sorting like fd does.

## Allocator analysis

Each emitted entry still needs a heap-allocated result string from `join_path`/`join_path_dir`, and each subdirectory needs a cloned `child_path` + `child_rel` for the work queue. That's 1-3 heap allocs per entry × millions of entries.

fd has the same pattern (PathBuf per entry + per subdirectory) but benefits from Rust's allocator (system allocator tuned via `malloc`/`free` or jemalloc). Odin's default allocator may have higher per-allocation overhead. Options:
- **Arena per thread**: bulk-allocate, reset after each directory or at thread exit. Best for transient data.
- **Slab allocator for small strings**: most filenames are <64 bytes. A slab for small allocations could reduce fragmentation and improve cache locality.
- **Test with different Odin allocators**: `context.allocator` can be swapped. Worth profiling with `mem.virt_allocator` or a custom arena to measure the gap.
