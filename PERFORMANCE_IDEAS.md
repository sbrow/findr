findr is 4.5x slower than fd (case 1: 658ms vs 146ms). Opportunities:
- Per-thread result buffers (eliminate mutex contention)
- Arena allocator for path strings
- Larger getdents buffer (8KB → 64KB+)
- Buffered stdout output

- Write while walking rather than waiting until the end?

1. Per-thread result buffers (biggest win)
Every result append currently takes results_mutex. With millions of files, that's millions of lock/unlock cycles. Fix: each thread accumulates results locally, then merges once when done.
2. Path allocation waste (join_path/join_path_dir)
Every path construction spins up a strings.Builder, does fmt.sbprintf, to_string, clone, then builder_destroy — 2 heap allocs + 2 frees per path. Could be a simple memcpy into a stack buffer with a single alloc.
3. Larger getdents buffer
Currently 8KB. Increasing to 64KB+ means fewer syscalls per directory with many entries.
4. Eliminate entry name cloning
strings.clone(name) in read_dir_entries heap-allocates per dirent. Names are valid in the getdents buffer during process_dir, so the clone may be unnecessary.
5. Arena allocator per thread
Replace the default allocator for transient strings with a bump allocator — allocate in bulk, free all at once.
