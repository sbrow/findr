package findr

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:thread"

RawEntry :: struct {
	name: string,
	type: linux.Dirent_Type,
}

WalkerPool :: struct {
	queue:         [dynamic]string,
	queue_mutex:   sync.Mutex,
	queue_sema:    sync.Atomic_Sema,
	results:       ^[dynamic]string,
	results_mutex: sync.Mutex,
	active:        i64,
	done:          sync.One_Shot_Event,
	threads:       [dynamic]^thread.Thread,
}

walk :: proc(root: string, results: ^[dynamic]string, thread_count: int) {
	pool := new(WalkerPool)
	pool.queue = make([dynamic]string)
	pool.results = results
	pool.active = 1
	pool.threads = make([dynamic]^thread.Thread)

	root_clone, _ := strings.clone(root)
	append(&pool.queue, root_clone)
	sync.atomic_sema_post(&pool.queue_sema)

	for i in 0 ..< thread_count {
		t := thread.create(walk_worker)
		t.data = rawptr(pool)
		t.init_context = context
		thread.start(t)
		append(&pool.threads, t)
	}

	sync.one_shot_event_wait(&pool.done)

	for _ in 0 ..< thread_count {
		sync.atomic_sema_post(&pool.queue_sema)
	}

	for t in pool.threads {
		thread.destroy(t)
	}
	delete(pool.threads)
	for path in pool.queue {
		delete(path)
	}
	delete(pool.queue)
	free(pool)
}

walk_worker :: proc(t: ^thread.Thread) {
	pool := cast(^WalkerPool)t.data

	for {
		sync.atomic_sema_wait(&pool.queue_sema)

		sync.mutex_lock(&pool.queue_mutex)
		if len(pool.queue) == 0 {
			sync.mutex_unlock(&pool.queue_mutex)
			if sync.atomic_load_explicit(&pool.active, .Acquire) == 0 {
				sync.one_shot_event_signal(&pool.done)
			}
			break
		}
		last := len(pool.queue) - 1
		dir_path := pool.queue[last]
		ordered_remove(&pool.queue, last)
		sync.mutex_unlock(&pool.queue_mutex)

		process_dir(pool, dir_path)
		delete(dir_path)

		old := sync.atomic_sub_explicit(&pool.active, 1, .Release)
		if old == 1 {
			sync.one_shot_event_signal(&pool.done)
		}
	}
}

process_dir :: proc(pool: ^WalkerPool, dir_path: string) {
	has_git := false
	entries := read_dir_entries(dir_path, &has_git)
	defer free_entries(&entries)

	if has_git {
		gi := load_gitignore(dir_path)
		defer if gi != nil {
			destroy(gi)
			free(gi)
		}

		for entry in entries {
			if entry.name == ".git" do continue
			is_dir := entry.type == .DIR
			if gi != nil && is_ignored(gi, entry.name, is_dir) {
				if !is_dir {
					full_path := join_path(dir_path, entry.name)
					sync.mutex_lock(&pool.results_mutex)
					append(pool.results, full_path)
					sync.mutex_unlock(&pool.results_mutex)
				}
				continue
			}
			if is_dir {
				child_path := join_path(dir_path, entry.name)
				push_work(pool, child_path)
			}
		}
	} else {
		for entry in entries {
			if entry.type == .DIR {
				child_path := join_path(dir_path, entry.name)
				push_work(pool, child_path)
			}
		}
	}
}

push_work :: proc(pool: ^WalkerPool, path: string) {
	sync.atomic_add_explicit(&pool.active, 1, .Relaxed)
	sync.mutex_lock(&pool.queue_mutex)
	append(&pool.queue, path)
	sync.mutex_unlock(&pool.queue_mutex)
	sync.atomic_sema_post(&pool.queue_sema)
}

read_dir_entries :: proc(dir_path: string, has_git: ^bool) -> [dynamic]RawEntry {
	entries := make([dynamic]RawEntry)

	cpath := strings.clone_to_cstring(dir_path)
	if cpath == nil do return entries

	fd, err := linux.open(cpath, {.DIRECTORY, .CLOEXEC})
	delete(cpath)
	if err != .NONE do return entries

	buf: [8192]u8
	has_git^ = false

	for {
		n, errno := linux.getdents(fd, buf[:])
		if n <= 0 || errno != .NONE do break

		offs := 0
		for d in linux.dirent_iterate_buf(buf[:n], &offs) {
			name := linux.dirent_name(d)
			if name == "." || name == ".." do continue

			if name == ".git" && d.type == .DIR {
				has_git^ = true
			}

			cloned := strings.clone(name)
			append(&entries, RawEntry{name = cloned, type = d.type})
		}
	}

	linux.close(fd)
	return entries
}

free_entries :: proc(entries: ^[dynamic]RawEntry) {
	for &entry in entries {
		delete(entry.name)
	}
	delete(entries^)
}

load_gitignore :: proc(dir_path: string) -> ^Gitignore {
	gi_path := join_path(dir_path, ".gitignore")
	defer delete(gi_path)

	data, err := os.read_entire_file_from_path(gi_path, context.allocator)
	if err != .NONE do return nil

	gi := new(Gitignore)
	gi^ = parse(string(data))
	delete(data)
	return gi
}

join_path :: proc(parent, child: string) -> string {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	fmt.sbprintf(&b, "%s", parent)
	if len(parent) == 0 || parent[len(parent) - 1] != '/' {
		fmt.sbprintf(&b, "/")
	}
	fmt.sbprintf(&b, "%s", child)

	s := strings.to_string(b)
	result, _ := strings.clone(s)
	return result
}

