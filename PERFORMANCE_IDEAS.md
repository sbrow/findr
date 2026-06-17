# Performance Ideas

Current state after regex→glob migration + inline entry processing + skip gitignore in .All mode + channel-based streaming output. findr beats fd in 3/4 cases.

## Benchmark results (2026-06-17, post-channels)

| Case | fd | findr | Ratio |
|------|------|-------|-------|
| 1 `-E .jj` | 159ms | 112ms | **1.42x faster** |
| 2 `-H` | 1.202s | 710ms | **1.69x faster** |
| 3 `-HI` | 1.080s | 1.212s | **1.12x slower** |
| 4 `-E .git` | 298ms | 222ms | **1.34x faster** |

Channels gave the biggest single improvement since the project started. Cases 1, 2, and 4 got dramatically faster because output I/O now overlaps with directory walking. Case 3 improved from 1.18x slower to 1.12x slower.

## Completed

1. **Per-thread result buffers** — each thread accumulates locally, merges once at exit. Eliminates per-result mutex contention.
2. **Lean path join** — `join_path`/`join_path_dir` use stack buffer + `copy` + single alloc instead of `strings.Builder` + `fmt.sbprintf` + `clone`.
3. **Regex→glob migration** — replaced regex NFA with backtracking glob matcher. Eliminated 27% of CPU spent on `add_thread`/`is_ignored`. Biggest win.
4. **32KB getdents buffer** — bumped from 8KB. Marginal improvement, within noise.
5. **Skip gitignore loading in `.All` mode** — eliminated thousands of unnecessary file opens/parses in `-HI`. Cut system time 34% (12.4s → 8.2s).
6. **Fixed-size threads slice** — replaced `[dynamic]^thread.Thread` with `[]^thread.Thread` since thread count is known upfront.
7. **Inline entry processing** — merged `read_dir_entries` into `process_dir`. Entry names consumed directly from getdents buffer via `dirent_name(d)` views. Eliminated millions of `strings.clone`/`delete` pairs. User time dropped 38% in `-HI` case.
8. **Skip `has_git_dir` probe in `.All` mode** — guarded `has_git_dir(fd)` with `ignore_mode != .All`. Eliminated ~280K wasted `openat` ENOENT probes in `-HI` case. System time dropped 33% (11.3s → 7.6s).
9. **Channel-based streaming output** — replaced global results array + mutex with `chan.Chan([]string)`, cap `2 * thread_count`. Workers flush 256-result batches through the channel; a consumer thread drains to stdout. Matches fd's architecture (`crossbeam_channel::bounded(2*threads)`, batch size `0x100`). Eliminates the collect-then-write barrier. Cases 1/2/4 went from 1.1-1.3x faster to 1.3-1.7x faster.

## fd vs findr architecture comparison

| Aspect | fd (ignore crate) | findr |
|--------|-------------------|-------|
| Syscall | `libc::readdir` | raw `getdents64` |
| Entry names | Clones into owned `PathBuf` per entry | Zero-copy view from getdents buffer |
| `.git` detection | `stat(".git")` per directory | `openat(fd, ".git")` probe per directory |
| Gitignore setup | Before entry iteration | Before entry iteration |
| Path traversal | Full paths | Full paths |
| Glob matching | globset stratification (literals→hash, complex→regex) | Backtracking token matcher |
| Result transport | `crossbeam_channel::bounded(2*threads)` (lock-free MPMC) | `core:sync/chan` (single-mutex ring buffer) |
| Batching | `Arc<Mutex<Option<Vec>>>` shared buffer, flush on first item | Detach backing array as `[]string`, flush when full (256) |
| Output mode | Hybrid: buffer 1000 items / 100ms → sort → stream | Direct streaming (no buffer/sort mode yet) |

## Known problems

1. **Allocator efficiency gap** — findr still allocates 1-3 heap strings per entry (`join_path` results, work item paths). fd does the same but benefits from Rust's allocator. Odin's default allocator may have higher per-allocation overhead.

2. **Channel mutex contention (unconfirmed)** — Odin's `core:sync/chan` uses a single mutex for the entire ring buffer. With 16 senders + 1 receiver hitting the same lock, every `chan.send`/`chan.recv` is a potential futex contention point. fd uses `crossbeam_channel::bounded` which is lock-free MPMC. **Note**: early spall profiles showed 11.8% futex_wait, but this was likely a profiling artifact — the channel ops generate more instrumentation events, causing the 1GB spall cap to be hit over a longer wall-time window (3.5s vs 1s), skewing the profile. Needs a fair comparison (smaller tree or larger cap) to confirm whether this is real.

## Remaining ideas

1. **Lock-free MPMC queue**
   Replace Odin's mutex-based channel with a custom multi-producer-single-consumer ring buffer using atomics. Eliminates all futex syscalls on the result-transport hot path.

   **Design**:
   - Fixed-capacity ring buffer of `[]string` slots (cap = `2 * thread_count`, same as now)
   - Producer side: each worker atomic-CASes a `head` counter forward to claim a slot index, writes its batch, then sets a `ready` flag on the slot
   - Consumer side: atomic-load `head`, drains all ready slots up to `head`, writes to stdout, frees batches
   - Backpressure: if `head - tail >= cap`, producer spins/waits (yields via `sched_yield` or `futex` with private flag)
   - Close: atomic flag set by `walk_stream` after all workers joined; consumer drains remaining then exits

   **Alternative**: Use a per-producer SPSC queue (one ring per worker thread). Consumer round-robins across all N queues. No CAS on producer side — each worker writes to its own queue with only a `store` + fence. Consumer reads from each with a `load`. Trades simplicity for zero contention.

   **Risk**: Low. The API surface is small (`send`, `recv`, `close`). Can be swapped behind the existing `flush_batch` interface without touching `walk_worker` or `output_writer`. fd's `crossbeam_channel` proves lock-free MPMC is achievable.

   **Effort**: Medium. ~100-150 lines for the queue + a few tests. No changes to walker or main.

2. **Arena allocator per thread**
   Bump allocator for all transient strings (result paths, work item paths), free once at exit. Would address the allocator efficiency gap. Bigger change, helps everywhere.

3. **Buffer/sort output mode** (fd's approach)
   Buffer up to 1000 results (or 100ms deadline), sort them, then switch to streaming. Gives sorted output for small searches without sacrificing throughput on large ones. fd's `ReceiverMode::Buffering → Streaming` pattern.

4. **Git index parsing**
   Parse `.git/index` binary format to show tracked dotfiles. Closes the 84-file correctness delta in cases 1/4. Last correctness gap.
