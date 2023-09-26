package main

import "core:sync"

Triple_Buffer :: struct($T: typeid) {
	front_buffer: ^T,
	middle_buffer: ^T,
	back_buffer: ^T,

	buffers: [3]T,
	lock: sync.Mutex,
	updated: bool,
}

triple_buffer_init :: proc(buf: ^$B/Triple_Buffer($T)) {
	buf.front_buffer = &buf.buffers[1]
	buf.middle_buffer = &buf.buffers[0]
	buf.back_buffer = &buf.buffers[2]
}

// Should be called by the producer after filling the back_buffer
triple_buffer_push :: proc(buf: ^$B/Triple_Buffer($T)) {
	sync.guard(&buf.lock)
	buf.middle_buffer, buf.back_buffer = buf.back_buffer, buf.middle_buffer
	buf.updated = true
}

// Should be called by the consumer to update the front_buffer
triple_buffer_fetch :: proc(buf: ^$B/Triple_Buffer($T)) {
	if buf.updated {
		sync.guard(&buf.lock)
		buf.middle_buffer, buf.front_buffer = buf.front_buffer, buf.middle_buffer
		buf.updated = false
	}
}
