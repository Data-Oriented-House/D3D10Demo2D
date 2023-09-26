package main

import "core:log"
import "core:fmt"
import "core:time"
import "core:sync"
import "core:mem"
import "core:math"
import "core:bytes"
import "core:reflect"
import "core:thread"
import "core:math/bits"
import "core:image"
import sar "core:container/small_array"

import "vendor:directx/dxgi"
import d3d "vendor:directx/d3d11"

import "lib:app"
import "lib:spall"
import "lib:cargo"
import "lib:atlas_packer"
import packer "lib:data_packer"

D3D10_REQ_TEXTURE2D_U_OR_V_DIMENSION :: 8192

SF32 :: [2]f32

Graphics_Settings :: enum {
	Smoothing,
	Graph,
}
DEFAULT_GRAPHICS_SETTINGS :: bit_set[Graphics_Settings]{.Smoothing, .Graph}

// Bitmap is a subtexture in a larger GPU texture
Bitmap :: struct {
	slot: u32,
	pos: [2]u32,
	size: [2]u32,
}

Texture_Antialias :: enum u8 {
	Linear,
	Crisp,
	Smooth,
}


Shaders :: enum {
	Shapes,
	Font,
}

shaders_input: [Shaders]typeid = {
	.Shapes = Shapes_Input,
	.Font = Font_Input,
}

Shape_Type :: enum u16 {
	Rectangle,
	Circle,
	Line,
}

Shape_Info :: struct {
	type: Shape_Type,
	textured: b16,
}

Shapes_Input :: struct {
	info: Shape_Info `INFO`,
	softness: f32 `SOFT`,
	coord: [2][2]f32 `COORD`,
	color: image.RGBA_Pixel `COL`,
	corner_radius: f32 `RAD`,

	// For untextured shapes
	outline_size: f32 `OUTLINE`,
	// For textured shapes
	anti_aliasing: u32 `AA`,
	tex_slot: u32 `TEX_SLOT`,
	tex_pos: [2]u32 `TEX_POS`,
	tex_size: [2]u32 `TEX_SIZE`,
}

Font_Input :: struct {
	pos: [2]f32 `POS`,
	scale: f32 `SCALE`,
	color: image.RGBA_Pixel `COL`,
	sdf: b32 `SDF`,
	bmp_pos: [2]u32 `BMP_POS`,
	bmp_size: [2]u32 `BMP_SIZE`,
}

// Common shader constant buffer
Common_Constants :: struct {
	framebuffer_size: [2]u32,
}


Draw_Command_Glyph :: struct {
	pos: [2]f32,
	scale: f32,
	color: image.RGBA_Pixel,

	glyph: Glyph,
}

Draw_Command_Sprite :: struct {
	pos: [2]SF32,
	size: [2]SF32,
	color: image.RGBA_Pixel,

	sprite: Sprites,
	anti_alias: Texture_Antialias,
}

Draw_Command_Rectangle :: struct {
	pos: [2]SF32,
	size: [2]SF32,
	color: image.RGBA_Pixel,

	corner_radius: f32,
	outline: f32,
}

Draw_Command_Circle :: struct {
	pos: [2]SF32,
	radius: SF32,
	color: image.RGBA_Pixel,

	outline: f32,
}

Draw_Command_Line :: struct {
	points: [2][2]f32,
	color: image.RGBA_Pixel,

	thickness: f32,
}

Draw_Command :: union {
	Draw_Command_Sprite,
	Draw_Command_Rectangle,
	Draw_Command_Circle,
	Draw_Command_Line,
	Draw_Command_Glyph,
}

Graphics_Input :: struct {
	tick: time.Tick,
	settings: bit_set[Graphics_Settings],
	mouse_pos: [2]SF32,
	commands: [dynamic]Draw_Command,
}


Graphics_Context :: struct {
	using frame: app.Frame_Context,
	input: Triple_Buffer(Graphics_Input),

	// Default simple pipeline state
	pipeline_state: Pipeline_State,

	// Timing
	gpu_timer: D3DTimer,

	// Shaders
	shaders: [Shaders]D3DShader,
	current_shader: Shaders,
	font_input_buf: Input_Buffer(Font_Input),
	shapes_input_buf: Input_Buffer(Shapes_Input),
	common_constants_buf: Constant_Buffer(Common_Constants),

	// Textures
	sprite_textures_view: ^d3d.IShaderResourceView,
	font_textures_view: ^d3d.IShaderResourceView,
}
graphics: Graphics_Context

get_frame_delta :: proc(simulation_tick, frame_tick: time.Tick) -> f32 {
	SIMULATION_TICK :: (time.Second / SIMULATION_TICK_RATE) * time.Nanosecond

	frame_diff := time.tick_diff(simulation_tick, frame_tick)
	frame_delta := f32(frame_diff) / cast(f32)SIMULATION_TICK
	return clamp(frame_delta, 0, 1)
}

graphics_frame :: proc() {
	spall.scoped("graphics frame")

	// Fetch draw commands
	triple_buffer_fetch(&graphics.input)
	frame_delta := get_frame_delta(graphics.input.front_buffer.tick, time.tick_now())

	frame_begin()

	// TODO: per-shape softness?
	softness: f32 = 1 if .Smoothing in graphics.input.front_buffer.settings else 0

	// Draw things from the simulation
	for command in graphics.input.front_buffer.commands {
		switch cmd in command {
		case Draw_Command_Sprite:
			lerp_pos := interpolate_smooth_position(cmd.pos, frame_delta)
			lerp_size := interpolate_smooth_position(cmd.size, frame_delta)
			draw_shape_rectangle_textured(
				softness = softness,
				pos = lerp_pos,
				size = lerp_size,
				color = cmd.color,
				anti_alias = cmd.anti_alias,
				bitmap = sprites[cmd.sprite].bitmap,
			)
		case Draw_Command_Rectangle:
			lerp_pos := interpolate_smooth_position(cmd.pos, frame_delta)
			lerp_size := interpolate_smooth_position(cmd.size, frame_delta)
			draw_shape_rectangle_untextured(
				softness = softness,
				pos = lerp_pos,
				size = lerp_size,
				color = cmd.color,
				corner_radius = cmd.corner_radius,
				outline = cmd.outline,
			)
		case Draw_Command_Circle:
			lerp_pos := interpolate_smooth_position(cmd.pos, frame_delta)
			lerp_radius := interpolate_sf32(cmd.radius, frame_delta)
			draw_shape_circle(
				softness = softness,
				pos = lerp_pos,
				radius = lerp_radius,
				color = cmd.color,
				outline = cmd.outline,
			)
		case Draw_Command_Line:
			// TODO: interpolate points, but also supply points that can be interpolated
			// First, graph needs to be made with limited number of points
			draw_shape_line(softness, cmd.points, cmd.color, cmd.thickness)
		case Draw_Command_Glyph:
			// TODO: interpolate position and scale

			bitmap, ok := glyph_atlas.glyph_map[cmd.glyph]
			if !ok { // if not in the glyph atlas, add it
				if !glyph_atlas_try_add(cmd.glyph) { // if can't fit, clear the atlas and try again
					frame_draw()
					glyph_atlas_clear()
					assert(glyph_atlas_try_add(cmd.glyph))
				}
				bitmap, ok = glyph_atlas.glyph_map[cmd.glyph]
				assert(ok)
			}

			input: Font_Input
			set_shader(.Font)

			input.pos = cmd.pos
			input.scale = cmd.scale
			input.color = cmd.color
			input.sdf = cast(b32)fonts[cmd.glyph.font].sdf
			input.bmp_pos = bitmap.pos
			input.bmp_size = bitmap.size

			input_buffer_push(&graphics.font_input_buf, input)
		}
	}

	if app.is_cursor_hidden() { // Mouse pointer (from the simulation)
		mouse_pos_smooth := graphics.input.front_buffer.mouse_pos
		mouse_lerp_pos := interpolate_smooth_position(mouse_pos_smooth, frame_delta)

		points: [2][2]f32
		points.x = {400, 300}
		points.y = mouse_lerp_pos
		draw_shape_line(softness, points, {0, 0, 0xff, 0xff}, 5)

		// Inside
		draw_shape_circle(
			softness = softness,
			pos = mouse_lerp_pos,
			radius = 3,
			color = {0xff, 0xff, 0xff, 0xff},
			outline = 2.5,
		)
		// Outside
		draw_shape_circle(
			softness = softness,
			pos = mouse_lerp_pos,
			radius = 4,
			color = {0, 0, 0, 0xff},
			outline = 1,
		)
	}

	frame_end()
}

graphics_init :: proc() {
	spall.thread_init()

	spall.scoped("Setting up graphics thread buffers")

	triple_buffer_init(&graphics.input)
	for &buf in graphics.input.buffers {
		buf.commands = make([dynamic]Draw_Command, heap_allocator)
		buf.settings = DEFAULT_GRAPHICS_SETTINGS
	}

	{ // NOTE: Use default OS allocator instead of potential arena/tracking
		context.allocator = heap_allocator
		thread.run(simulation_thread, priority = .High)
	}
	sync.park(&common.simulation_started)

	gpu_timer_init(&graphics.gpu_timer)
	load_shaders()
	preload_assets_gpu()
}

graphics_finish :: proc() {
	unload_assets_gpu()
	spall.thread_finish()
	cargo.deliver_and_wait(&common.simulation_quit)
}

load_shaders :: proc() {
	// This pipeline configuration will be used for all shaders
	graphics.pipeline_state = pipeline_make(
		depth = .Disabled,
		stencil = .Disabled,
		blending = .Alpha_Premultiply,
		face_culling = .Disabled,
		texture_filter = .Linear,
		texture_wrapping = .Clamp,
	)

	// Load shaders
	{
		shaders_asset := packer.map_root(SHADERS, []Shader_Asset)
		for sa in shaders_asset {
			sa := packer.unpack_value(SHADERS, sa)

			id, ok := reflect.enum_from_name(Shaders, sa.name)
			assert(ok, fmt.tprint("Shader", sa.name, "not found in Shaders"))

			shader_load(
				shader = &graphics.shaders[id],
				topology = sa.topology,
				vertex_data = sa.vso,
				pixel_data = sa.pso,
				input_type = shaders_input[id],
			)
		}
	}

	// Setup buffers
	constant_buffer_init(&graphics.common_constants_buf)

	block_size: uint = 1000 // 50_000 ~= 2.4 MB
	// log.info(instance_type, f32(cast(u32)reflect.size_of_typeid(instance_type) * block_size) / f32(mem.Megabyte), "MB/Block")
	input_buffer_init(&graphics.shapes_input_buf, block_size)
	// NOTE: Same size
	input_buffer_init(&graphics.font_input_buf, block_size)
}

frame_begin :: proc() {
	graphics.device_context->OMSetRenderTargets(1, &graphics.rt_view, nil)
	gpu_timer_frame_begin(&graphics.gpu_timer)
	pipeline_set(graphics.pipeline_state)
	graphics.device_context->ClearRenderTargetView(graphics.rt_view, &{0.2, 0.2, 0.2, 1})
}

frame_end :: proc() {
	// Draw what is left
	frame_draw()

	// Collect measurements
	gpu_timer_frame_end(&graphics.gpu_timer)
	if work_time, ok := gpu_timer_collect(&graphics.gpu_timer); ok {
		register_frametime(work_time)
	}

	@static frame_tick: time.Tick
	framerate := cast(i64)(cast(f64)time.Second / cast(f64)time.tick_since(frame_tick)) * cast(i64)time.Nanosecond
	frame_tick = time.tick_now()

	atomic_type_save(&common.framerate, framerate)
}

frame_draw :: proc() {
	current_shader := &graphics.shaders[graphics.current_shader]
	shader_bind(current_shader)

	constant_buffer_update(&graphics.common_constants_buf, &Common_Constants{
		framebuffer_size = graphics.frame.size,
	})
	constant_buffer_bind(&graphics.common_constants_buf)

	switch graphics.current_shader {
	case .Shapes:
		input_buffer_bind(&graphics.shapes_input_buf)
		graphics.device_context->PSSetShaderResources(0, 1, &sprites_textures.textures)
		graphics.device_context->DrawInstanced(4, u32(graphics.shapes_input_buf.len), 0, 0)
		input_buffer_clear(&graphics.shapes_input_buf)
	case .Font:
		input_buffer_bind(&graphics.font_input_buf)
		graphics.device_context->PSSetShaderResources(0, 1, &glyph_atlas.texture)
		graphics.device_context->DrawInstanced(4, u32(graphics.font_input_buf.len), 0, 0)
		input_buffer_clear(&graphics.font_input_buf)
	}
}

set_shader :: proc(shader: Shaders) {
	if shader != graphics.current_shader {
		frame_draw()
	}
	graphics.current_shader = shader
}

interpolate_sf32 :: proc(sf: SF32, frame_delta: f32) -> (interp: f32) {
	diff := sf[1] - sf[0]
	delta := diff * frame_delta
	interp = sf[0] + delta
	return
}

interpolate_smooth_position :: proc(pos: [2]SF32, frame_delta: f32) -> (interp_pos: [2]f32) {
	interp_pos.x = interpolate_sf32(pos.x, frame_delta)
	interp_pos.y = interpolate_sf32(pos.y, frame_delta)
	return
}

draw_shape_rectangle_textured :: proc(
	softness: f32,
	pos, size: [2]f32,
	color: image.RGBA_Pixel,
	anti_alias: Texture_Antialias,
	bitmap: Bitmap,
) {
	set_shader(.Shapes)
	input: Shapes_Input

	input.info = {type = .Rectangle, textured = true}
	input.softness = softness
	input.coord = {pos, size}
	input.color = color
	input.corner_radius = 0

	input.anti_aliasing = cast(u32)anti_alias
	input.tex_slot = bitmap.slot
	input.tex_pos = bitmap.pos
	input.tex_size = bitmap.size

	input_buffer_push(&graphics.shapes_input_buf, input)
}

draw_shape_rectangle_untextured :: proc(
	softness: f32,
	pos, size: [2]f32,
	color: image.RGBA_Pixel,
	corner_radius: f32,
	outline: f32,
) {
	set_shader(.Shapes)
	input: Shapes_Input

	input.info = {type = .Rectangle, textured = false}
	input.softness = softness
	input.coord = {pos, size}
	input.color = color
	input.corner_radius = corner_radius
	input.outline_size = outline

	input_buffer_push(&graphics.shapes_input_buf, input)
}

draw_shape_circle :: proc(
	softness: f32,
	pos: [2]f32,
	radius: f32,
	color: image.RGBA_Pixel,
	outline: f32,
) {
	set_shader(.Shapes)
	input: Shapes_Input

	input.info = {type = .Circle, textured = false}
	input.softness = softness
	input.coord = {pos, {radius, 0}}
	input.color = color
	input.outline_size = outline

	input_buffer_push(&graphics.shapes_input_buf, input)
}

draw_shape_line :: proc(
	softness: f32,
	points: [2][2]f32,
	color: image.RGBA_Pixel,
	thickness: f32,
) {
	set_shader(.Shapes)
	input: Shapes_Input

	input.info = {type = .Line, textured = false}
	input.softness = softness
	input.coord = points
	input.color = color
	input.outline_size = thickness

	input_buffer_push(&graphics.shapes_input_buf, input)
}


// Make texture on the GPU from desciption
d3d_texture_make :: proc(texture_desc: ^d3d.TEXTURE2D_DESC) -> ^d3d.IShaderResourceView {
	texture: ^d3d.ITexture2D
	graphics.device->CreateTexture2D(texture_desc, nil, &texture)
	defer texture->Release()

	texture_view: ^d3d.IShaderResourceView
	graphics.device->CreateShaderResourceView(texture, nil, &texture_view)
	return texture_view
}

// Get texture handle from its view
d3d_texture_from_view :: proc(texture_view: ^d3d.IShaderResourceView) -> ^d3d.ITexture2D {
	resource: ^d3d.IResource
	texture_view->GetResource(&resource)
	defer resource->Release()

	texture: ^d3d.ITexture2D
	resource->QueryInterface(d3d.ITexture2D_UUID, cast(^rawptr)&texture)
	return texture
}

// Get texture description from its view
d3d_texture_get_desc :: proc(texture_view: ^d3d.IShaderResourceView) -> d3d.TEXTURE2D_DESC {
	texture := d3d_texture_from_view(texture_view)
	defer texture->Release()

	texture_desc: d3d.TEXTURE2D_DESC
	texture->GetDesc(&texture_desc)
	return texture_desc
}

// Blits pixels into GPU texture
d3d_texture_blit :: proc(texture_view: ^d3d.IShaderResourceView, bitmap: Bitmap, pixels: []image.RGBA_Pixel) {
	box: d3d.BOX = {
		left = bitmap.pos.x,
		right = bitmap.pos.x + bitmap.size[0],
		top = bitmap.pos.y,
		bottom = bitmap.pos.y + bitmap.size[1],
		front = 0, // Beginning depth level.
		back = 1, // Ending depth level.
	}
	pitch := size_of(image.RGBA_Pixel) * bitmap.size[0]

	texture := d3d_texture_from_view(texture_view)
	texture_slot := d3d.CalcSubresource(MipSlice = 0, ArraySlice = bitmap.slot, MipLevels = 1)
	graphics.device_context->UpdateSubresource(texture, texture_slot, &box, raw_data(pixels), pitch, 0)
	texture->Release()
}

// TODO: check if sane
/*
HRESULT GetRefreshRate(IDXGISwapChain* swapChain, double* outRefreshRate)
{
       ComPtr<IDXGIOutput> dxgiOutput;
       HRESULT hr = graphics.swapChain->GetContainingOutput(&dxgiOutput);
       // if swap chain get failed to get DXGIoutput then follow the below link get the details from remarks section
       //https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-getcontainingoutput
       if (SUCCEEDED(hr))
       {

          ComPtr<IDXGIOutput1> dxgiOutput1;
          hr = dxgiOutput.As(&dxgiOutput1);
          if (SUCCEEDED(hr))
          {
                 // get the descriptor for current output
                 // from which associated mornitor will be fetched
                 DXGI_OUTPUT_DESC outputDes{};
                 hr = dxgiOutput->GetDesc(&outputDes);
                 if (SUCCEEDED(hr))
                 {

                        MONITORINFOEXW info;
                        info.cbSize = sizeof(info);
                        // get the associated monitor info
                        if (GetMonitorInfoW(outputDes.Monitor, &info) != 0)
                        {
                               // using the CCD get the associated path and display configuration
                               UINT32 requiredPaths, requiredModes;
                               if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &requiredPaths, &requiredModes) == ERROR_SUCCESS)
                               {
                                      std::vector<DISPLAYCONFIG_PATH_INFO> paths(requiredPaths);
                                      std::vector<DISPLAYCONFIG_MODE_INFO> modes2(requiredModes);
                                      if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &requiredPaths, paths.data(), &requiredModes, modes2.data(), nullptr) == ERROR_SUCCESS)
                                      {
                                             // iterate through all the paths until find the exact source to match
                                             for (auto& p : paths) {
                                                    DISPLAYCONFIG_SOURCE_DEVICE_NAME sourceName;
                                                    sourceName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
                                                    sourceName.header.size = sizeof(sourceName);
                                                    sourceName.header.adapterId = p.sourceInfo.adapterId;
                                                    sourceName.header.id = p.sourceInfo.id;
                                                    if (DisplayConfigGetDeviceInfo(&sourceName.header) == ERROR_SUCCESS)
                                                    {
                                                           // find the matched device which is associated with current device
                                                           // there may be the possibility that display may be duplicated and windows may be one of them in such scenario
                                                           // there may be two callback because source is same target will be different
                                                           // as window is on both the display so either selecting either one is ok
                                                           if (wcscmp(info.szDevice, sourceName.viewGdiDeviceName) == 0) {
                                                                  // get the refresh rate
                                                                  UINT numerator = p.targetInfo.refreshRate.Numerator;
                                                                  UINT denominator = p.targetInfo.refreshRate.Denominator;
                                                                  double refrate = (double)numerator / (double)denominator;
                                                                  *outRefreshRate = refrate;
                                                                  break;
                                                           }
                                                    }
                                             }
                                      }
                                      else
                                      {
                                             hr = E_FAIL;
                                      }
                               }
                               else
                               {
                                      hr = E_FAIL;
                               }
                        }
                 }
          }
   }
   return hr;
}
*/
