package app

/*
TODO

expose hittest API for drag-n-drop
*/

import "core:fmt"
import "core:sync"
import "core:thread"
import "core:strings"
import "core:runtime"
import sar "core:container/small_array"

import "lib:cargo"

// DOSBox resolution
MIN_SIZE :: [2]u32{320, 200}

Window_Pos :: enum {
	Centered,
	Default,
}

App_Flag :: enum {
	Maximized,
	Fullscreen,
	// Disallow other instances of the app to run simultaneously
	No_Clones,
	// Use parameters supplied to run() instead of restoring them from previous launches
	Reset,
}
App_Flags :: distinct bit_set[App_Flag; u8]

Window_State :: enum {
	Created,
	Closed,
	Close_Disabled,
	Maximized,
	Minimized,
	Fullscreen,
	Focused,
	Cursor_Inside,
	Cursor_Hidden,
	Cursor_Relative,
	// TODO: Cursor_Confined: [win32.ClipCursor] needed for games that pan the screen, like strategies.
	// Actually do I need confined cursor, or is it better to have relative mode and software cursor instead???
}

Window_Context :: struct {
	// TODO: Values to backup
	app_id: string,
	pos: [2]i32,
	size: [2]u32,
	// This one idk, I think user should be able to rename it...
	title: string,
	// State accessible to the user through functions
	framebuffer_size: [2]u32,
	monitor_size: [2]u32,
	monitor_refresh_rate: u32,
	state: bit_set[Window_State],
	mouse_pos: [2]i16,
	relative_mouse_pos: [2]i16,
	// Synchronization with the graphics thread
	ready: sync.Parker,
	quit: sync.Parker,
	graphics_quit: cargo.Cargo,

	using window_specific: Window_Context_OS_Specific,
	using graphics_specific: Graphics_Context_OS_Specific,
}
window: Window_Context

Frame_Context :: struct {
	will_quit: bool,
	size: [2]u32,
	using specific: Graphics_Context_OS_Specific,
}

App_Loop_Mode :: enum {
	Uninitialized,
	Frame_Start,
	Frame_End,
}

App_State :: struct {
	loop_mode: App_Loop_Mode,
	frame: Frame_Context,
}
app_state: App_State

heap_allocator := runtime.default_allocator()

run :: proc(
	app_id: string,
	title: string = "Window",
	pos: Window_Pos = .Centered,
	size: [2]u32 = {},
	flags: App_Flags = {},
) -> (Frame_Context, bool) {
	APP_LOOP: for {
		switch app_state.loop_mode {
		case .Uninitialized:
			_app_init(app_id, title, pos, size, flags)
			fallthrough
		case .Frame_Start:
			framebuffer_size := get_framebuffer_size()
			if app_state.frame.size != framebuffer_size {
				app_state.frame.size = framebuffer_size
				_graphics_resize_framebuffer(framebuffer_size)
			}

			app_state.frame.specific = window.graphics_specific
			// 1 frame to let the frame proc know app is about to quit
			app_state.frame.will_quit = cargo.is_pending(&window.graphics_quit)
			_graphics_frame_prepare()

			app_state.loop_mode = .Frame_End
			return app_state.frame, true
		case .Frame_End:
			_graphics_frame_present()

			app_state.loop_mode = .Frame_Start
			if !app_state.frame.will_quit {
				continue APP_LOOP
			}

			_graphics_finish()

			// TODO: At this point I have to save the state to the appid location
			fmt.println(window.state, window.pos, window.size)

			cargo.accept(&window.graphics_quit)

			return app_state.frame, false
		}
	}
}

close :: proc() {
	close_enable()
	_close()
}

close_disable :: proc() {
	window.state += {.Close_Disabled}
}

close_enable :: proc() {
	window.state -= {.Close_Disabled}
}

get_framebuffer_size :: proc "contextless" () -> [2]u32 {
	return transmute([2]u32)sync.atomic_load(cast(^u64)&window.framebuffer_size)
}

get_monitor_size :: #force_inline proc "contextless" () -> [2]u32 {
	return transmute([2]u32)sync.atomic_load(cast(^u64)&window.monitor_size)
}

get_monitor_refresh_rate :: #force_inline proc "contextless" () -> u32 {
	return sync.atomic_load(&window.monitor_refresh_rate)
}

get_mouse_pos :: #force_inline proc "contextless" () -> [2]i16 {
	return transmute([2]i16)sync.atomic_load(cast(^i32)&window.mouse_pos)
}

toggle_fullscreen :: #force_inline proc "contextless" () { _toggle_fullscreen() }
is_fullscreen :: #force_inline proc "contextless" () -> bool { return .Fullscreen in window.state }

set_cursor_hidden :: #force_inline proc "contextless" (hide: bool) { _set_cursor_hidden(hide) }
is_cursor_hidden :: #force_inline proc "contextless" () -> bool { return .Cursor_Hidden in window.state }

set_cursor_relative :: #force_inline proc "contextless" (relative: bool) { _set_cursor_relative(relative) }
is_cursor_relative :: #force_inline proc "contextless" () -> bool { return .Cursor_Relative in window.state }

// Useful for pausing the game when window loses focus, or for muting sound
is_focused :: #force_inline proc "contextless" () -> bool { return .Focused in window.state }



// NOTE: In a perfect OS window size should be controlled by the user, not by the program.
// But since OSes do not remember window positions, you would have to restore them manually.
// This library does it for you automatically. (TODO)
maximize :: #force_inline proc() { _maximize() }
is_maximized :: #force_inline proc() -> bool { return .Maximized in window.state }
minimize :: #force_inline proc() { _minimize() }
restore  :: #force_inline proc() { _restore() }

_app_init :: proc(app_id: string, title: string, pos: Window_Pos, size: [2]u32, flags: App_Flags) {
	assert(.Created not_in window.state)

	size := size
	if size != {} {
		size.x = max(MIN_SIZE.x, size.x)
		size.y = max(MIN_SIZE.y, size.y)
	}

	{
		context.allocator = heap_allocator
		window.app_id = strings.clone(app_id)
		window.title = strings.clone(title)

		// TODO: Check app_id backup and restore size/pos/flags
		pos := pos
		size := size
		flags := flags

		thread.run_with_poly_data3(arg1 = pos, arg2 = size, arg3 = flags, fn = _window_proc, priority = .High)
	}

	sync.park(&window.ready)
	_graphics_init()
}

_window_proc :: proc(pos: Window_Pos, size: [2]u32, flags: App_Flags) {
	_window_create(pos, size, flags)
	defer _window_destroy()

	// Notify graphics to start
	sync.unpark(&window.ready)

	for (.Closed not_in window.state) {
		_pump_events()
	}

	// Notify graphics to stop
	cargo.deliver_and_wait(&window.graphics_quit)
}

@(private)
array_cast :: proc "contextless" ($Elem_Type: typeid, v: [$N]$T) -> (w: [N]Elem_Type) #no_bounds_check {
	for i in 0..<N {
		w[i] = Elem_Type(v[i])
	}
	return
}
