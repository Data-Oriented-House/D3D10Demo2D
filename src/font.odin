package main

import "core:fmt"
import "core:slice"
import "core:bytes"
import "core:image"
import "core:container/lru"

import d3d "vendor:directx/d3d11"

import "lib:atlas_packer"

// Atlas for caching font
FONT_ATLAS_SIZE :: 1024
MAX_GLYPH_SIZE :: FONT_ATLAS_SIZE - 2
GLYPH_CACHE_SIZE :: 64

Fonts :: enum {
	Default,
}

Glyph :: struct {
	font: Fonts,
	codepoint: rune,
}

Glyph_Info :: struct {
	// Every font type has these
	y_offset: uint,

	// Bitmaps have pixels and size
	pixels: []image.RGBA_Pixel,
	size: [2]u32,

	// SDFs have curve data or whatever idk
}

Font :: struct {
	sdf: bool,
	glyphs: map[rune]Glyph_Info,
}

fonts: [Fonts]Font

// Returns the input glyph, or fallback if it wasn't found
get_glyph :: proc(font: Fonts, codepoint: rune) -> Glyph {
	if _, ok := fonts[font].glyphs[codepoint]; ok {
		return {font, codepoint}
	}

	if _, ok := fonts[.Default].glyphs[codepoint]; ok {
		return {.Default, codepoint}
	}

	// NOTE: ? must exist in the default font
	return {.Default, '?'}
}


// Cache of CPU-side pre-rendered pixel buffers for glyphs
glyph_cache: lru.Cache(Glyph, []image.RGBA_Pixel)

_glyph_cache_on_remove :: proc(g: Glyph, data: []image.RGBA_Pixel, user_data: rawptr) {
	delete(data, glyph_cache.entries.allocator)
}

glyph_cache_get :: proc(g: Glyph) -> []image.RGBA_Pixel {
	if !lru.exists(&glyph_cache, g) {
		assert(!fonts[g.font].sdf, fmt.tprint("Implement SDF glyph caching for", g.font))

		glyph_info := fonts[g.font].glyphs[g.codepoint]

		{
			pixels, err := slice.clone(glyph_info.pixels, glyph_cache.entries.allocator)
			assert(err == nil)

			lru.set(&glyph_cache, g, pixels)
			return pixels
		}
	}

	return lru.get(&glyph_cache, g)
}


// GPU texture with an atlas mapping glyphs to locations in that texture
Glyph_Atlas :: struct {
	texture: ^d3d.IShaderResourceView,
	atlas: atlas_packer.Atlas,
	glyph_map: map[Glyph]Bitmap,
}

// Contains every glyph for the frame
glyph_atlas: Glyph_Atlas

glyph_atlas_init :: proc() {
	glyph_atlas.glyph_map = make(map[Glyph]Bitmap, allocator = heap_allocator)
	atlas_packer.init(&glyph_atlas.atlas, {FONT_ATLAS_SIZE, FONT_ATLAS_SIZE})

	texture_desc: d3d.TEXTURE2D_DESC = {
		Width = FONT_ATLAS_SIZE,
		Height = FONT_ATLAS_SIZE,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DEFAULT,
		BindFlags = {.SHADER_RESOURCE},
	}
	glyph_atlas.texture = d3d_texture_make(&texture_desc)
}

glyph_atlas_finish :: proc() {
	glyph_atlas.texture->Release()
	atlas_packer.destroy(&glyph_atlas.atlas)
	delete(glyph_atlas.glyph_map)
}

glyph_atlas_try_add :: proc(g: Glyph) -> bool {
	if glyph_atlas.texture == nil {
	}

	// Try inserting glyph into the atlas
	bitmap_size := fonts[g.font].glyphs[g.codepoint].size
	pos, ok := atlas_packer.try_insert(&glyph_atlas.atlas, bitmap_size + 2)
	if !ok {
		return false
	}

	// Blit glyph to the GPU texture
	pixels := glyph_cache_get(g)
	bitmap := Bitmap{slot = 0, pos = pos + 1, size = bitmap_size}
	glyph_atlas.glyph_map[g] = bitmap
	d3d_texture_blit(glyph_atlas.texture, bitmap, pixels)

	return true
}

glyph_atlas_clear :: proc() {
	texture_desc := d3d_texture_get_desc(glyph_atlas.texture)
	glyph_atlas.texture->Release()
	glyph_atlas.texture = d3d_texture_make(&texture_desc)

	atlas_packer.destroy(&glyph_atlas.atlas)
	atlas_packer.init(&glyph_atlas.atlas, {FONT_ATLAS_SIZE, FONT_ATLAS_SIZE})
}
