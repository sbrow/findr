package findr

import "base:runtime"
import "core:os"
import "core:prof/spall"
import "core:sync"
import "core:sys/linux"

SPALL_ENABLED :: #config(SPALL_ENABLED, ODIN_DEBUG)

SPALL_MAX_BYTES :: 1 * 1024 * 1024 * 1024

_SPALL_LIMIT_MSG := "findr: spall recording reached 1 GiB limit, exiting\n"

spall_bytes_written: int

spall_ctx: spall.Context

@(thread_local) spall_buffer: spall.Buffer
@(thread_local) spall_backing: []u8

@(instrumentation_enter)
spall_enter :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	when SPALL_ENABLED {
		if spall_buffer.head + spall.BEGIN_EVENT_MAX > len(spall_buffer.data) {
			spall_bytes_written += spall_buffer.head
			if spall_bytes_written >= SPALL_MAX_BYTES {
				linux.write(2, transmute([]u8)_SPALL_LIMIT_MSG)
				spall.buffer_flush(&spall_ctx, &spall_buffer)
				os.exit(0)
			}
		}
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	when SPALL_ENABLED {
		if spall_buffer.head + size_of(spall.End_Event) > len(spall_buffer.data) {
			spall_bytes_written += spall_buffer.head
			if spall_bytes_written >= SPALL_MAX_BYTES {
				linux.write(2, transmute([]u8)_SPALL_LIMIT_MSG)
				spall.buffer_flush(&spall_ctx, &spall_buffer)
				os.exit(0)
			}
		}
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

prof_init :: proc() {
	when SPALL_ENABLED {
		spall_ctx = spall.context_create_with_scale("findr.spall", false, 1.0)
		spall_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
		spall_buffer = spall.buffer_create(spall_backing, u32(sync.current_thread_id()))
		spall._buffer_name_thread(&spall_ctx, &spall_buffer, "main")
	}
}

prof_destroy :: proc() {
	when SPALL_ENABLED {
		spall.buffer_destroy(&spall_ctx, &spall_buffer)
		delete(spall_backing)
		spall.context_destroy(&spall_ctx)
	}
}

prof_thread_init :: proc(name: string) {
	when SPALL_ENABLED {
		spall_backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
		spall_buffer = spall.buffer_create(spall_backing, u32(sync.current_thread_id()))
		spall._buffer_name_thread(&spall_ctx, &spall_buffer, name)
	}
}

prof_thread_destroy :: proc() {
	when SPALL_ENABLED {
		spall.buffer_destroy(&spall_ctx, &spall_buffer)
		delete(spall_backing)
	}
}
