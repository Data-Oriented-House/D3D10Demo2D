package timer

import "core:time"

import win32 "core:sys/windows"

foreign import ntdll_lib "system:ntdll.lib"

@(default_calling_convention="stdcall")
foreign ntdll_lib {
	NtQueryTimerResolution :: proc(MinimumResolution, MaximumResolution, CurrentResolution: win32.PULONG) -> win32.NTSTATUS ---
	NtSetTimerResolution :: proc(DesiredResolution: win32.ULONG, SetResolution: win32.BOOLEAN, CurrentResolution: win32.PULONG) -> win32.NTSTATUS ---
}

_set_resolution :: proc(res: time.Duration) {
	resolution_100ns := time.duration_nanoseconds(res) / 100
	old_resolution: u32
	NtSetTimerResolution(u32(resolution_100ns), true, &old_resolution)
}
