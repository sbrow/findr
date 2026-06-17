package findr

import "core:fmt"
import "core:os"

main :: proc() {
	args := os.args

	search_dirs := make([dynamic]string)
	defer delete(search_dirs)

	for i in 1 ..< len(args) {
		append(&search_dirs, args[i])
	}

	if len(search_dirs) == 0 {
		append(&search_dirs, ".")
	}

	results := make([dynamic]string)
	defer {
		for r in results {delete(r)}
		delete(results)
	}

	thread_count := os.get_processor_core_count()
	for dir in search_dirs {
		walk(dir, &results, thread_count)
	}

	for r in results {
		fmt.println(r)
	}
}

