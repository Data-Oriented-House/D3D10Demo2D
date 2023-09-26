package data_packer

import "core:mem"
import "core:reflect"
import "core:mem/virtual"

Map_Writer :: struct {
	buf: []byte,
	data_cursor: uint,
}

// Packs data of simple formats into a byte array to be written to disk or otherwise
// NOTE: Does not support map/data packer, turn those into slices to pack
pack :: proc(v: any, size_limit: uint) -> []byte {
	buf, err := virtual.reserve_and_commit(size_limit)
	assert(err == nil)

	w: Map_Writer
	w.buf = buf
	w.data_cursor = cast(uint)reflect.size_of_typeid(v.id)

	_pack(&w, 0, v)
	return w.buf[:w.data_cursor]
}

// Maps root datatype of the packed data (no allocations, not recursive)
map_root :: proc(data: []byte, $T: typeid) -> T {
	root := (cast(^T)raw_data(data))^
	return unpack_value(data, root)
}

// Unpacks a value from the data by mapping (no allocations, not recursive)
unpack_value :: proc(data: []byte, v: $T) -> T {
	vu: T
	_map_value(data, vu, v)
	return vu
}

/*
Example packing:

// Common data structures for asset packer and program that uses the assets
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

{ // Write asset packer like this
	assets: Assets

	// Fill assets with some data

	os.write_entire_file("assets.pack", packer.pack(assets, 4 * mem.Megabyte))
}

{ // Write this in a program that needs the assets
	ASSETS :: #load("assets.pack")
	assets := packer.map_root(ASSETS, Assets)

	// Notice that since assets was mapped, it's values are also mapped, but only 1 level deep
	for sprite in assets.sprites {
		// So you need to unpack every item in the slice properly like this
		sprite := packer.unpack_value(ASSETS, sprite)

		fmt.println("Unpacked", sprite.name)
		// Now you can use sprite.pixels (slice of pixels) to draw the sprite.
		// If value was 1 more level deep (slice of slices instead of slice of pixels),
		// you would need to unpack every element in it individually again.
	}
}
*/


// NOTE
// write_cursor being passed is where the type info should be written
// w.data_cursor is where pointer data should be written
_pack :: proc(w: ^Map_Writer, write_cursor: uint, v: any) {
	ti := reflect.type_info_base(type_info_of(v.id))
	assert(ti != nil)

	#partial switch info in ti.variant {
	case
	// Allocator field is not meaningfully mappable, just use slices.
	reflect.Type_Info_Dynamic_Array,
	// Internal structure is too complicated to be mapped, and also has an allocator field, so use slices.
	reflect.Type_Info_Map,
	// Is this even useful at all? Can base type info even be any?
	reflect.Type_Info_Any:
		unreachable()
	case reflect.Type_Info_Union:
		// Is it possible to pack union, considering it packs unknown types?
		unreachable()
	case reflect.Type_Info_Pointer:
		unimplemented()
	case reflect.Type_Info_String:
		write_cursor := write_cursor

		if !info.is_cstring {
			_pack(w, write_cursor, any{v.data, typeid_of([]byte)})
			return
		}

		// Write pointer to data
		dst := cast(^mem.Raw_Cstring)&w.buf[write_cursor]
		dst.data = cast([^]byte)cast(uintptr)w.data_cursor
		// Iterate and write data
		cstr := cast(^mem.Raw_Cstring)v.data
		for idx := 0; ; idx += 1 {
			w.buf[w.data_cursor] = cstr.data[idx]
			w.data_cursor += size_of(byte)

			if cstr.data[idx] == 0 {
				break
			}
		}
		return
	case reflect.Type_Info_Slice:
		write_cursor := write_cursor

		vs := cast(^mem.Raw_Slice)v.data
		bs := mem.byte_slice(vs.data, vs.len * info.elem_size)

		ds := cast(^mem.Raw_Slice)&w.buf[write_cursor]
		ds.data = cast(rawptr)cast(uintptr)w.data_cursor
		ds.len = vs.len

		w.data_cursor += len(bs)
		write_cursor = cast(uint)cast(uintptr)ds.data
		for i in 0..<ds.len {
			elem := any{&bs[i * info.elem_size], info.elem.id}
			_pack(w, write_cursor, elem)
			write_cursor += cast(uint)info.elem_size
		}
	case reflect.Type_Info_Struct:
		write_cursor := write_cursor
		struct_fields := reflect.struct_fields_zipped(v.id)
		for f in struct_fields {
			field := any{rawptr(uintptr(v.data) + f.offset), f.type.id}
			_pack(w, write_cursor + cast(uint)f.offset, field)
		}
	case:
		write_cursor := write_cursor
		mem.copy(&w.buf[write_cursor], v.data, ti.size)
	}
}

// For normal values - copies them to destination
// For slices/strings/cstrings - also corrects data pointer from offset to actual memory
_map_value :: proc(data: []byte, dst_ref: any, src: any) {
	ti := reflect.type_info_base(type_info_of(src.id))
	assert(ti != nil)

	#partial switch info in ti.variant {
	case reflect.Type_Info_String:
		if !info.is_cstring {
			src_bytes := any{src.data, typeid_of([]byte)}
			dst_bytes := any{dst_ref.data, typeid_of([]byte)}
			_map_value(data, dst_bytes, src_bytes)
			return
		}

		mem.copy(dst_ref.data, src.data, size_of(mem.Raw_Cstring))
		dst_cstr := cast(^mem.Raw_Cstring)dst_ref.data
		dst_cstr.data = cast([^]byte)(cast(uintptr)raw_data(data) + cast(uintptr)dst_cstr.data)
	case reflect.Type_Info_Slice:
		mem.copy(dst_ref.data, src.data, size_of(mem.Raw_Slice))
		dst_slice := cast(^mem.Raw_Slice)dst_ref.data
		dst_slice.data = cast(rawptr)(cast(uintptr)raw_data(data) + cast(uintptr)dst_slice.data)
	case reflect.Type_Info_Struct:
		struct_fields := reflect.struct_fields_zipped(src.id)
		for f in struct_fields {
			src_field := any{cast(rawptr)(cast(uintptr)src.data + f.offset), f.type.id}
			dst_field := any{cast(rawptr)(cast(uintptr)dst_ref.data + f.offset), f.type.id}
			_map_value(data, dst_field, src_field)
		}
	case:
		mem.copy(dst_ref.data, src.data, ti.size)
	}
}
import "core:fmt"
