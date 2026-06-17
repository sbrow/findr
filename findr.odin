package findr

import "core:bufio"
import "core:os"
import "core:strings"
import "core:sync/chan"
import "core:thread"

Writer_Data :: struct {
	ch: chan.Chan([]string),
}

output_writer :: proc(t: ^thread.Thread) {
	data := cast(^Writer_Data)t.data

	w: bufio.Writer
	bufio.writer_init(&w, os.to_stream(os.stdout), 1 << 13)
	defer bufio.writer_destroy(&w)

	for {
		batch, ok := chan.recv(data.ch)
		if !ok do break
		for s in batch {
			bufio.writer_write_string(&w, s)
			bufio.writer_write_byte(&w, '\n')
			delete(s)
		}
		delete(batch)
	}
	bufio.writer_flush(&w)
}

main :: proc() {
	prof_init()
	defer prof_destroy()

	args := os.args

	opts: WalkOptions
	opts.include_hidden = false
	opts.ignore_mode = .Respected

	excludes := make([dynamic]string)
	defer delete(excludes)

	pattern := ""
	paths := make([dynamic]string)
	defer delete(paths)

	i := 1
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--ignored":
			opts.ignore_mode = .Ignored
		case arg == "-E":
			i += 1
			if i < len(args) {
				append(&excludes, args[i])
			}
		case strings.has_prefix(arg, "-E"):
			append(&excludes, arg[2:])
		case len(arg) > 1 && arg[0] == '-':
			for c, j in arg[1:] {
				switch c {
				case 'H':
					opts.include_hidden = true
				case 'I':
					opts.ignore_mode = .All
				case 'a':
				// no-op: accepted for fd compatibility
				}
			}
		case:
			if pattern == "" {
				pattern = arg
			} else {
				append(&paths, arg)
			}
		}
		i += 1
	}

	if len(paths) == 0 && pattern != "" && os.exists(pattern) {
		append(&paths, pattern)
		pattern = ""
	}

	opts.pattern = pattern
	if len(excludes) > 0 {
		opts.excludes = excludes[:]
	}

	if len(paths) == 0 {
		append(&paths, ".")
	}

	thread_count := os.get_processor_core_count()

	ch, _ := chan.create(chan.Chan([]string), max(2 * thread_count, 2), context.allocator)
	defer chan.destroy(ch)

	wdata := new(Writer_Data)
	wdata.ch = ch
	defer free(wdata)

	writer := thread.create(output_writer)
	writer.data = rawptr(wdata)
	writer.init_context = context
	thread.start(writer)

	walk_stream(paths[:], ch, opts, thread_count)

	chan.close(ch)
	thread.join(writer)
	thread.destroy(writer)
}

