package app

import "core:sync"

import "lib:fifo"

Key :: struct {
	code: Key_Code,
	state: Key_State,
}

Key_State :: enum {
	Released,
	Pressed,
	Repeated,
}

Key_Code :: enum {
	Unknown,
	Up,
	Down,
	Left,
	Right,
	Space,
	Enter,
	Escape,
	Backspace,
	Tab,
	Left_Shift,
	Right_Shift,
	Left_Control,
	Right_Control,
	Left_Alt,
	Right_Alt,
	Application,
	Caps_Lock,
	Page_Up,
	Page_Down,
	Insert,
	Delete,
	Home,
	End,
	Print_Screen,
	Scroll_Lock,
	Pause,
	Break,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Num0,
	Num1,
	Num2,
	Num3,
	Num4,
	Num5,
	Num6,
	Num7,
	Num8,
	Num9,
	Numlock,
	Numpad0,
	Numpad1,
	Numpad2,
	Numpad3,
	Numpad4,
	Numpad5,
	Numpad6,
	Numpad7,
	Numpad8,
	Numpad9,
	Multiply,
	Add,
	Subtract,
	Divide,
	Decimal,
	Separator,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	F13,
	F14,
	F15,
	F16,
	F17,
	F18,
	F19,
	F20,
	F21,
	F22,
	F23,
	F24,
	Browser_Back,
	Browser_Forward,
	Browser_Refresh,
	Browser_Stop,
	Browser_Search,
	Browser_Favorites,
	Browser_Home,
	Volume_Mute,
	Volume_Down,
	Volume_Up,
	Media_Next_Track,
	Media_Prev_Track,
	Media_Stop,
	Media_Play_Pause,
	Launch_Mail,
	Launch_Media_Select,
	Launch_App1,
	Launch_App2,
	Help,
	Plus,
	Minus,
	Comma,
	Period,
	Semicolon,
	Quotation_Mark,
	Opening_Bracket,
	Closing_Bracket,
	Slash,
	Backslash,
	Backtick,
}

Keyboard_Buffer :: fifo.FIFO(1024, Key)
Character_Buffer :: fifo.FIFO(1024, rune)

Keyboard_State :: struct {
	pressed: [Key_Code]bool,
	key_buffer: Keyboard_Buffer,
	char_buffer: Character_Buffer,
}

keyboard_get_state :: proc "contextless" () -> (keyboard_state: Keyboard_State) {
	sync.guard(&keyboard.lock)

	for &state, key in keyboard.state {
		if .Pressed in state || .Repeated in state {
			keyboard_state.pressed[key] = true
			state -= {.Repeated}
		}
		if .Released in state {
			state = {}
		}
	}

	for key in fifo.pop_safe(&keyboard.keys) {
		fifo.push(&keyboard_state.key_buffer, key)
	}

	for char in fifo.pop_safe(&keyboard.characters) {
		fifo.push(&keyboard_state.char_buffer, char)
	}

	return
}

keyboard_keys_iterate :: proc "contextless" (keyboard_state: ^Keyboard_State) -> (key: Key, ok: bool) {
	return fifo.pop_safe(&keyboard_state.key_buffer)
}

keyboard_characters_iterate :: proc "contextless" (keyboard_state: ^Keyboard_State) -> (char: rune, ok: bool) {
	return fifo.pop_safe(&keyboard_state.char_buffer)
}


Keyboard_Context :: struct {
	state: [Key_Code]bit_set[Key_State],
	keys: Keyboard_Buffer,
	characters: Character_Buffer,
	lock: sync.Mutex,
}
keyboard: Keyboard_Context

_keyboard_register_key :: proc "contextless" (key: Key) {
	sync.guard(&keyboard.lock)

	fifo.push(&keyboard.keys, key)
	keyboard.state[key.code] += {key.state}
}

_keyboard_register_character :: proc "contextless" (char: rune) {
	sync.guard(&keyboard.lock)

	fifo.push(&keyboard.characters, char)
}

_keyboard_reset :: proc "contextless" () {
	sync.guard(&keyboard.lock)

	for &state, key in keyboard.state {
		if .Pressed in state && .Released not_in state {
			fifo.push(&keyboard.keys, Key{key, .Released})
			state += {.Released}
		}
	}
}
