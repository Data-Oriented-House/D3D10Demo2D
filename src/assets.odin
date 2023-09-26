package main

import "core:log"
import "core:fmt"
import "core:slice"
import "core:image"
import "core:bytes"
import "core:reflect"
import "core:container/lru"
import sar "core:container/small_array"

import ma "vendor:miniaudio"
import d3d "vendor:directx/d3d11"

import "lib:spall"
import packer "lib:data_packer"

Glyph_Asset :: struct {
	codepoint: rune,
	pixels: []image.RGBA_Pixel,
	size: [2]u32,
	y_offset: uint,
}

Sprite_Asset :: struct {
	name: string,
	pixels: []image.RGBA_Pixel,
	size: [2]u32,
}

Sound_Asset :: struct {
	name: cstring,
	data: []byte,
}

Assets :: struct {
	default_font: []Glyph_Asset,
	sprites: []Sprite_Asset,
	sounds: []Sound_Asset,
}

ASSETS :: #load("../res/assets.pack")

Shader_Asset :: struct {
	name: string,
	topology: d3d.PRIMITIVE_TOPOLOGY,
	vso, pso: []byte,
}

when ODIN_DEBUG {
	SHADERS :: #load("../res/shaders_debug.pack")
} else {
	SHADERS :: #load("../res/shaders_release.pack")
}

preload_assets :: proc() {
	assets := packer.map_root(ASSETS, Assets)

	{
		spall.scoped("Loading font info")

		// Default font
		font: Font = {
			sdf = false,
			glyphs = make(map[rune]Glyph_Info, allocator = heap_allocator),
		}
		for glyph in assets.default_font {
			glyph := packer.unpack_value(ASSETS, glyph)

			too_big := glyph.size[0] > MAX_SPRITE_SIZE || glyph.size[1] > MAX_SPRITE_SIZE
			assert(!too_big, fmt.tprintf("Glyph {0} is too big. Expected <= {1}x{1}, got {2}x{3}", glyph.codepoint, MAX_GLYPH_SIZE, glyph.size[0], glyph.size[1]))

			font.glyphs[glyph.codepoint] = {
				pixels = glyph.pixels,
				size = glyph.size,
				y_offset = glyph.y_offset,
			}
		}
		fonts[.Default] = font
	}

	{
		spall.scoped("Loading sprite info")

		for sprite in assets.sprites {
			sprite := packer.unpack_value(ASSETS, sprite)

			too_big := sprite.size[0] > MAX_SPRITE_SIZE || sprite.size[1] > MAX_SPRITE_SIZE
			assert(!too_big, fmt.tprintf("Sprite {0} is too big. Expected <= {1}x{1}, got {2}x{3}", sprite.name, MAX_SPRITE_SIZE, sprite.size[0], sprite.size[1]))

			id, ok := reflect.enum_from_name(Sprites, sprite.name)
			assert(ok, fmt.tprint("Sprite", sprite.name, "not found in Sprites"))

			sprites[id] = {
				pixels = sprite.pixels,
				size = sprite.size,
			}
		}
	}

	// Sounds
	resource_manager_config := ma.resource_manager_config_init()
	assert(ma.resource_manager_init(&resource_manager_config, &sounds.resource_manager) == .SUCCESS, "Failed to load miniaudio resource manager")

	{
		spall.scoped("Loading sound info")

		for sound in assets.sounds {
			sound := packer.unpack_value(ASSETS, sound)

			res := ma.resource_manager_register_encoded_data(&sounds.resource_manager, sound.name, raw_data(sound.data), len(sound.data))
			assert(res == .SUCCESS, fmt.tprint("Failed to register sound:", sound.name))

			id, ok := reflect.enum_from_name(Sounds, string(sound.name))
			assert(ok, fmt.tprint("Sound", sound.name, "not found in Sounds"))

			sounds.info[id] = {
				name = sound.name,
				data = sound.data,
			}
		}

		engine_config := ma.engine_config_init()
		engine_config.pResourceManager = &sounds.resource_manager
		ma.engine_init(&engine_config, &sounds.engine)

		for &info in sounds.info {
			res := ma.sound_init_from_file(&sounds.engine, info.name, auto_cast ma.sound_flags. DECODE, nil, nil, &info.sound)
			assert(res == .SUCCESS, fmt.tprint("Failed to init sound:", info.name))
		}
	}
}

unload_assets :: proc() {
	for &info in sounds.info {
		ma.sound_uninit(&info.sound)
	}
	ma.engine_uninit(&sounds.engine)
	ma.resource_manager_uninit(&sounds.resource_manager)
}

preload_assets_gpu :: proc() {
	lru.init(&glyph_cache, GLYPH_CACHE_SIZE)
	glyph_cache.on_remove = _glyph_cache_on_remove
	glyph_atlas_init()
	texture_array_init(&sprites_textures)

	// Get sprite positions in the texture array
	// NOTE: I need 2 loops because when texture array grows it clears all textures
	for &sprite in sprites {
		// NOTE: sprite.size was preloaded on the CPU
		sprite.bitmap = texture_array_push(&sprites_textures, sprite.size)
	}
	// log.info("Made", sar.len(sprites_textures.atlases), "textures of size", SPRITE_ATLAS_SIZE, "for sprites")

	for sprite in sprites {
		d3d_texture_blit(sprites_textures.textures, sprite.bitmap, sprite.pixels)
	}
}

unload_assets_gpu :: proc() {
	texture_array_finish(&sprites_textures)
	glyph_atlas_finish()
	lru.destroy(&glyph_cache, true)
}
