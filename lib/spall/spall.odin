package spall_helper

import "core:mem"
import "core:sync"
import "core:runtime"
import "core:prof/spall"

MEASURE :: #config(SPALL_MEASURE, false)
THREAD_BUFFER_SIZE :: 512 * mem.Kilobyte

ctx: spall.Context
@thread_local buf_data: []byte
@thread_local buf: spall.Buffer

heap_allocator := runtime.default_allocator()

@(disabled=!MEASURE)
init :: proc(file_name: string) {
	ctx = spall.context_create(file_name)
}

@(disabled=!MEASURE)
finish :: proc() {
	spall.context_destroy(&ctx)
}

@(disabled=!MEASURE)
thread_init :: proc() {
	buf_data = make([]byte, THREAD_BUFFER_SIZE, heap_allocator)
	buf = spall.buffer_create(buf_data, auto_cast sync.current_thread_id())
}

@(disabled=!MEASURE)
thread_finish :: proc() {
	spall.buffer_destroy(&ctx, &buf)
	delete(buf_data, heap_allocator)
}

@(deferred_none=thread_finish)
thread_scoped :: proc() {
	thread_init()
}

@(disabled=!MEASURE)
begin :: proc(name: string) {
	spall._buffer_begin(&ctx, &buf, name)
}

@(disabled=!MEASURE)
end :: proc() {
	spall._buffer_end(&ctx, &buf)
}

@(deferred_none=end)
scoped :: proc(name: string) {
	begin(name)
}
