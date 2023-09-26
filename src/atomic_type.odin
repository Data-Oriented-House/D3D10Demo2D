package main

import "core:sync"

// Atomic_Type is a purely atomic (no mutexes used) storage; it can store any type with size less than register size
Atomic_Type :: struct($T: typeid) where size_of(T) <= size_of(uintptr) {
	data: uintptr,
}

atomic_type_save :: proc(a: $A/^Atomic_Type($T), v: T) {
	data: [size_of(uintptr)]byte = ---
	(cast(^T)&data)^ = v
	sync.atomic_store(&a.data, transmute(uintptr)data)
}

atomic_type_load :: proc(a: $A/^Atomic_Type($T)) -> (v: T) {
	data := sync.atomic_load(&a.data)
	return (cast(^T)&data)^
}
