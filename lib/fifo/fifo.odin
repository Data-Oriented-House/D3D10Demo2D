package fifo

FIFO :: struct($N: uint, $T: typeid) {
	buffer: [N]T,
	len: uint,
}

push :: proc "contextless" (fifo: $F/^FIFO($N, $T), n: T) {
	copy(fifo.buffer[1:], fifo.buffer[:])
	fifo.buffer[0] = n
	if fifo.len < N {
		fifo.len += 1
	}
}

pop_safe :: proc "contextless" (fifo: $F/^FIFO($N, $T)) -> (n: T, ok: bool) {
	if fifo.len == 0 {
		return
	}
	fifo.len -= 1
	n = fifo.buffer[fifo.len]
	ok = true
	return
}

// Returns a reversed slice (from most recent to oldest)
slice :: proc "contextless" (fifo: $F/^FIFO($N, $T)) -> []T {
	return fifo.buffer[:fifo.len]
}
