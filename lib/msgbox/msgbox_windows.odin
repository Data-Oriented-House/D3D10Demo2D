package msgbox

import win32 "core:sys/windows"

_show :: proc(type: Message_Box_Flags, title, message: string, window: uintptr) -> Message_Box_Result {
	winid: win32.HWND
	if window != 0 {
		winid = auto_cast window
	}

	utype: win32.UINT = win32.MB_TOPMOST
	switch type {
	case .Error:
		utype |= win32.MB_ICONERROR
	case .Warning:
		utype |= win32.MB_ICONWARNING
	case .Info:
		utype |= win32.MB_ICONINFORMATION
	case .OkCancel:
		utype |= win32.MB_OKCANCEL
	}

	switch win32.MessageBoxW(winid, win32.utf8_to_wstring(message), win32.utf8_to_wstring(title), utype) {
	case win32.IDOK:
		return .Ok
	case win32.IDCANCEL:
		return .Cancel
	case:
		return .None
	}
}
