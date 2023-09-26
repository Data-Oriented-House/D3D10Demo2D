package main

import "core:image"

// NOTE: 1024 is 4MB, you don't want any bigger usually.
SPRITE_ATLAS_SIZE :: 1024
MAX_SPRITE_SIZE :: SPRITE_ATLAS_SIZE - 2

Sprites :: enum u8 {
	Wabbit,
	Skull,
}

Sprite_Info :: struct {
	bitmap: Bitmap,
	pixels: []image.RGBA_Pixel,
	size: [2]u32,
}

sprites: [Sprites]Sprite_Info
sprites_textures: Texture_Array(SPRITE_ATLAS_SIZE)
