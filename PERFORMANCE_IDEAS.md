findr is 4.5x slower than fd (case 1: 658ms vs 146ms). Opportunities:
- Per-thread result buffers (eliminate mutex contention)
- Arena allocator for path strings
- Larger getdents buffer (8KB → 64KB+)
- Buffered stdout output
