package sync_cargo

import "core:sync"

Cargo :: struct {
	delivery: bool,
	confirmation: sync.Parker,
}

deliver_and_wait :: proc(cargo: ^Cargo) {
	cargo.delivery = true
	sync.park(&cargo.confirmation)
}

is_pending :: proc(cargo: ^Cargo) -> bool {
	return cargo.delivery
}

accept :: proc(cargo: ^Cargo) {
	cargo.delivery = false
	sync.unpark(&cargo.confirmation)
}
