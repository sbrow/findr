# TODOS

- [ ] add `flake.nix`

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
