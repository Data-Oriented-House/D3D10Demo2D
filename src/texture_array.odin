package main

import "core:slice"
import sar "core:container/small_array"

import d3d "vendor:directx/d3d11"

import "lib:atlas_packer"

D3D10_REQ_TEXTURE2D_ARRAY_AXIS_DIMENSION :: 512

TEXTURE_SLOTS :: D3D10_REQ_TEXTURE2D_ARRAY_AXIS_DIMENSION

// Texture array is an array of large GPU textures, all with the same size NxN
Texture_Array :: struct($N: u32) {
	textures: ^d3d.IShaderResourceView,
	atlases: sar.Small_Array(TEXTURE_SLOTS, atlas_packer.Atlas),
}

texture_array_init :: proc(arr: $T/^Texture_Array($N)) {
	textures_desc: d3d.TEXTURE2D_DESC = {
		Width = N,
		Height = N,
		MipLevels = 1,
		ArraySize = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		Usage = .DEFAULT,
		BindFlags = {.SHADER_RESOURCE},
	}
	arr.textures = d3d_texture_make(&textures_desc)

	atlas: atlas_packer.Atlas
	atlas_packer.init(&atlas, {N, N})
	sar.push(&arr.atlases, atlas)
}

texture_array_finish :: proc(arr: $T/^Texture_Array($N)) {
	arr.textures->Release()
	for &atlas in sar.slice(&arr.atlases) {
		atlas_packer.destroy(&atlas)
	}
}

texture_array_push :: proc(arr: $T/^Texture_Array($N), texture_size: [2]u32) -> Bitmap {
	assert(sar.len(arr.atlases) > 0)

	atlas_last := slice.last_ptr(sar.slice(&arr.atlases))
	pos, fit := atlas_packer.try_insert(atlas_last, texture_size + 2)
	if !fit {
		textures_desc := d3d_texture_get_desc(arr.textures)
		textures_desc.ArraySize += 1
		arr.textures->Release()
		arr.textures = d3d_texture_make(&textures_desc)

		atlas: atlas_packer.Atlas
		atlas_packer.init(&atlas, {N, N})
		assert(sar.push(&arr.atlases, atlas))
		atlas_last = slice.last_ptr(sar.slice(&arr.atlases))
		pos, fit = atlas_packer.try_insert(atlas_last, texture_size + 2)
		assert(fit)
	}

	atlases_len := sar.len(arr.atlases)
	assert(atlases_len > 0)
	return {
		slot = cast(u32)atlases_len - 1,
		pos = pos + 1,
		size = texture_size,
	}
}

texture_array_blit :: proc(arr: $T/^Texture_Array($N), bitmap: Bitmap, pixels: []byte, pixel_size: u32) {
	texture_slot := d3d.CalcSubresource(MipSlice = 0, ArraySlice = bitmap.slot, MipLevels = 1)
	d3d_texture_blit(arr.texture, bitmap, pixels, pixel_size)
}
