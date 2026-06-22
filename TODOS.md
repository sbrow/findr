# TODOS

## `collect_worker` improvements

- [ ] `bytes.index_byte`, `#no_bounds_check`

```odin
collect_worker :: proc(t: ^thread.Thread) {
	data := cast(^Collector_Data)t.data
	for {
		batch, ok := chan.recv(data.ch)
		if !ok do break
		start := 0
		for {
			remaining: []u8
			#no_bounds_check {remaining = batch[start:]}

			idx := bytes.index_byte(remaining, '\n')
			if idx < 0 do break

			i := start + idx
			if i > start {
				segment: []u8
				#no_bounds_check {segment = batch[start:i]}
				s, _ := strings.clone(string(segment))
				append(data.results, s)
			}
			start = i + 1
		}
		delete(batch)
	}
}
```

## Bugs

- [ ] **`test_dir_only_pattern` overwrites `.gitignore`** (findr_test.odin:58-72) — Second `create_file` for `repo/.gitignore` replaces the `node_modules/` rule with `ignored_dir/`. The test never verifies that `node_modules/` doesn't match a file named `node_modules`. Fix: combine into one `create_file` call.
- [ ] **`join_path` produces `"/child"` for empty parent** (walker.odin:468-480) — `need_sep := len(parent) == 0 || ...` is wrong: empty parent shouldn't add a separator. `join_path("", "foo")` returns `"/foo"` instead of `"foo"`. No current caller hits this path, but it's a latent bug.
- [ ] **`flake.nix` is copy-pasted from envr** — Binary named `envr` instead of `findr`; includes `libsodium`/`sqlite` deps findr doesn't use; package metadata is all wrong.

## Stale Documentation

- [ ] **PLAN.md contradicts implementation** — Says "No dedicated glob matcher" / "Transpile to regex" but `glob.odin` is a dedicated glob matcher. Says only `DT_REG`/`DT_UNKNOWN` emitted but code emits all non-dir types (FIFOs confirmed by `test_fifo_emitted`). Glob→regex table (lines 151-164) is entirely outdated.

## Design Concerns

- [ ] **`DT_UNKNOWN` directories silently treated as files** (walker.odin:322-323) — On XFS/BTRFS/FUSE, `d.type` can be `DT_UNKNOWN`. Code treats these as non-dir files, so directories won't be descended into. Add stat fallback.
- [ ] **`build_rel` silently truncates at 4096 bytes** (walker.odin:310, 399-408) — `rel_buf` is a fixed 4096-byte stack buffer. If `rel + name` exceeds this, the path is silently truncated with no error, potentially causing incorrect gitignore matching for very deep paths.
