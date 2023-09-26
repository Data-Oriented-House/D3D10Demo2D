package main

import "core:log"
import "core:fmt"
import "core:time"
import "core:sync"

import "lib:app"
import "lib:timer"
import "lib:cargo"

APP_ID :: "D3D10Demo2D"
WINDOW_TITLE :: "D3D10Demo2D"
WINDOW_W :: 640
WINDOW_H :: 480

// Data shared between threads
Common_Context :: struct {
	// Thread synchronization
	simulation_started: sync.Parker,
	simulation_quit: cargo.Cargo,
	// Auto-detected (what the swapchain *thinks* refresh rate is)
	// When you move the window to another monitor, swapchain doesn't change swap interval (from my testing)
	framerate: Atomic_Type(i64),
}
common: Common_Context

start :: proc() {
	// NOTE: In a game with config/save files on disk, you would load them here

	when ODIN_OS == .Windows {
		// Adjust Windows scheduler to accommodate high simulation rate.
		// NOTE: Might want to set resolution to 100ns.
		// It's a bad habit that games do, but if other programs (like Chrome) set it to 8ms,
		// and my simulation requires 7.8125ms, then it will simulate at 8ms rate.
		// Benefit is significant, 0% versus 20% of my CPU
		if SIMULATION_TICK_RATE > 64 && SIMULATION_TICK_RATE < 200 {
			timer._set_resolution((time.Second / SIMULATION_TICK_RATE) * time.Nanosecond)
		}
	}

	preload_assets()
	defer unload_assets()

	for frame in app.run(APP_ID, WINDOW_TITLE, .Centered, {WINDOW_W, WINDOW_H}) {
		defer free_all(context.temp_allocator)
		graphics.frame = frame

		@static init_once: sync.Once
		sync.once_do(&init_once, graphics_init)

		graphics_frame()

		if frame.will_quit {
			graphics_finish()
			continue
		}
	}
}
