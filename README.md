# D3D10 2D Demo

This is a demo of a simple library-engine (lib/app) for quick platform-layer setup to draw D3D,
as well as some other cool techniques I have discovered.

## lib/app

Emphasis is put on simplicity of the scope of library, not on simplicity of getting things drawn on the screen.
The library prepares all the D3D device/swapchain nonsense for you, but you still have to use D3D to draw anything.

There is a single iterator function to both init the program, and to continually run it.

Here is the simplest possible loop that opens an interactive window:
```odin
for frame in app.run("window_id") {}
```

Here is a more complicated exampled to showcase how you would initialize your own things (using `sync.Once`),
and how you would detinitialize them (by checking `frame.will_quit`):
```odin
graphics: My_Global_Graphics_Context

for frame in app.run("window_id", "Window title", .Centered, {600, 600}) {
	defer free_all(context.temp_allocator)

	// Saved globally for use in another function
	graphics.frame = frame

	@static init_once: sync.Once
	sync.once_do(&init_once, graphics_init)

	graphics_frame()

	if frame.will_quit {
		graphics_finish()
		continue
	}
}
```

To get input state you would do this in a loop (on any thread, not necessarily the graphics one):
```odin
keyboard := app.keyboard_get_state()
mouse := app.mouse_get_state()

// You can iterate over key events in order
for key in app.keyboard_keys_iterate(&keyboard) {
	switch key {
	case {.Q, .Pressed}:
		app.close()
	case {.A, .Released}, {.A, .Repeated}:
		fmt.println("A released or repeated")
	}
}

// Or over characters typed (also in order)
for char in app.keyboard_characters_iterate(&keyboard) {
	fmt.println(char)
}

// You can also check if key is being pressed this frame (not ordered, obviously)
if keyboard.pressed[.Space] {
	fmt.println("Space is being held")
}

// Similarly with the mouse
for button in app.mouse_buttons_iterate(&mouse) {
	if button == {.Right, .Clicked} {
		fmt.println("RMB clicked")
	}
}

if mouse.pressed[.Left] {
	fmt.println("LMB is being held at", mouse.pos)
}

// There is also a relative mouse mode, especially useful for 3D POV games, switch to it with set_cursor_relative()
if mouse.relative_pos != 0 {
	fmt.println("mouse moved by", mouse.relative_pos)
}

// There are also a couple of useful procedures that you may commonly want (completely thread-safe)
// In the graphics thread you have to use `frame.size`, but for code in other threads (e.g. simulation) you can get it like this
framebuffer_size := app.get_framebuffer_size()
// And if you process inputs not on the graphics thread, then you can get mouse position on the graphics thread like this
mouse_pos := app.get_mouse_pos()
```

The rest of the API you can find in `lib/app/app.odin`, procedures such as `close/_enable/_disable`,
`get_monitor_refresh_rate`, `toggle_fullscreen`,  `is_focused`, etc.

## lib/data_packer

Data packer/unpacker that has 0 memory overhead (for unpacking) by using relative pointers and mapping.
More documentation can be found in its source code.

I use it to pack all the assets, as well as shaders, this way I can embed only a couple of files with `#load("assets.pack")`,
and then unpack the resources when I need them. Unpacking is very fast, since it just maps pointers.

## lib/atlas_packer

A simple packer of rectangles into a texture, got the code from a famous lightmap packing article.

## lib/msgbox

Simple message box to show in case of an error.

## lib/spall

Simple wrapper around `core:prof/spall`

## lib/stacktrace

Simple wrapper around [pdb](https://github.com/DaseinPhaos/pdb)

## lib/timer

Simple precise timer for use in fixed step simulations and things like that

## src

Demo 2D program that simulates and draws a bunch of simple stuff.
One notable technique I use is separation of simulation and graphics into different threads,
and then interpolation of the state in the graphics thread.
This way the 2 code cycles run completely independantly of one another,
with minimal synchronization by using a triple-buffer.

For single-player games you probably want to limit the simulation rate if framerate is too low,
for this you can modify the triple buffer to keep track of pushed simulation states,
which graphics thread would set to 0 once it receives the state;
and when the number of simulation states goes over a certain treshhold (e.g. 40-50ms, so 3-4 states),
you can just skip the simulation tick until the graphics thread catches up.

Also note that even through simulation runs at 64 ticks per second, this method of interpolation works so well,
that even on a 360Hz monitor it would be hard to notice the input lag, at least of the mouse;
what happens with 3D POV I don't know, maybe it would be too noticable, requiring to up the tickrate to 128.

Font glyphs are being cached (LRU) on the CPU on-demand, then uploaded to a single GPU atlas on-demand.
This way the requirement is fixed, only a single atlas is ever used.
If GPU atlas gets filled, texture just gets reset along with GPU cache,
but not the CPU cache (that one updates automatically since it's LRU).

Sprites use a different method, they are uploaded all at once to the GPU in the beginning,
packed into atlases (512 max) of a set size (1024 currently, but can be upto 8K).

Sound is packed into assets (and thus is stored in memory), and is unpacked in the beginning to miniaudio sound engine,
then played on demand.

Because all the assets and shaders are stored in a couple of asset files, I just embed them into the program with `#load`,
and my program becomes a single portable no-dependency executable.

## tools

Just a couple of tools that pack assets and shaders, nothing interesting.
