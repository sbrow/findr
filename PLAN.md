# findr — Native Odin File Finder (fd Replacement)

## Overview

findr is a native Odin file finder that replaces `fd` in envr. It supports three ignore modes for A/B benchmarking against specific fd commands, plus a unique "emit ONLY gitignored files" mode that gives envr a single-pass advantage over fd's double-run-and-diff approach.

## Directory Structure

```
findr/
  findr.odin           # main + CLI (hand-rolled arg parsing)
  walker.odin          # parallel directory walker (getdents + thread pool)
  gitignore.odin       # .gitignore parsing + glob→regex transpilation + matching
  test_env.odin        # test harness: temp dir, mock filesystem, assert helpers
  findr_test.odin      # integration tests
  gitignore_test.odin  # transpilation + matching unit tests (22 tests)
```

## CLI Interface

```
findr [-I] [--ignored] [--no-hidden] [-E <glob>]... [pattern] [path]...
```

Defaults: `include_hidden=true, ignore_mode=.Respected` (matches fd's `-H` behavior).

| fd command | findr equivalent |
|---|---|
| `fd -a \.env -E ... -HI ~/` | `findr -I -E ... \.env ~/` |
| `fd -a \.env -E ... -H ~/`  | `findr -E ... \.env ~/` |
| `fd . -H ~/`                | `findr ~/` |
| `fd . -HI ~/`               | `findr -I ~/` |
| `fd . ~/` (no flags)        | `findr --no-hidden ~/` |
| *(findr original)*          | `findr --ignored ~/` |

## Build

```bash
odin build findr -o:speed -out:findr/findr
odin test findr
```

## Architecture

### Two Orthogonal Axes (matching fd's semantics)

1. **Hidden files** (`.` prefix): `include_hidden=true` includes them, `false` excludes them
2. **Gitignore**: three modes (see `IgnoreMode` below)

### Types

```odin
IgnoreMode :: enum {
    Respected,  // skip gitignored, prune ignored dirs (fd -H default)
    All,        // ignore .gitignore entirely, descend everywhere (fd -HI)
    Ignored,    // emit ONLY gitignored files, prune ignored dirs (findr original)
}

WalkOptions :: struct {
    pattern:        string,       // regex on basename; "" = match all
    excludes:       []string,     // glob patterns to skip entirely (fd -E)
    include_hidden: bool,         // true = include dotfiles (fd -H)
    ignore_mode:    IgnoreMode,
}
```

### process_dir Filtering Order Per Entry

Each directory traversal carries a `WorkItem` with the absolute path, a relative path from repo root, and a `^GIContext` linked list of gitignore contexts (one per ancestor directory with a `.gitignore`).

1. Skip `.git` directory
2. **Load nested `.gitignore`**: If this directory has a `.gitignore`, push a new `GIContext` onto the chain (tracked in `pool.all_contexts` for cleanup)
3. **Per entry**:
   - Skip non-regular files (symlinks, sockets, etc. — parity with `fd -t f`)
   - **Excludes**: if entry matches any exclude glob → skip entirely
   - **Hidden**: if `!include_hidden && name[0] == '.'` → skip entirely
   - **Gitignore status**: check `GIContext` chain deepest-to-root via `check_chain`, passing the **relative path** (not basename). First match wins (correct gitignore precedence). Nested negation overrides parent rules.
   - **Mode-based decision**:

| Mode | gitignored file | gitignored dir | normal file | normal dir |
|---|---|---|---|---|
| `.All` | emit if pattern matches | descend | emit if pattern matches | descend |
| `.Respected` | skip | prune | emit if pattern matches | descend |
| `.Ignored` | emit if pattern matches | prune | skip | descend |

**Nested repos**: When a directory contains `.git/`, the gitignore context chain is reset (new repo root). The relative path resets to `""`. Nested repos are always traversed to find deeper repos.

### Performance Architecture

- **Stat avoidance via `dirent.type`** — Uses `core:sys/linux` getdents directly, bypassing `core:os` which calls `openat` + `fstat` per entry.
- **Prune ignored directories** — When a directory matches a gitignore/exclude pattern, it is not descended into.
- **Parallel traversal** — Worker thread pool with shared LIFO queue and futex-based semaphore signaling. 5.4x speedup over serial on home directory.

## Decisions

- **Gitignore matching**: Transpile gitignore glob patterns to regex, then use `core:text/regex`. No dedicated glob matcher.
- **Pattern matching**: Pattern is a regex (same as fd), matched against basename via `regex.match` (unanchored search).
- **Excludes**: Glob patterns compiled via the same gitignore transpiler (`parse()`). Reuses tested transpilation logic.
- **Nested gitignore**: Every `.gitignore` file within a repo is read, not just the root. Each directory's rules are scoped relative to that directory's path. Negation in a child overrides parent rules (correct gitignore precedence).
- **Stat avoidance**: Use `core:sys/linux` getdents directly — read `dirent.type` from the kernel, never call stat. `DT_UNKNOWN` treated as regular file (correct for ext4/tmpfs; may miss dirs on XFS/BTRFS/FUSE — Phase 7 concern).

## Testing Strategy

- **In-process integration tests** — Tests call `walk()` directly (not via subprocess), build mock filesystems in temp dirs, and compare sorted output.
- **Unit tests** — Pure-function tests for glob→regex transpilation and gitignore matching.
- **Output sorting for determinism** — Always sort output lines before comparison.
- **Memory tracking** — Odin's test runner reports leaks automatically.

### Test Coverage (findr_test.odin)

**`.Ignored` mode (original findr behavior):**

| Test | What it covers |
|---|---|
| `test_basic_gitignored` | Repo with `.gitignore`, gitignored files emitted, normal files skipped |
| `test_non_repo_not_scanned` | Dirs without `.git/` produce no output |
| `test_negation_pattern` | `!prod.env` un-ignores a file |
| `test_dir_only_pattern` | `node_modules/` pattern doesn't emit file results |
| `test_multiple_repos` | Multiple repos in one tree, each with its own `.gitignore` |
| `test_nested_repos` | Repo inside a repo, both scanned independently |
| `test_no_gitignore_file` | Repo with `.git/` but no `.gitignore` produces nothing |
| `test_empty_gitignore` | Comments and blank lines only → no results |
| `test_multiple_search_dirs` | Multiple top-level search dirs in one call |
| `test_nested_gitignore_read` | Nested `.gitignore` rules applied (subdir patterns work) |
| `test_nested_gitignore_negation` | Nested negation overrides parent pattern |
| `test_multisegment_pattern` | `build/output.txt` matches relative path, not just basename |

**`.All` mode (fd -HI parity):**

| Test | What it covers |
|---|---|
| `test_all_mode_emits_all_files` | All files emitted regardless of gitignore |
| `test_all_mode_descends_everywhere` | Gitignored dirs still descended |

**`.Respected` mode (fd -H parity):**

| Test | What it covers |
|---|---|
| `test_respected_mode_skips_gitignored` | Gitignored files skipped |
| `test_respected_mode_prunes_ignored_dirs` | Gitignored dirs pruned |
| `test_nested_gitignore_respected_mode` | Nested negation respected in `.Respected` mode |

**Filters:**

| Test | What it covers |
|---|---|
| `test_excludes_prune_dirs` | Excluded dirs not descended |
| `test_pattern_filters_results` | Only pattern-matching files emitted |
| `test_no_hidden_skips_dotfiles` | Hidden files skipped when include_hidden=false |

## Glob→Regex Transpilation Rules

| Gitignore pattern | Regex | Notes |
|---|---|---|
| `foo` | `(^|/)foo(/.*)?$` | matches at any depth |
| `/foo` | `^foo(/.*)?$` | anchored to gitignore dir |
| `foo/` | `(^|/)foo/.*$` | directory only |
| `*.log` | `(^|/)[^/]*\.log$` | `*` = any chars except `/` |
| `**/foo` | `(^|/)(.*/)?foo(/.*)?$` | `**` = any chars including `/` |
| `foo/**/bar` | `(^|/)foo/(.*/)?bar(/.*)?$` | `**` between segments |
| `!pattern` | (handled by layer) | negation flag, not regex |
| `#comment` | (skipped) | |
| `[abc]` | `[abc]` | same regex syntax |
| `?` | `[^/]` | single char, no `/` |

## Implementation Phases

### Phase 1: Gitignore Transpiler + Tests ✅

22 tests, all passing, zero leaks.

### Phase 2: findr Walker + Tests ✅

Parallel DFS using getdents with worker thread pool. 32 total tests pass, zero leaks.

### Phase 3: Parallel Traversal ✅

8-worker thread pool, shared LIFO queue, futex-based semaphore. 852ms vs 4.57s serial (5.4x speedup). Serial code removed — parallel is the only implementation.

### Phase 4: Benchmark ✅

findr found 227 gitignored files on `~` in 852ms. fd's double-run walked ~1.1M entries.

### Phase 5: fd-Parity API ✅

**Goal:** Make findr replicate specific fd commands for A/B benchmarking, plus keep the unique gitignored-only mode.

**Built:**
- `IgnoreMode` enum (`.Respected`, `.All`, `.Ignored`) and `WalkOptions` struct
- New `walk` signature: `walk(root, results, opts: WalkOptions, thread_count)`
- Rewritten `process_dir` with centralized mode-based filtering
- Pattern matching via `core:text/regex` on basenames
- Exclude patterns compiled via existing `gitignore.parse()`
- CLI arg parsing: `-I`, `--ignored`, `--no-hidden`, `-E <glob>`
- 7 new integration tests (17 total) covering all three modes, excludes, pattern, and hidden filtering

**Result:** All tests pass (22 gitignore + 20 walker = 42), zero leaks.

### Phase 6: Parity (partially done)

**Goal:** Achieve file-count parity with fd. An invalid benchmark (different result sets) is useless.

#### Steps 1-2: Nested gitignore + relative path matching ✅

**What was done:**

1. **`Match` enum + `check_match`** in `gitignore.odin` — Tri-state return (`None`/`Ignored`/`Unignored`) so nested negation overrides work correctly. `is_ignored` wraps it as before.

2. **`GIContext` linked list** in `walker.odin` — Each context holds a `^Gitignore`, `base_rel` (relative path from repo root to this dir), and `parent: ^GIContext`. `process_dir` loads `.gitignore` in every directory within a repo (not just roots). `check_chain` walks deepest-to-root, first match wins (correct gitignore precedence).

3. **`WorkItem` struct** replaced plain `string` in the work queue:
   ```odin
   WorkItem :: struct {
       path:    string,       // absolute directory path
       rel:     string,       // relative path from repo root ("" = root)
       gi_ctx:  ^GIContext,   // gitignore chain (nil = outside any repo)
   }
   ```

4. **Relative path matching** — `check_chain` strips each context's `base_rel` prefix to get the locally-scoped relative path. Multi-segment patterns like `build/output.txt` now match correctly.

5. **Symlink filtering** — Only `DT_REG` and `DT_UNKNOWN` entries are emitted (matching `fd -t f`). Symlinks (`DT_LNK`) are skipped.

6. **`DT_UNKNOWN` handling** — Treated as regular files (no stat fallback). Correct for ext4/tmpfs; may miss directories on XFS/BTRFS/FUSE.

**Memory management:** All `GIContext` objects tracked in `pool.all_contexts` (mutex-protected append). Gitignore objects and context structs freed in bulk when `walk` completes.

**Parity achieved** (`~`, 5M+ files):

| Mode | findr | fd equivalent | diff |
|---|---|---|---|
| `.All` (-I) | 5,426,451 | `fd -HI -t f --exclude .git` | **0 (exact)** |
| `.Respected` | 4,442,505 | `fd -H -t f --exclude .git` | +1,417 (0.03%) |
| `--no-hidden` | 393,605 | `fd -t f --exclude .git` | +17 (0.004%) |

On the envr repo itself, all three modes are **exact match (0 diffs)**. The tiny residual diffs on `~` are likely from global gitignore (`~/.config/git/ignore`) and `.git/info/exclude` which fd reads but findr doesn't.

#### Step 3: DT_UNKNOWN stat fallback (TODO)

On XFS/BTRFS/FUSE filesystems, `dirent.type` returns `DT_UNKNOWN`. Currently findr treats these as regular files, which means directories may be missed (not descended into). Add a stat fallback in `read_dir_entries` when `d.type == .UNKNOWN` to determine the real type before proceeding. This is not needed for ext4/tmpfs (what tests and most Linux systems use).

### Phase 7: Performance Optimization (next)

**Goal:** Make findr competitive with or faster than fd across all modes. Current benchmark (`~`, hyperfine 5 runs):

| Command | Mean | vs fd equivalent |
|---|---|---|
| `findr --ignored` | 984ms | *(no fd equivalent)* |
| `findr --no-hidden` | 542ms | 3.2x slower than `fd -t f` (170ms) |
| `findr` (respected) | 4.134s | 2.4x slower than `fd -H -t f` (1.745s) |
| `findr -I` (all) | 3.821s | 1.9x slower than `fd -HI -t f` (1.972s) |

**Bottleneck analysis:**

1. **Mutex contention on result collection** — Every file append goes through `sync.mutex_lock(&pool.results_mutex)` → `append` → `sync.mutex_unlock`. With 5M+ files across 16 threads, workers serialize on the mutex.

2. **`--ignored` regression** — Was 402ms before nested gitignore support, now 984ms. The overhead comes from loading `.gitignore` in every directory and checking the context chain per entry. Since `--ignored` mode prunes gitignored dirs, many of these `.gitignore` loads are wasted (the dir won't be descended into anyway). Optimization: skip loading `.gitignore` for directories that will be pruned.

3. **Per-string heap allocation** — Every path string is individually `strings.clone`'d and `delete`'d. Millions of alloc/free calls.

**Optimization plan:**

1. **Per-thread result buffers** — Each worker accumulates results in a thread-local `[dynamic]string`. Merge into shared array once at the end (single-threaded concat).

2. **Lazy gitignore loading for `.Ignored` mode** — Only load `.gitignore` when we need to decide whether to emit or descend. In `.Ignored` mode, we can check the parent context first and skip loading if the directory itself is already ignored.

3. **Arena allocator for paths** — Replace per-string `strings.clone` with a bump allocator. Free everything in one `arena_destroy` at the end.

4. **Larger getdents buffer** — Increase from 8KB to 64KB to reduce syscall count.

5. **BufWriter on stdout** — Batch `write` syscalls instead of per-line `fmt.println`.

**Success criteria:**
- `.All` mode faster than `fd -HI -t f --exclude .git`
- `.Respected` mode faster than `fd -H -t f --exclude .git`
- `--ignored` mode faster than `fd -HI -t f --exclude .git` (restore pre-regression advantage)
- Re-benchmark after each step using `findr/bench.sh`

### Phase 8: Integrate into envr

**Goal:** Replace ALL `fd` subprocess usage in envr with in-process findr calls. Remove `Feature.Fd` entirely.

#### Part A: Rewrite `scan_path` (`scan.odin`)

Replace the double-run-and-diff approach with a single `findr.walk` call using `.Ignored` mode:

```odin
// Before: fd -HI + fd -H, then diff
// After:
findr.walk(search_path, &paths, WalkOptions{
    pattern = cfg.ScanConfig.Matcher,
    excludes = cfg.ScanConfig.Exclude[:],
    include_hidden = true,
    ignore_mode = .Ignored,
}, thread_count)
```

**Delete:** `build_fd_args`, `run_fd`, `next_fd_tmp_path`, `fd_counter`, `fd_seq`, `cant_scan`.

#### Part B: Add `find_repos` and rewrite `find_git_roots` (`config.odin`)

Add a `find_repos` proc to findr that walks a tree and collects directories containing `.git/`:

```odin
find_repos :: proc(root: string, results: ^[dynamic]string, thread_count: int)
```

- Reuses worker pool architecture
- `process_dir` emits `dir_path` when `has_git == true`
- Always descends into subdirs (except `.git`) to find nested repos
- No gitignore/exclude/pattern processing

Replace `find_git_roots`'s `run_fd` call with `findr.find_repos`.

#### Part C: Remove `Feature.Fd` everywhere

| File | Change |
|---|---|
| `features.odin` | Remove `Fd` from enum, remove fd binary check |
| `cmd_scan.odin` | Remove feats/cant_scan guard + "install fd" error |
| `cmd_check.odin` | Same removal |
| `cmd_deps.odin` | Remove fd table row |
| `db.odin` | Change check to `.Git not_in feats` only; update error message |
| `scan_test.odin` | Remove `cant_scan` tests and assertions |

#### Part D: Verification

```bash
odin build findr -o:speed -out:findr/findr
odin test findr
odin build . -o:speed -out:envr
odin test .
```

## Risks

| Risk | Mitigation |
|---|---|
| Gitignore edge cases (`**/foo`, `foo/**/bar`) | Comprehensive gitignore_test.odin with spec examples |
| `DT_UNKNOWN` on XFS/BTRFS/FUSE | Phase 6 Step 3: stat fallback for unknown types |
| Global gitignore (`~/.config/git/ignore`) and `.git/info/exclude` not read | Causes ~0.03% delta vs fd. Acceptable for envr's use case (finds `.env` files in repos). |
| Thread safety of `regex.match` on shared `Regular_Expression` | Odin regex is read-only after compilation; `match` returns per-call `Captures` |
