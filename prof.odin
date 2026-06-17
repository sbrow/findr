package findr

import "base:runtime"
import "core:prof/spall"
import "core:sync"

SPALL_ENABLED :: #config(SPALL_ENABLED, ODIN_DEBUG)

spall_ctx: spall.Context

@(thread_local) spall_buffer: spall.Buffer
@(thread_local) spall_backing: []u8

@(instrumentation_enter)
spall_enter :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	when SPALL_ENABLED {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (
	proc_address, call_site_return_address: rawptr,
	loc: runtime.Source_Code_Location,
) {
	when SPALL_ENABLED {
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
