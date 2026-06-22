# findr

A partial port of [fd](https://github.com/sharkdp/fd) to
[Odin](https://odin-lang.org/)

Only the `-H`, `-I`, and `-E` flags are supported.

`findr` runs faster than fd on my machine, but feel free to check out the
results for yourself:

```markdown
=== findr benchmark suite ===
Target: /home/spencer


=== File counts ===

  fd -a -E .jj .                :   460921
  findr -E .jj                  :   460838

  fd -a -E .git -E .jj -H .     :  3593254
  findr -E .git -E .jj -H       :  3593254

  fd -a -E .git -E .jj -HI .    :  4142964
  findr -E .git -E .jj -HI      :  4142964

  fd -a -E .git -E .jj .        :   460921
  findr -E .git -E .jj          :   460838

=== Benchmarks (hyperfine, 5 runs, 2 warmups) ===

Benchmark 1: fd -a -E .jj . "/home/spencer" > /dev/null
  Time (mean ± σ):     150.7 ms ±   5.0 ms    [User: 1279.9 ms, System: 855.6 ms]
  Range (min … max):   147.0 ms … 159.3 ms    5 runs

Benchmark 2: /home/spencer/github.com/findr/findr -E .jj "/home/spencer" > /dev/null
  Time (mean ± σ):      97.4 ms ±   0.9 ms    [User: 466.5 ms, System: 924.5 ms]
  Range (min … max):    96.3 ms …  98.2 ms    5 runs

Benchmark 3: fd -a -E .git -E .jj -H . "/home/spencer" > /dev/null
  Time (mean ± σ):     776.1 ms ±  25.9 ms    [User: 7444.3 ms, System: 4268.7 ms]
  Range (min … max):   745.5 ms … 815.3 ms    5 runs

Benchmark 4: /home/spencer/github.com/findr/findr -E .git -E .jj -H "/home/spencer" > /dev/null
  Time (mean ± σ):     437.1 ms ±   5.4 ms    [User: 1674.3 ms, System: 4566.7 ms]
  Range (min … max):   430.0 ms … 442.4 ms    5 runs

Benchmark 5: fd -a -E .git -E .jj -HI . "/home/spencer" > /dev/null
  Time (mean ± σ):     704.1 ms ±  12.9 ms    [User: 7049.0 ms, System: 3537.1 ms]
  Range (min … max):   687.6 ms … 721.9 ms    5 runs

Benchmark 6: /home/spencer/github.com/findr/findr -E .git -E .jj -HI "/home/spencer" > /dev/null
  Time (mean ± σ):     387.3 ms ±  24.9 ms    [User: 1828.2 ms, System: 3414.5 ms]
  Range (min … max):   363.3 ms … 427.7 ms    5 runs

Benchmark 7: fd -a -E .git -E .jj . "/home/spencer" > /dev/null
  Time (mean ± σ):     170.3 ms ±   1.6 ms    [User: 1505.3 ms, System: 996.8 ms]
  Range (min … max):   169.3 ms … 173.1 ms    5 runs

Benchmark 8: /home/spencer/github.com/findr/findr -E .git -E .jj "/home/spencer" > /dev/null
  Time (mean ± σ):     105.5 ms ±   1.2 ms    [User: 524.9 ms, System: 1011.0 ms]
  Range (min … max):   103.7 ms … 106.9 ms    5 runs

Summary
  /home/spencer/github.com/findr/findr -E .jj "/home/spencer" > /dev/null ran
    1.08 ± 0.02 times faster than /home/spencer/github.com/findr/findr -E .git -E .jj "/home/spencer" > /dev/null
    1.55 ± 0.05 times faster than fd -a -E .jj . "/home/spencer" > /dev/null
    1.75 ± 0.02 times faster than fd -a -E .git -E .jj . "/home/spencer" > /dev/null
    3.98 ± 0.26 times faster than /home/spencer/github.com/findr/findr -E .git -E .jj -HI "/home/spencer" > /dev/null
    4.49 ± 0.07 times faster than /home/spencer/github.com/findr/findr -E .git -E .jj -H "/home/spencer" > /dev/null
    7.23 ± 0.15 times faster than fd -a -E .git -E .jj -HI . "/home/spencer" > /dev/null
    7.97 ± 0.28 times faster than fd -a -E .git -E .jj -H . "/home/spencer" > /dev/null

=== Results written to /home/spencer/github.com/findr/bench-results.md ===
```
