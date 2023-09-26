package main

import "core:log"
import "core:fmt"
import "core:math"
import "core:time"
import "core:sync"
import "core:image"
import "core:strings"
import "core:slice"

import "lib:app"
import "lib:fifo"
import "lib:spall"
import "lib:timer"
import "lib:cargo"

// NOTE: 64 is precise on Windows without needing to change timer resolution using my timing method.
// Many games change resolution to 100ns since they don't know what I know, and don't do what I do.
// It can be changed to 128 for more precise simulation; timer resolution and simulation values would need to be adjusted.
// The only reason you would want 128 is for 3d games with a 3d camera view.
SIMULATION_TICK_RATE :: 64
SIMULATION_ENTITIES_MAX :: 100_000 // 100_000 ~= 2.3 MB


Fade :: struct {
	// anim: Animation,
}

Skull :: struct {
	pos: [2]SF32,
	// anim: Animation,
}

Entity_Bunny :: struct {
	pos: [2]SF32,
	color: image.RGBA_Pixel,
}

Entity :: union {
	Entity_Bunny,
}

Simulation_Context :: struct {
	using world: struct {
		paused: bool,
		entities: [dynamic]Entity,
	},

	// Time of every simulation cycle
	// TODO: 1000 instead?
	stats: fifo.FIFO(SIMULATION_TICK_RATE, time.Duration),
	// Time of every frame
	frametimes: fifo.FIFO(100, time.Duration),
	frametimes_lock: sync.Mutex,

	graphics_settings: bit_set[Graphics_Settings],
}
simulation: Simulation_Context

simulation_thread :: proc() {
	context = setup_context()

	sync.unpark(&common.simulation_started)
	defer cargo.accept(&common.simulation_quit)

	spall.thread_init()
	defer spall.thread_finish()

	simulation.entities = make_fixed([dynamic]Entity, SIMULATION_ENTITIES_MAX, heap_allocator)
	simulation.graphics_settings = DEFAULT_GRAPHICS_SETTINGS

	app.set_cursor_hidden(true)

	// sound_play(.Reconstruction_Science)

	for !cargo.is_pending(&common.simulation_quit) {
		defer free_all(context.temp_allocator)

		spall.scoped("Update tick")
		cycle_start := time.tick_now()

		// Handle events
		keyboard := app.keyboard_get_state()
		mouse := app.mouse_get_state()

		for key in app.keyboard_keys_iterate(&keyboard) {
			switch key {
			case {.E, .Pressed}: // error
				// TODO
				// exception = "EXCEPTION!"
			case {.B, .Pressed}: // leak
				_ = new(int)
				sound_restart(.Boom)
			case {.Q, .Pressed}:
				app.close()
			case {.A, .Pressed}:
				simulation.graphics_settings ~= {.Smoothing}
			case {.F3, .Pressed}:
				simulation.graphics_settings ~= {.Graph}
			case {.C, .Pressed}:
				app.set_cursor_hidden(!app.is_cursor_hidden())
			case {.Space, .Pressed}:
				if sound_state(.Reconstruction_Science) == .Playing {
					sound_pause(.Reconstruction_Science)
				} else {
					sound_play(.Reconstruction_Science)
				}
			case {.S, .Pressed}:
				sound_stop(.Reconstruction_Science)
			}
		}
		for char in app.keyboard_characters_iterate(&keyboard) {}
		if keyboard.pressed[.Space] {}

		for button in app.mouse_buttons_iterate(&mouse) {
			if button == {.Right, .Clicked} {
				app.set_cursor_relative(true)
			}
			if button == {.Right, .Released} {
				app.set_cursor_relative(false)
			}
		}
		if mouse.pressed[.Left] {
			fmt.println(mouse.pos)
		}
		if mouse.relative_pos != 0 {
			fmt.println(mouse.relative_pos)
		}

		// Drawing

		@static old_size: [2]u32
		framebuffer_size := app.get_framebuffer_size()
		if old_size != framebuffer_size {
			// log.info(framebuffer_size)
			old_size = framebuffer_size
		}

		{ // Draw testing things
			@static skull: Skull
			@static skull_scale: f32
			MAX_SCALE :: 12
			skull_scale += 0.05
			if skull_scale > MAX_SCALE {
				skull_scale = 0
			}
			actual_skull_scale := MAX_SCALE - abs(skull_scale - MAX_SCALE/2)

			@static skull_size: [2]SF32
			skull_size.x[0] = skull_size.x[1]
			skull_size.y[0] = skull_size.y[1]
			skull_size.x[1] = cast(f32)sprites[.Skull].size.x * actual_skull_scale
			skull_size.y[1] = cast(f32)sprites[.Skull].size.y * actual_skull_scale
			if skull_size.x[0] == 0 && skull_size.y[0] == 0 {
				skull_size.x[0] = skull_size.x[1]
				skull_size.y[0] = skull_size.y[1]
			}

			skull.pos.x[0] = skull.pos.x[1]
			skull.pos.y[0] = skull.pos.y[1]
			skull.pos.x[1] = cast(f32)(framebuffer_size[0] - 10) - skull_size[0][1] + 0.5
			skull.pos.y[1] = cast(f32)(framebuffer_size[1] - 10) - skull_size[1][1] + 0.5
			if skull.pos.x[0] == 0 && skull.pos.y[0] == 0 {
				skull.pos.x[0] = skull.pos.x[1]
				skull.pos.y[0] = skull.pos.y[1]
			}

			append(&graphics.input.back_buffer.commands, Draw_Command_Sprite{
				pos = skull.pos,
				size = skull_size,
				color = {0xff, 0xff, 0xff, 0xff},

				sprite = .Skull,
				anti_alias = .Smooth,
			})

			@static wabbit: Entity_Bunny
			@static wabbit_size: [2]SF32
			wabbit_size.x[0] = wabbit_size.x[1]
			wabbit_size.y[0] = wabbit_size.y[1]
			wabbit_size.x[1] = cast(f32)sprites[.Wabbit].size.x * 4
			wabbit_size.y[1] = cast(f32)sprites[.Wabbit].size.y * 4
			if wabbit_size.x[0] == 0 && wabbit_size.y[0] == 0 {
				wabbit_size.x[0] = wabbit_size.x[1]
				wabbit_size.y[0] = wabbit_size.y[1]
			}

			wabbit.pos.x[0] = wabbit.pos.x[1]
			wabbit.pos.y[0] = wabbit.pos.y[1]
			wabbit.pos.x[1] = 10
			wabbit.pos.y[1] = cast(f32)(framebuffer_size[1] - 10) - wabbit_size[1][1]
			if wabbit.pos.x[0] == 0 && wabbit.pos.y[0] == 0 {
				wabbit.pos.x[0] = wabbit.pos.x[1]
				wabbit.pos.y[0] = wabbit.pos.y[1]
			}

			wabbit.pos.x[1] += actual_skull_scale
			append(&graphics.input.back_buffer.commands, Draw_Command_Sprite{
				pos = wabbit.pos,
				size = wabbit_size,
				color = {0xcd, 0xb8, 0x91, 0xff},

				sprite = .Wabbit,
				anti_alias = .Smooth,
			})
			append(&graphics.input.back_buffer.commands, Draw_Command_Rectangle{
				pos = {wabbit.pos.x + 120, wabbit.pos.y},
				size = wabbit_size,
				color = {0xcd, 0xb8, 0x91, 0xff},

				corner_radius = 3,
				outline = 0,
			})

			draw_text(
				font = .Default,
				text = `!'*"#%&$.,+-/\|:;<=>?[](){}^_@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdfghijklmnoprtuvwz`+
				"\n"+`The quick brown fox jumps over the lazy dog`+
				"\n"+
				"\n"+`// Here is some code`+
				"\n"+`pos, ok := atlas_packer.try_insert(&atlas, sprite.size + 2)`,
				pos = {10, 240},
				color = {0xff, 0xff, 0, 0xff},
			)
		}

		// TODO: time-based graph
		// Count FPS
		{
			refresh_rate := app.get_monitor_refresh_rate()
			last_frame_percentage: f32

			if simulation.frametimes.len > 0 {
				last_stat := simulation.frametimes.buffer[0]

				last_frame_time := time.duration_milliseconds(last_stat)
				expected_frame_time := 1000 / f32(refresh_rate)
				last_frame_percentage = f32(last_frame_time) / expected_frame_time
				// log.info(last_stat, last_frame_percentage)
			}

			// Draw FPS Graph
			if .Graph in simulation.graphics_settings  {
				PANEL_OFFSET :: 10
				PANEL_WIDTH :: 500
				PANEL_HEIGHT :: 200
				CORNER_RADIUS :: 4
				BORDER_SIZE :: 2

				append(&graphics.input.back_buffer.commands, Draw_Command_Rectangle{
					pos = PANEL_OFFSET,
					size = {PANEL_WIDTH, PANEL_HEIGHT},
					color = {0, 0, 0, 70},

					corner_radius = CORNER_RADIUS,
					outline = 0,
				})

				stats_slice := fifo.slice(&simulation.frametimes)
				GRAPH_OFFSET :: PANEL_OFFSET + BORDER_SIZE
				GRAPH_WIDTH :: PANEL_WIDTH - (BORDER_SIZE * 2)
				GRAPH_HEIGHT :: PANEL_HEIGHT - (BORDER_SIZE * 2)
				prev_pos: [2]f32
				for stat, idx in stats_slice {
					pos: [2]f32
					frame_percentage := f32(time.duration_milliseconds(stat)) / ((1000 / f32(refresh_rate / 2)))

					// Calculate X
					buffer_percent := f32(idx) / f32(len(simulation.frametimes.buffer) - 1)
					pos.x = (GRAPH_OFFSET + GRAPH_WIDTH) - (buffer_percent * GRAPH_WIDTH)

					// Calculate Y
					// Calculate line color based on Y
					line_color: image.RGBA_Pixel = {0, 0xff, 0, 0xff}
					line_color.r = u8((frame_percentage) * 255)
					line_color.g = u8(((1 - frame_percentage)) * 255)

					pos.y = (GRAPH_OFFSET + GRAPH_HEIGHT) - (frame_percentage * GRAPH_HEIGHT)
					pos.y = math.floor(pos.y)
					if pos.y < GRAPH_OFFSET {
						pos.y = GRAPH_OFFSET
						line_color.rg = {0xff, 0x00}
					}

					if idx > 0 {
						append(&graphics.input.back_buffer.commands, Draw_Command_Line{
							points = {{pos.x, pos.y}, prev_pos},
							color = line_color,
							thickness = 0.5,
						})
					}

					prev_pos = pos
				}

				// Half VSync FPS
				draw_text(
					font = .Default,
					text = fmt.tprintf("{}", refresh_rate / 2),
					pos = {GRAPH_OFFSET + 2, GRAPH_OFFSET + 2},
					color = {0xff, 0xff, 0, 0xff},
				)
				// VSync FPS
				draw_text(
					font = .Default,
					text = fmt.tprintf("{}", refresh_rate),
					pos = {GRAPH_OFFSET + 2, PANEL_OFFSET + PANEL_HEIGHT/2 + 4},
					color = {0xff, 0xff, 0, 0xff},
				)
				// Detected monitor FPS
				draw_text(
					font = .Default,
					text = fmt.tprintf("{}", atomic_type_load(&common.framerate)),
					pos = {GRAPH_OFFSET + 2, PANEL_OFFSET + GRAPH_HEIGHT - get_font_height(.Default) - 1},
					color = {0xff, 0xff, 0, 0xff},
				)
				// Percentage of time that frame took out of VSync interval
				text := fmt.tprint(simulation.frametimes.buffer[0])
				w := get_text_width(.Default, text)
				draw_text(
					font = .Default,
					text = text,
					pos = {GRAPH_OFFSET + GRAPH_WIDTH - f32(w) - 2, GRAPH_OFFSET + 2},
					color = {0xff, 0xff, 0, 0xff},
				)

				// Mid-line
				append(&graphics.input.back_buffer.commands, Draw_Command_Line{
					points = {
						{PANEL_OFFSET, PANEL_OFFSET + PANEL_HEIGHT/2},
						{PANEL_OFFSET + PANEL_WIDTH, PANEL_OFFSET + PANEL_HEIGHT/2},
					},
					color = {0xff, 0xff, 0xff, 0xff},
					thickness = 2.5,
				})
				// Border
				append(&graphics.input.back_buffer.commands, Draw_Command_Rectangle{
					pos = PANEL_OFFSET,
					size = {PANEL_WIDTH, PANEL_HEIGHT},
					color = {0xff, 0xff, 0xff, 0xff},

					corner_radius = CORNER_RADIUS,
					outline = BORDER_SIZE,
				})
			}
		}

		// game world update
		// for id, &entity in game.entities {
		// 	entity.color.r += u8(1 * id)
		// 	entity.color.g += u8(2 * id)
		// 	entity.color.b += u8(3 * id)
		// }

		// frame := (tick / 5) % ANIMATION_FRAMES
		// cell: [2]i32 = {frame % ATLAS_COLS, frame / ATLAS_COLS} // animation frame cell index in atlas grid

		// sprite: Sprite = {
		// 	size = {ATLAS_WIDTH / ATLAS_COLS, ATLAS_HEIGHT / ATLAS_ROWS},
		// }
		// sprite.screen_pos = (array_cast(i32, framebuffer_size) - sprite.size) / 2
		// sprite.atlas_pos = cell * sprite.size

		work_time := time.tick_since(cycle_start)
		fifo.push(&simulation.stats, work_time)

		{
			spall.scoped("Pushing graphics input out")

			@static old_mouse_pos: [2]f32
			mouse_pos := array_cast(f32, mouse.pos)
			if old_mouse_pos == {} {
				old_mouse_pos = mouse_pos
			}
			graphics.input.back_buffer.mouse_pos.x = {old_mouse_pos.x, mouse_pos.x}
			graphics.input.back_buffer.mouse_pos.y = {old_mouse_pos.y, mouse_pos.y}
			old_mouse_pos = mouse_pos

			graphics.input.back_buffer.tick = time.tick_now()
			graphics.input.back_buffer.settings = simulation.graphics_settings
			triple_buffer_push(&graphics.input)
			clear(&graphics.input.back_buffer.commands)
		}

		timer.wait(timer.tick_duration_from_rate(SIMULATION_TICK_RATE), cycle_start)

		// @static cycle_tick: time.Tick
		// cycle_time := time.tick_lap_time(&cycle_tick)
		// log.info("Core cycle:", cycle_time)
	}
}

get_font_height :: proc(font: Fonts) -> f32 {
	max_height: f32
	for _, info in fonts[font].glyphs {
		max_height = max(max_height, f32(info.size[1]))
	}
	return max_height
}

draw_text :: proc(font: Fonts, text: string, pos: [2]f32, color: image.RGBA_Pixel) {
	if text == "" do return

	max_height := get_font_height(font)

	text_x := pos.x
	text_y := pos.y
	text := text
	for line in strings.split_iterator(&text, "\n") {
		for ch in line {
			if font == .Default {
				if ch == ' ' {
					text_x += 3
					continue
				}
			}

			glyph := get_glyph(font, ch)
			glyph_info := fonts[glyph.font].glyphs[glyph.codepoint]
			glyph_size := array_cast(f32, glyph_info.size)

			// Bottom-align all characters
			glyph_y := text_y + max_height - glyph_size[1]
			glyph_y += f32(glyph_info.y_offset)

			// Shadow
			append(&graphics.input.back_buffer.commands, Draw_Command_Glyph{
				pos = [2]f32{text_x, glyph_y} + 1,
				scale = 1,
				color = {0, 0, 0, 0xff},
				glyph = glyph,
			})
			// Glyph
			append(&graphics.input.back_buffer.commands, Draw_Command_Glyph{
				pos = {text_x, glyph_y},
				scale = 1,
				color = color,
				glyph = glyph,
			})
			text_x += glyph_size[0]
			text_x += 1 // add space between letters
		}

		text_x = pos.x
		text_y += f32(max_height) + 2
	}
}

get_text_width :: proc(font: Fonts, text: string) -> f32 {
	if text == "" {
		return 0
	}

	text_width: f32
	text := text
	for line in strings.split_iterator(&text, "\n") {
		line_width: f32
		for ch in line {
			if font == .Default {
				if ch == ' ' {
					line_width += 3
					continue
				}
			}

			glyph := get_glyph(font, ch)
			glyph_info := fonts[glyph.font].glyphs[glyph.codepoint]
			glyph_size := array_cast(f32, glyph_info.size)
			line_width += glyph_size[0]
			line_width += 1 // add space between letters
		}
		line_width -= 1 // remove last space

		text_width = max(text_width, line_width)
	}

	return text_width
}

register_frametime :: proc(frametime: time.Duration) {
	sync.guard(&simulation.frametimes_lock)
	fifo.push(&simulation.frametimes, frametime)
}

make_fixed :: proc($T: typeid/[dynamic]$E, #any_int cap: int, allocator := context.allocator, loc := #caller_location) -> T {
	return slice.into_dynamic(make([]E, cap, allocator, loc))
}
