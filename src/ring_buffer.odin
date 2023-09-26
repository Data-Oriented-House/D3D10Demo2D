package main

Ring_Buffer :: struct($N: uint, $T: typeid) {
	data: [N]T,
	len: uint,
	write_cursor: uint,
	read_cursor: uint,
}

ring_buffer_push :: proc(buf: ^$B/Ring_Buffer($N, $T), item: T) {
	buf.data[buf.write_cursor] = item
	if buf.len == N {
		buf.read_cursor = (buf.read_cursor + 1) % N
	}
	buf.len = min(buf.len + 1, N)
	buf.write_cursor = (buf.write_cursor + 1) % N
}

ring_buffer_iterator :: proc(buf: ^$B/Ring_Buffer($N, $T)) -> (item: T, ok: bool) {
	if buf.len == 0 {
		return
	}

	item = buf.data[buf.read_cursor]
	ok = true

	buf.len -= 1
	buf.read_cursor = (buf.read_cursor + 1) % N

	return
}

ring_buffer_is_empty :: proc(buf: ^$B/Ring_Buffer($N, $T)) -> bool {
	return buf.len == 0
}
