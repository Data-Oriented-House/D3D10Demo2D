package msgbox

Message_Box_Flags :: enum {
	Error,
	Warning,
	Info,
	OkCancel,
}

Message_Box_Result :: enum {
	None,
	Ok,
	Cancel,
}

show :: #force_inline proc(type: Message_Box_Flags, title, message: string, window: uintptr = 0) -> Message_Box_Result {
	return _show(type, title, message, window)
}
