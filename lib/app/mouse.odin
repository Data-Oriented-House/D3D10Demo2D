package app

import "core:sync"

import "lib:fifo"

MOUSE_FIFO_SIZE :: 64

Mouse_Button :: struct {
	code: Mouse_Button_Code,
	state: Mouse_Button_State,
}

Mouse_Button_State :: enum {
	Released,
	Clicked,
	// TODO: Double clicks? I hate the concept of a double click, so I'm hesitant.
}

Mouse_Button_Code :: enum {
	Left,
	Right,
	Middle,
	X1,
	X2,
}

Mouse_Buffer :: fifo.FIFO(64, Mouse_Button)

Mouse_State :: struct {
	pressed: [Mouse_Button_Code]bool,
	buffer: Mouse_Buffer,
	wheel: f32,
	relative_pos: [2]i16,
	pos: [2]i16,
}

mouse_get_state :: proc "contextless" () -> (mouse_state: Mouse_State) {
	sync.guard(&mouse.lock)

	for &state, button in mouse.state {
		if .Clicked in state {
			mouse_state.pressed[button] = true
		}
		if .Released in state {
			state = {}
		}
	}

	for button in fifo.pop_safe(&mouse.buttons) {
		fifo.push(&mouse_state.buffer, button)
	}

	mouse_state.wheel = mouse.wheel
	mouse.wheel = 0

	mouse_state.relative_pos = mouse.relative_pos
	mouse.relative_pos = 0

	mouse_state.pos = get_mouse_pos()

	return
}

mouse_buttons_iterate :: proc "contextless" (mouse_state: ^Mouse_State) -> (button: Mouse_Button, ok: bool) {
	return fifo.pop_safe(&mouse_state.buffer)
}


Mouse_Context :: struct {
	state: [Mouse_Button_Code]bit_set[Mouse_Button_State],
	buttons: Mouse_Buffer,
	wheel: f32,
	relative_pos: [2]i16,
	lock: sync.Mutex,
}
mouse: Mouse_Context

_mouse_register_button :: proc "contextless" (button: Mouse_Button) {
	sync.guard(&mouse.lock)

	fifo.push(&mouse.buttons, button)
	mouse.state[button.code] += {button.state}
}

_mouse_register_wheel :: proc "contextless" (delta: f32) {
	sync.guard(&mouse.lock)

	mouse.wheel += delta
}

_mouse_register_relative_pos :: proc "contextless" (pos: [2]i16) {
	sync.guard(&mouse.lock)

	mouse.relative_pos += pos
}

_mouse_reset :: proc "contextless" () {
	sync.guard(&mouse.lock)

	for &state, button in mouse.state {
		if .Clicked in state && .Released not_in state {
			fifo.push(&mouse.buttons, Mouse_Button{button, .Released})
			state += {.Released}
		}
	}
}
