package findr

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	args := os.args

	opts: WalkOptions
	opts.include_hidden = true
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
		case arg == "-I":
			opts.ignore_mode = .All
		case arg == "--ignored":
			opts.ignore_mode = .Ignored
		case arg == "--no-hidden":
			opts.include_hidden = false
		case arg == "-E":
			i += 1
			if i < len(args) {
				append(&excludes, args[i])
			}
		case strings.has_prefix(arg, "-E"):
			append(&excludes, arg[2:])
		case len(arg) > 0 && arg[0] == '-':
			// unknown flag, skip
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

	results := make([dynamic]string)
	defer {
		for r in results {delete(r)}
		delete(results)
	}

	thread_count := os.get_processor_core_count()
	for dir in paths {
		walk(dir, &results, opts, thread_count)
	}

	for r in results {
		fmt.println(r)
	}
}
