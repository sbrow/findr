# Performance Ideas

Current state after regex→glob migration + inline entry processing + skip gitignore in .All mode + channel-based streaming output + byte-buffer output. findr beats fd in 4/4 cases.

## Benchmark results (2026-06-17, post-byte-buffer)

| Case | fd | findr | Ratio |
|------|------|-------|-------|
| 1 `-E .jj` | 148ms | 99ms | **1.50x faster** |
| 2 `-H` | 1.142s | 609ms | **1.88x faster** |
| 3 `-HI` | 1.009s | 966ms | **1.04x faster** |
| 4 `-E .git` | 268ms | 197ms | **1.36x faster** |

Byte-buffer output eliminated per-result string allocations. Workers now write `path\n` directly into `[]u8` buffers sent through the channel; the output writer does a single bulk write per batch. Case 3 (`-HI`, 5.6M entries) flipped from 1.12x slower to 1.04x faster — the biggest win since it has the most output.

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
10. **Byte-buffer output** — replaced `chan.Chan([]string)` with `chan.Chan([]u8)`. Workers write `path\n` directly into 64KB byte buffers via `append_path`; output writer does a single bulk `writer_write` per batch. Eliminates ~5M `join_path` allocs, ~5M `delete(s)` frees, ~20K batch array allocs. Case 3 (`-HI`) flipped from 1.12x slower to 1.04x faster. All 4 cases now beat fd.

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
| Batching | `Arc<Mutex<Option<Vec>>>` shared buffer, flush on first item | 64KB `[]u8` byte buffers, flush when full |
| Output mode | Hybrid: buffer 1000 items / 100ms → sort → stream | Bulk byte writes, direct streaming (no buffer/sort mode yet) |

## Known problems

1. **Allocator efficiency gap** — findr still allocates 1-3 heap strings per entry (`join_path` results, work item paths). fd does the same but benefits from Rust's allocator. Odin's default allocator may have higher per-allocation overhead.

2. **Channel mutex contention (unconfirmed)** — Odin's `core:sync/chan` uses a single mutex for the entire ring buffer. With 16 senders + 1 receiver hitting the same lock, every `chan.send`/`chan.recv` is a potential futex contention point. fd uses `crossbeam_channel::bounded` which is lock-free MPMC. **Note**: early spall profiles showed 11.8% futex_wait, but this was likely a profiling artifact — the channel ops generate more instrumentation events, causing the 1GB spall cap to be hit over a longer wall-time window (3.5s vs 1s), skewing the profile. Needs a fair comparison (smaller tree or larger cap) to confirm whether this is real.

## Remaining ideas

### Allocation strategies

Allocation audit (per-entry hot path in `process_dir`):

| Site | What | Est. count (-HI) |
|------|------|-------------------|
| `join_path`/`join_path_dir` for results | `make([]u8, total)` for result paths | ~5M |
| `join_path` for WorkItem paths | same, for recursed dirs | ~500K |
| `strings.clone(entry_rel)` | clone for WorkItem.rel | ~500K |
| `clone_to_c_string(dir_path)` | cstring for `open()` | ~500K |
| `flush_batch` → `make([dynamic]string)` | new batch array | ~20K |
| `delete(s)` per result | free in output writer | ~5M |

Available Odin allocators: `core:mem` (Arena, Dynamic_Arena, Stack, etc.), `core:mem/tlsf` (TLSF — O(1) alloc/free, supports individual frees, grows via backing allocator).

1. **Byte-buffer output — eliminate result path allocations entirely** *(COMPLETED — see #10 in Completed)*

2. **Stack-buffer cstring for `open()`**
   Replace `strings.clone_to_c_string(dir_path)` + `delete(cpath)` with a stack buffer copy:
   ```odin
   cbuf: [4096]u8
   copy(cbuf[:], dir_path)
   cbuf[len(dir_path)] = 0
   fd, err := linux.open(cstring(raw_data(&cbuf[0])), ...)
   ```

   **Eliminates**: ~500K heap allocs for cstrings. Trivial change.

3. **Arena for WorkItem paths**
   Use a `Dynamic_Arena` or virtual-memory bump allocator for `join_path` results and `clone(entry_rel)` in WorkItems. Remove individual `delete(item.path)` / `delete(item.rel)` calls. Free arena once at end of `walk_stream`.

   **Eliminates**: ~1M individual alloc/free pairs for WorkItem paths/rels.

   **Challenge**: WorkItems cross thread boundaries via the queue, so the arena must be shared. A shared `Dynamic_Arena` needs synchronization on the bump pointer. Cleanest approach: `core:mem/virtual` to reserve a large address space (e.g. 256MB) and do `atomic_add_explicit(&offset, size, .Acquire)` for lock-free bump allocation.

4. **TLSF as global allocator**
   Swap `context.allocator` to TLSF at program start. O(1) alloc/free with good cache locality. ~5 lines of code. Best as a fallback if strategies 1-3 don't fully close the gap.

### Other ideas

5. **Lock-free MPMC queue**
   Replace Odin's mutex-based channel with a custom multi-producer-single-consumer ring buffer using atomics. Eliminates all futex syscalls on the result-transport hot path.

   **Design**:
   - Fixed-capacity ring buffer of `[]u8` slots (cap = `2 * thread_count`, same as now)
   - Producer side: each worker atomic-CASes a `head` counter forward to claim a slot index, writes its batch, then sets a `ready` flag on the slot
   - Consumer side: atomic-load `head`, drains all ready slots up to `head`, writes to stdout, frees batches
   - Backpressure: if `head - tail >= cap`, producer spins/waits (yields via `sched_yield` or `futex` with private flag)
   - Close: atomic flag set by `walk_stream` after all workers joined; consumer drains remaining then exits

   **Alternative**: Use a per-producer SPSC queue (one ring per worker thread). Consumer round-robins across all N queues. No CAS on producer side — each worker writes to its own queue with only a `store` + fence. Consumer reads from each with a `load`. Trades simplicity for zero contention.

   **Risk**: Low. The API surface is small (`send`, `recv`, `close`). Can be swapped behind the existing `flush_batch` interface without touching `walk_worker` or `output_writer`. fd's `crossbeam_channel` proves lock-free MPMC is achievable.

   **Effort**: Medium. ~100-150 lines for the queue + a few tests. No changes to walker or main.

6. **Buffer/sort output mode** (fd's approach)
   Buffer up to 1000 results (or 100ms deadline), sort them, then switch to streaming. Gives sorted output for small searches without sacrificing throughput on large ones. fd's `ReceiverMode::Buffering → Streaming` pattern.

7. **Git index parsing**
   Parse `.git/index` binary format to show tracked dotfiles. Closes the 84-file correctness delta in cases 1/4. Last correctness gap.
