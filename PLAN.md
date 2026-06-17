# findr — Gitignored File Finder

## Overview

findr is a native Odin tool that finds **gitignored files** within git repositories. It replaces envr's current approach of running `fd` twice (all files vs. unignored files) and diffing the results.

**Simplified scope:** findr does one thing — walks directories, finds git repos, reads each repo's `.gitignore`, and prints every gitignored file. No flags, no filtering, no pattern matching. envr handles result filtering itself.

## Current fd Usage in envr (being replaced)

1. **`scan.odin:13-43`** (`scan_path`) — runs `fd` twice per search path:
   - Run 1: `fd -a <matcher> [-E <exclude>]... -HI <path>` → all files including gitignored
   - Run 2: `fd -a <matcher> [-E <exclude>]... -H <path>` → hidden but NOT gitignored
   - Diff = gitignored files only
2. Both go through `run_fd` (`scan.odin:68-118`), which spawns a subprocess and captures output via temp files.

After findr integration, `scan_path` calls `findr.walk(path)` directly — no subprocess, no double-run, no diff.

## Directory Structure

```
findr/
  findr.odin           # main + CLI (positional dir args only)
  walker.odin          # recursive directory walker using core:sys/linux getdents
  gitignore.odin       # .gitignore parsing + glob→regex transpilation + matching
  test_env.odin        # test harness: temp dir, mock filesystem, assert helpers
  findr_test.odin      # integration tests (10 tests)
  gitignore_test.odin  # transpilation + matching unit tests (22 tests)
```

## Decisions

- **Scope**: findr prints ALL gitignored files. No regex filtering, no exclude patterns, no type filters. envr post-processes the output.
- **Gitignore matching**: Transpile gitignore glob patterns to regex, then use `core:text/regex`. No dedicated glob matcher.
- **Stat avoidance**: Use `core:sys/linux` getdents directly — read `dirent.type` from the kernel, never call stat.
- **Architecture**: Separate directory with its own `main`. Core logic (`walk` proc + `gitignore` package) designed to be importable into envr later.

## CLI Interface

```
findr [dir1] [dir2] ...
```

No flags. Defaults to `.` if no dirs given. Prints absolute or relative paths (as given) to stdout, one per line.

## Build

```bash
odin build findr -o:speed -out:findr/findr
```

## How It Works

```
walk(dir):
  entries = getdents(dir)         # via core:sys/linux, zero stat calls
  if entries contains ".git/":
    gi = parse(.gitignore)        # if present
    for entry in entries:
      if entry is gitignored file:
        emit entry path
      if entry is dir (not ignored):
        walk(entry)               # recurse to find nested repos
  else:
    for entry in entries:
      if entry is dir:
        walk(entry)               # descend looking for repos
```

Key behaviors:
- **Nested repos**: When a repo is found, subdirectories are still traversed to find nested repos. Gitignored directories are pruned (not descended into).
- **Flat gitignore**: Only the root `.gitignore` is read. `.gitignore` files in subdirectories of a repo are ignored.
- **Non-repo dirs**: Traversed recursively to find repos. No gitignore rules apply.

## Performance Architecture

### Implemented

- **Stat avoidance via `dirent.type`** — Uses `core:sys/linux` getdents directly, bypassing `core:os` which calls `openat` + `fstat` per entry. File type comes free from the directory entry.
- **Prune ignored directories** — When a directory matches a gitignore pattern, it is not descended into. Skips potentially thousands of readdir calls.
- **Parallel traversal** — 8-worker thread pool with shared LIFO queue and futex-based semaphore signaling. 5.4x speedup over serial on home directory.

### Future (if needed)

- BufWriter on stdout for large result sets
- Arena allocators for path strings

## Testing Strategy

- **In-process integration tests** — Tests call `walk()` directly (not via subprocess), build mock filesystems in temp dirs, and compare sorted output.
- **Unit tests** — Pure-function tests for glob→regex transpilation and gitignore matching.
- **Output sorting for determinism** — Always sort output lines before comparison.
- **Memory tracking** — Odin's test runner reports leaks automatically. All 32 tests pass with zero leaks.

### Test Coverage (findr_test.odin)

| Test | What it covers |
|---|---|
| `test_basic_gitignored` | Repo with `.gitignore`, gitignored files emitted, normal files skipped |
| `test_non_repo_not_scanned` | Dirs without `.git/` produce no output |
| `test_negation_pattern` | `!prod.env` un-ignores a file |
| `test_dir_only_pattern` | `node_modules/` pattern doesn't emit file results |
| `test_multiple_repos` | Multiple repos in one tree, each with its own `.gitignore` |
| `test_nested_repos` | Repo inside a repo, both scanned independently |
| `test_gitignore_in_subdir_ignored` | Subdirectory `.gitignore` files are not read |
| `test_no_gitignore_file` | Repo with `.git/` but no `.gitignore` produces nothing |
| `test_empty_gitignore` | Comments and blank lines only → no results |
| `test_multiple_search_dirs` | Multiple top-level search dirs in one call |

### Gitignore Unit Tests (gitignore_test.odin)

22 tests covering: simple/anchored patterns, `*`, `?`, `[abc]`, `[!abc]`, dot escaping, globstar variants, backslash escapes, empty patterns, basic matching, negation, dir-only, comments, blank lines, last-match-wins, env patterns.

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

**Goal:** Isolated, fully-tested glob→regex transpiler.

**Result:** 22 tests, all passing, zero leaks.

---

### Phase 2: findr Walker + Tests ✅

**Goal:** Working tool that finds gitignored files in git repos.

**Built:**
- `walker.odin` — Parallel DFS using `core:sys/linux` getdents with 8-worker thread pool. Finds repos, reads `.gitignore`, emits gitignored files, recurses into subdirs for nested repos.
- `findr.odin` — Minimal CLI: `findr [dirs...]`, no flags.
- `test_env.odin` — Test harness with temp dirs and mock filesystems.
- `findr_test.odin` — 10 integration tests.

**Result:** All 32 tests pass (22 gitignore + 10 walker), zero leaks.

---

### Phase 3: Parallel Traversal ✅

**Goal:** Parallelize directory descent for large trees.

**Result:** Worker pool with shared LIFO queue, 8 threads, futex-based semaphore signaling. 852ms vs 4.57s serial (5.4x speedup) on `~`. Serial code has been removed — parallel is the only implementation.

---

### Phase 4: Benchmark ✅

**Goal:** Quantify performance vs fd on large directory trees.

**Result:** findr found 227 gitignored files on `~` in 852ms. fd's double-run (all vs unignored) walked ~1.1M entries. findr's pruning of ignored directories (node_modules, dist, etc.) gives a massive advantage.

---

### Phase 5: Integrate into envr (future)

**Goal:** Replace ALL `fd` subprocess usage in envr with in-process findr calls. Remove `Feature.Fd` entirely.

#### Part A: Extend findr API (`findr/walker.odin`)

1. **Add `WalkMode` enum** and `mode` field to `WalkerPool`:
   ```odin
   WalkMode :: enum { GitignoredFiles, GitRepos }
   ```

2. **Extract `run_pool`** helper — shared pool setup/teardown (create threads, wait for done, cleanup). Both `walk` and `find_repos` call it.

3. **New `walk` signature with filtering:**
   ```odin
   walk :: proc(root: string, results: ^[dynamic]string, matcher: string = "", exclude: []string = nil)
   ```
   - Compiles `matcher` into a regex (stored as `pool.matcher_re`); tested against each file's basename via `regex.find`. Empty = emit all.
   - Parses `exclude` patterns into a `^Gitignore` via existing `parse()` (stored as `pool.exclude_gi`). Entries matching any exclude pattern are skipped entirely (not emitted, not descended into).
   - Sets `pool.mode = .GitignoredFiles`

4. **`process_dir` filtering logic** (in the `has_git` branch):
   - Exclude check first: `is_ignored(exclude_gi, entry.name, is_dir)` → skip entirely (prune dirs, skip files)
   - Gitignore check: if ignored, emit file only if `matcher_re` is nil or matches basename
   - Not excluded/ignored: descend if dir
   - Non-repo branch also prunes dirs matching exclude patterns

5. **New `find_repos` function:**
   ```odin
   find_repos :: proc(root: string) -> [dynamic]string
   ```
   - Creates pool with `mode = .GitRepos`, calls `run_pool`, returns collected repo roots
   - Parallel (reuses worker pool architecture)

6. **New `process_dir_repos`** — simpler than `process_dir`:
   - If `has_git`: record `dir_path` as repo root
   - Always descend into subdirs (except `.git` itself) to find nested repos
   - No gitignore/exclude/matcher processing

7. **`walk_worker` switch** — centralized control flow per AGENTS.md convention:
   ```odin
   switch pool.mode {
   case .GitignoredFiles: process_dir(pool, dir_path)
   case .GitRepos:        process_dir_repos(pool, dir_path)
   }
   ```

8. **Cleanup in `walk`:** destroy `matcher_re` and `exclude_gi` after `run_pool` completes.

9. **Add `import "core:text/regex"`** to walker.odin.

**No changes to:** `findr.odin`, `test_env.odin`, `gitignore.odin` (default params preserve existing behavior).

#### Part B: Rewrite `scan_path` (`scan.odin`)

- Add `import "findr"`
- `scan_path` becomes ~3 lines: call `findr.walk(search_path, &paths, cfg.ScanConfig.Matcher, cfg.ScanConfig.Exclude[:])`
- **Delete:** `build_fd_args`, `run_fd`, `next_fd_tmp_path`, `fd_counter`, `fd_seq`, `cant_scan`
- Remove unused imports (`core:sync`, `core:terminal`)

#### Part C: Rewrite `find_git_roots` (`config.odin`)

- Add `import "findr"`
- Replace `run_fd` call with `findr.find_repos(sp)` — no more `filepath.dir` post-processing needed (find_repos returns repo roots directly)

#### Part D: Remove `Feature.Fd` everywhere

| File | Change |
|---|---|
| `features.odin` | Remove `Fd` from enum, remove fd binary check |
| `cmd_scan.odin` | Remove feats/cant_scan guard + "install fd" error |
| `cmd_check.odin` | Same removal |
| `cmd_deps.odin` | Remove fd table row |
| `db.odin` | Change check to `.Git not_in feats` only; update error message |
| `scan_test.odin` | Remove `test_scan_meets_expectations` (cant_scan test); remove `cant_scan` assertions from other tests |

#### Part E: Verification

```bash
odin build findr -o:speed -out:findr/findr
odin test findr
odin build . -o:speed -out:envr
odin test .
```

#### Execution order

1. **findr API changes** → build + test findr (32 tests should pass with default params)
2. **Rewrite scan_path** + delete dead code
3. **Rewrite find_git_roots**
4. **Remove Feature.Fd** across all files
5. **Update tests** → build + test everything

## Risks

| Risk | Mitigation |
|---|---|
| Single-threaded may be slow on huge trees | Resolved — parallel traversal implemented (Phase 3) |
| Gitignore edge cases (`**/foo`, `foo/**/bar`) | Comprehensive gitignore_test.odin with spec examples |
| dirent.type may be UNKNOWN on some filesystems | Fall back to stat only when type is UNKNOWN |
| Missing nested `.env` files in monorepos | Accepted limitation — flat gitignore model |
| Memory allocation churn from path strings | Use thread-local arena allocators in Phase 3 |
