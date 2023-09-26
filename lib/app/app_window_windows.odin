package app

import "core:os"
import "core:fmt"
import "core:time"
import "core:sync"
import "core:runtime"
import "core:container/small_array"

import win32 "core:sys/windows"

import "lib:cargo"

Window_Context_OS_Specific :: struct {
	id: win32.HWND,
	icon: win32.HICON,
	cursor: win32.HCURSOR,

	// Needed for fullscreen toggling
	wp_prev: win32.WINDOWPLACEMENT,
	// Needed to make the window size limiting work properly
	resizing_mode: bool,
	dec_size: [2]u32,
	// Needed for proper event loop
	main_fiber: rawptr,
	events_fiber: rawptr,
}

_close :: proc "contextless" () {
	win32.PostMessageW(window.id, win32.WM_CLOSE, 0, 0)
}

_toggle_fullscreen :: proc "contextless" () {
	fullscreen := .Fullscreen not_in window.state

	style := cast(u32)win32.GetWindowLongPtrW(window.id, win32.GWL_STYLE)
	if fullscreen {
		window.state += {.Fullscreen}

		monitor_info: win32.MONITORINFO = {
			cbSize = size_of(win32.MONITORINFO),
		}
		win32.GetWindowPlacement(window.id, &window.wp_prev)
		win32.GetMonitorInfoW(win32.MonitorFromWindow(window.id, .MONITOR_DEFAULTTONEAREST), &monitor_info)
		win32.SetWindowLongPtrW(window.id, win32.GWL_STYLE, cast(int)(style &~ win32.WS_OVERLAPPEDWINDOW))
		win32.SetWindowPos(
			window.id, win32.HWND_TOP,
			monitor_info.rcMonitor.left,
			monitor_info.rcMonitor.top,
			monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
			monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
			win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED,
		)
	} else {
		window.state -= {.Fullscreen}

		win32.SetWindowLongPtrW(window.id, win32.GWL_STYLE, cast(int)(style | win32.WS_OVERLAPPEDWINDOW))
		win32.SetWindowPlacement(window.id, &window.wp_prev)
		win32.SetWindowPos(
			window.id, nil, 0, 0, 0, 0,
			win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED,
		)
	}
}

_set_cursor_hidden :: proc "contextless" (hide: bool) {
	if hide {
		window.state += {.Cursor_Hidden}
		win32.SetCursor(nil)
	} else {
		window.state -= {.Cursor_Hidden}
		win32.SetCursor(window.cursor)
	}
}

_set_cursor_relative :: proc "contextless" (relative: bool) {
	if relative {
		pos: win32.POINT
		win32.GetCursorPos(&pos)
		win32.ScreenToClient(window.id, &pos)
		window.state += {.Cursor_Relative}
	} else {
		window.state -= {.Cursor_Relative}
	}
}

// Internal

_window_create :: proc(pos: Window_Pos, size: [2]u32, flags: App_Flags) {
	// NOTE: app_id and title should already be in window context
	app_id_w := win32.utf8_to_wstring(window.app_id)
	title_w := win32.utf8_to_wstring(window.title)

	if .No_Clones in flags {
		existing := win32.FindWindowW(app_id_w, nil)
		if existing != nil {
			win32.SetForegroundWindow(existing)
			os.exit(0)
		}
	}

	instance := cast(win32.HINSTANCE)win32.GetModuleHandleW(nil)
	black_brush := cast(win32.HBRUSH)win32.GetStockObject(win32.BLACK_BRUSH)
	icon := win32.LoadIconA(nil, win32.IDI_APPLICATION)
	cursor := win32.LoadCursorA(nil, win32.IDC_ARROW)

	class_style := win32.CS_OWNDC | win32.CS_DBLCLKS
	window_style := win32.WS_OVERLAPPEDWINDOW
	window_ex_style := win32.WS_EX_APPWINDOW | win32.WS_EX_NOREDIRECTIONBITMAP

	// TODO: to fix the bug with Centered, perhaps first create a window, then move it, THEN show it maximized?
	// Might mess some things up tho...
	if .Maximized in flags {
		window_style |= win32.WS_MAXIMIZE
	}

	x, y: i32 = win32.CW_USEDEFAULT, win32.CW_USEDEFAULT
	w, h: i32 = win32.CW_USEDEFAULT, win32.CW_USEDEFAULT

	if size != {} {
		w, h = cast(i32)size[0], cast(i32)size[1]
	}

	crect: win32.RECT
	if x >= 0 do crect.left = x
	if y >= 0 do crect.top = y
	if w >= 0 do crect.right = crect.left + w
	if h >= 0 do crect.bottom = crect.top + h

	// Windows will make a window with specified size as window size, not as client size, AdjustWindowRect gets the client size needed
	win32.AdjustWindowRectEx(&crect, window_style, false, window_ex_style)

	if x >= 0 do x = crect.left
	if y >= 0 do y = crect.top
	if w >= 0 do w = crect.right - crect.left
	if h >= 0 do h = crect.bottom - crect.top

	window_class: win32.WNDCLASSEXW = {
		cbSize = size_of(win32.WNDCLASSEXW),
		style = class_style,
		lpfnWndProc = _default_window_proc,
		hInstance = instance,
		hIcon = icon,
		hCursor = cursor,
		hbrBackground = black_brush,
		lpszClassName = app_id_w,
	}
	win32.RegisterClassExW(&window_class)

	// Creating hidden window
	window.id = win32.CreateWindowExW(
		dwExStyle = window_ex_style,
		lpClassName = app_id_w,
		lpWindowName = title_w,
		dwStyle = window_style,
		X = x,
		Y = y,
		nWidth = w,
		nHeight = h,
		hWndParent = nil,
		hMenu = nil,
		hInstance = instance,
		lpParam = nil,
	)
	assert(window.id != nil)

	// Setting default values
	window.icon = win32.LoadIconW(instance, win32.L("icon"))
	window.cursor = cursor
	if window.icon != nil {
		win32.SetClassLongPtrW(window.id, win32.GCLP_HICON, auto_cast cast(uintptr)window.icon)
	}

	// NOTE: if .Maximized is present, centered position will not be restored after unmaximizing.
	if pos == .Centered {
		window_size, area_pos, area_size: [2]int
		{
			wr: win32.RECT
			win32.GetWindowRect(window.id, &wr)
			window_size = {cast(int)(wr.right - wr.left), cast(int)(wr.bottom - wr.top)}
		}
		{
			wr: win32.RECT
			win32.SystemParametersInfoW(win32.SPI_GETWORKAREA, 0, &wr, 0)
			area_pos = {cast(int)wr.left, cast(int)wr.top}
			area_size = {cast(int)(wr.right - wr.left), cast(int)(wr.bottom - wr.top)}
		}

		mid_pos := (area_size - window_size) / 2
		pos := area_pos + mid_pos
		flags: u32 = win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE
		win32.SetWindowPos(window.id, nil, i32(pos.x), i32(pos.y), 0, 0, flags)
	}

	if .Maximized in flags {
		win32.ShowWindow(window.id, win32.SW_MAXIMIZE)
	} else {
		win32.ShowWindow(window.id, win32.SW_SHOW)
	}

	focused := win32.GetForegroundWindow() == window.id
	win32.PostMessageW(window.id, win32.WM_NCACTIVATE, cast(uintptr)focused, 0)

	wr, cr: win32.RECT
	point: win32.POINT
	win32.GetWindowRect(window.id, &wr)
	win32.GetClientRect(window.id, &cr)
	win32.ClientToScreen(window.id, &point)

	window.pos = {wr.left, wr.top}
	window.size = {cast(u32)(wr.right - wr.left), cast(u32)(wr.bottom - wr.top)}
	window.dec_size = {cast(u32)(wr.right - wr.left - cr.right), cast(u32)(wr.bottom - wr.top - cr.bottom)}
	window.framebuffer_size = {cast(u32)cr.right, cast(u32)cr.bottom}
	window.monitor_size, window.monitor_refresh_rate = _get_monitor_info(window.id)

	if focused {
		window.state += {.Focused}
	}

	if .Fullscreen in flags {
		toggle_fullscreen()
	}

	window.main_fiber = win32.ConvertThreadToFiber(nil)
	window.events_fiber = win32.CreateFiber(0, _events_fiber_proc, nil)
	window.state += {.Created}
}

_window_destroy :: proc() {
	win32.SwitchToFiber(window.events_fiber)
	delete(window.title, heap_allocator)
	delete(window.app_id, heap_allocator)
	window = {}
}

_pump_events :: proc() {
	win32.SwitchToFiber(window.events_fiber)
}

_events_fiber_proc :: proc "stdcall" (_: rawptr) {
	msg: win32.MSG = ---
	for win32.GetMessageW(&msg, nil, 0, 0) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
		win32.SwitchToFiber(window.main_fiber)
	}
}

_default_window_proc :: proc "stdcall" (winid: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> (result: win32.LRESULT) {
	if msg == win32.WM_DESTROY {
		win32.PostQuitMessage(0)
		return win32.DefWindowProcW(winid, msg, wparam, lparam)
	}

	if .Created not_in window.state {
		return win32.DefWindowProcW(winid, msg, wparam, lparam)
	}

	switch msg {
	case win32.WM_SYSCOMMAND:
		mode := win32.GET_SC_WPARAM(wparam)
		if mode == win32.SC_SIZE {
			window.resizing_mode = true
		}
	case win32.WM_EXITSIZEMOVE:
		window.resizing_mode = false
	case win32.WM_WINDOWPOSCHANGING: // limit window size, if need be
		// NOTE: I have no idea how this code works, and never had it to begin with
		dec_size := array_cast(i32, window.dec_size)
		min_size := array_cast(i32, MIN_SIZE)
		pos := cast(^win32.WINDOWPOS)cast(uintptr)lparam
		nw, nh := pos.cx - dec_size[0], pos.cy - dec_size[1]
		cs := array_cast(i32, window.framebuffer_size)

		if min_size[0] > 0 do nw = max(nw, min_size[0])
		if min_size[1] > 0 do nh = max(nh, min_size[1])

		if window.resizing_mode {
			// correct position when resizing from top/left
			if pos.x > window.pos.x && cs[0] > min_size[0] {
				pos.x = min(pos.x, window.pos.x + cs[0] - min_size[0])
			} else {
				pos.x = min(pos.x, window.pos.x)
			}

			if pos.y > window.pos.y && cs[1] > min_size[1] {
				pos.y = min(pos.y, window.pos.y + cs[1] - min_size[1])
			} else {
				pos.y = min(pos.y, window.pos.y)
			}
		}

		pos.cx, pos.cy = i32(nw + dec_size[0]), i32(nh + dec_size[1])
	case win32.WM_WINDOWPOSCHANGED:
		pos := cast(^win32.WINDOWPOS)cast(uintptr)lparam

		if pos.x == -32000 && pos.y == -32000 {
			window.state += {.Minimized}
		} else {
			window.state -= {.Minimized}

			if pos.x == -8 && pos.y == -8 {
				window.state += {.Maximized}
			} else {
				if .Fullscreen not_in window.state {
					window.state -= {.Maximized}
				}

				window.pos = {pos.x, pos.y}
				window.size = {cast(u32)pos.cx, cast(u32)pos.cy}

				monitor_size, monitor_refresh_rate := _get_monitor_info(winid)
				sync.atomic_store(cast(^u64)&window.monitor_size, transmute(u64)monitor_size)
				sync.atomic_store(&window.monitor_refresh_rate, monitor_refresh_rate)
			}

			rect: win32.RECT
			win32.GetClientRect(winid, &rect)
			framebuffer_size: [2]u32 = {cast(u32)rect.right, cast(u32)rect.bottom}
			sync.atomic_store(cast(^u64)&window.framebuffer_size, transmute(u64)framebuffer_size)
		}

		return 0
	case win32.WM_DISPLAYCHANGE:
		monitor_size, monitor_refresh_rate := _get_monitor_info(winid)
		sync.atomic_store(cast(^u64)&window.monitor_size, transmute(u64)monitor_size)
		sync.atomic_store(&window.monitor_refresh_rate, monitor_refresh_rate)
	case win32.WM_NCACTIVATE: // this is like WM_ACTIVATEAPP but better (or so it seems)
		focused := bool(wparam)
		if focused {
			window.state += {.Focused}
		} else {
			window.state -= {.Focused}
			_keyboard_reset()
			_mouse_reset()
		}
	case win32.WM_SETCURSOR:
		if win32.LOWORD(u32(lparam)) == win32.HTCLIENT {
			if .Cursor_Hidden in window.state {
				win32.SetCursor(nil)
			} else {
				win32.SetCursor(window.cursor)
			}
			return 1
		}
	case win32.WM_KEYDOWN, win32.WM_KEYUP, win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP:
		code: Key_Code
		state: Key_State

		scancode := u32(lparam & 0x00ff0000) >> 16
		extended := (lparam & 0x01000000) != 0
		was_pressed := (lparam & (1 << 31)) == 0
		was_released := (lparam & (1 << 30)) != 0
		alt_was_down := (lparam & (1 << 29)) != 0

		if was_pressed && was_released {
			state = .Repeated
		} else if was_released {
			state = .Released
		} else {
			state = .Pressed
		}

		// TODO: Meta key seems to be 0x5b - check on other computers
		code = vk_conversation_table[wparam] or_else .Unknown
		if code == .Unknown {
			switch wparam {
			case win32.VK_CONTROL:
				code = .Right_Control if extended else .Left_Control
			case win32.VK_MENU:
				code = .Right_Alt if extended else .Left_Alt
			case win32.VK_SHIFT:
				is_right := win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX) == win32.VK_RSHIFT
				code = .Right_Shift if is_right else .Left_Shift
			case:
				switch vk_code := win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX); vk_code {
				case win32.VK_HELP:
					code = .Help
				case:
					context = runtime.default_context()
					fmt.printf("vk_code: {3} 0x{3:x} ({4}), scancode: {2}, code: {0}, wparam = 0x{1:x} 0b{1:b}\n", code, wparam, scancode, vk_code, win32.VK_CLEAR == vk_code)
				}
			}
		}
		if code == .Unknown {
			break
		}

		if state == .Pressed && code == .F11 {
			toggle_fullscreen()
		}

		_keyboard_register_key({code, state})
	case win32.WM_CHAR:
		_keyboard_register_character(cast(rune)wparam)
	case win32.WM_LBUTTONDOWN, win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_XBUTTONDOWN,
	win32.WM_LBUTTONUP, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_XBUTTONUP,
	win32.WM_LBUTTONDBLCLK, win32.WM_RBUTTONDBLCLK, win32.WM_MBUTTONDBLCLK, win32.WM_XBUTTONDBLCLK:
		mb: Mouse_Button

		switch msg {
		case win32.WM_LBUTTONDOWN, win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_XBUTTONDOWN,
		win32.WM_LBUTTONDBLCLK, win32.WM_RBUTTONDBLCLK, win32.WM_MBUTTONDBLCLK, win32.WM_XBUTTONDBLCLK:
			mb.state = .Clicked
		case:
			mb.state = .Released
		}

		switch msg {
		case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP, win32.WM_LBUTTONDBLCLK:
			mb.code = .Left
		case win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_RBUTTONDBLCLK:
			mb.code = .Right
		case win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP, win32.WM_MBUTTONDBLCLK:
			mb.code = .Middle
		case win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP, win32.WM_XBUTTONDBLCLK:
			mb.code = .X1 if win32.GET_XBUTTON_WPARAM(wparam) == win32.XBUTTON1 else .X2
		}

		switch msg {
		case win32.WM_LBUTTONDBLCLK, win32.WM_RBUTTONDBLCLK, win32.WM_MBUTTONDBLCLK, win32.WM_XBUTTONDBLCLK:
			mb.state = .Clicked
		}

		_mouse_register_button(mb)
	case win32.WM_MOUSEMOVE:
		if .Cursor_Inside not_in window.state {
			window.state += {.Cursor_Inside}
			tme: win32.TRACKMOUSEEVENT = {
				cbSize = size_of(win32.TRACKMOUSEEVENT),
				dwFlags = win32.TME_LEAVE,
				hwndTrack = winid,
			}
			win32.TrackMouseEvent(&tme)
		}

		pos := transmute([2]i16)cast(i32)lparam
		if .Cursor_Relative not_in window.state {
			sync.atomic_store(cast(^i32)&window.mouse_pos, transmute(i32)pos)
			break
		}

		// Relative cursor handling
		if pos != window.mouse_pos {
			// Move cursor back
			pt: win32.POINT = {i32(window.mouse_pos.x), i32(window.mouse_pos.y)}
			win32.ClientToScreen(winid, &pt)
			win32.SetCursorPos(pt.x, pt.y)
			_mouse_register_relative_pos(pos - window.mouse_pos)
		}
	case win32.WM_MOUSELEAVE:
		window.state -= {.Cursor_Inside}
	case win32.WM_MOUSEWHEEL, win32.WM_MOUSEHWHEEL:
		delta := f32(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / 120
		_mouse_register_wheel(delta)
	case win32.WM_PAINT:
		winrect: win32.RECT = ---
		if win32.GetUpdateRect(winid, &winrect, false) {
			win32.ValidateRect(winid, nil)
		}
	case win32.WM_ERASEBKGND:
		return 1
	case win32.WM_CLOSE:
		if .Close_Disabled in window.state {
			return 0
		}

		window.state += {.Closed}
		// NOTE: Let main thread do the cleanup, it will return the fiber once it calls _destroy_window
		win32.SwitchToFiber(window.main_fiber)
	case:
		// context = runtime.default_context()
		// fmt.printf("unknown message: {:x}\n", msg)
	}

	return win32.DefWindowProcW(winid, msg, wparam, lparam)
}

_get_monitor_info :: proc "contextless" (winid: win32.HWND) -> (size: [2]u32, refresh_rate: u32) {
	monitor_handle := win32.MonitorFromWindow(winid, .MONITOR_DEFAULTTONEAREST)

	minfo: win32.MONITORINFOEXW
	minfo.cbSize = size_of(win32.MONITORINFOEXW)
	win32.GetMonitorInfoW(monitor_handle, &minfo)

	dev_mode: win32.DEVMODEW
	dev_mode.dmSize = size_of(win32.DEVMODEW)
	win32.EnumDisplaySettingsW(raw_data(&minfo.szDevice), win32.ENUM_CURRENT_SETTINGS, &dev_mode)

	size = {dev_mode.dmPelsWidth, dev_mode.dmPelsHeight}
	refresh_rate = dev_mode.dmDisplayFrequency

	return size, refresh_rate
}


_maximize :: proc() {
	win32.ShowWindow(window.id, win32.SW_MAXIMIZE)
}

_minimize :: proc() {
	win32.ShowWindow(window.id, win32.SW_MINIMIZE)
}

_restore :: proc() {
	win32.ShowWindow(window.id, win32.SW_RESTORE)
}
