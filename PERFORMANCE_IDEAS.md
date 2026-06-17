findr is ~2.3x slower than fd (case 1: 547ms vs 241ms). Opportunities:

1. Per-thread result buffers (DONE)
Each thread accumulates results locally, then merges once at exit. Eliminates per-result mutex contention.

2. Batched channel (fd's approach)
Replace global results array + merge with a buffered channel of batches. Each worker fills a local batch (~256 items), sends it to a `chan.Chan([]string)` (capacity = 2 × threads). A receiver thread drains batches and collects/prints. Provides backpressure, streaming output, and per-batch (not global) synchronization. Enables sorting like fd does (buffer first 1000 results or 100ms, then stream).

3. Path allocation waste (join_path/join_path_dir)
Every path construction spins up a strings.Builder, does fmt.sbprintf, to_string, clone, then builder_destroy — 2 heap allocs + 2 frees per path. Could be a simple memcpy into a stack buffer with a single alloc.

4. Larger getdents buffer
Currently 8KB. Increasing to 64KB+ means fewer syscalls per directory with many entries.

5. Eliminate entry name cloning
strings.clone(name) in read_dir_entries heap-allocates per dirent. Names are valid in the getdents buffer during process_dir, so the clone may be unnecessary.

6. Arena allocator per thread
Replace the default allocator for transient strings with a bump allocator — allocate in bulk, free all at once.
2. Path allocation waste (join_path/join_path_dir)
Every path construction spins up a strings.Builder, does fmt.sbprintf, to_string, clone, then builder_destroy — 2 heap allocs + 2 frees per path. Could be a simple memcpy into a stack buffer with a single alloc.
3. Larger getdents buffer
Currently 8KB. Increasing to 64KB+ means fewer syscalls per directory with many entries.
4. Eliminate entry name cloning
strings.clone(name) in read_dir_entries heap-allocates per dirent. Names are valid in the getdents buffer during process_dir, so the clone may be unnecessary.
5. Arena allocator per thread
Replace the default allocator for transient strings with a bump allocator — allocate in bulk, free all at once.
