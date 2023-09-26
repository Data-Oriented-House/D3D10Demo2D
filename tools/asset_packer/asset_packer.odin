package main

import "core:os"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:bytes"
import "core:reflect"
import "core:strings"
import "core:path/filepath"

import "core:image"
@(require) import "core:image/png"

import packer "../../lib/data_packer"

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

main :: proc() {
	exe_path := filepath.dir(os.args[0])
	os.change_directory(exe_path)

	assets: Assets
	{ // Add font
		dir, _ := os.open("../../res/fonts/default")
		files_info, _ := os.read_dir(dir, -1)

		assets.default_font = make([]Glyph_Asset, len(files_info))
		for &glyph, idx in assets.default_font {
			fi := files_info[idx]

			glyph.codepoint = rune_from_name(strings.trim_suffix(fi.name, ".png"))

			img, err := image.load(fi.fullpath, {.alpha_add_if_missing, .alpha_premultiply})
			assert(err == nil, fmt.tprintf("Failed to load glyph for {}: {}", glyph.codepoint, err))
			defer image.destroy(img)

			img_pixels := slice.reinterpret([]image.RGBA_Pixel, bytes.buffer_to_bytes(&img.pixels))

			glyph.pixels = slice.clone(img_pixels)
			glyph.size = {cast(u32)img.width, cast(u32)img.height}

			switch glyph.codepoint {
			case 'y', 'g', 'p', 'q', 'j', ',', ';', ':', '-', '+', '=', '<', '>':
				glyph.y_offset = 1
			}
		}
	}
	{ // Add sprites
		dir, _ := os.open("../../res/sprites")
		files_info, _ := os.read_dir(dir, -1)

		assets.sprites = make([]Sprite_Asset, len(files_info))
		for &sprite, idx in assets.sprites {
			fi := files_info[idx]

			sprite.name = sprite_from_name(strings.trim_suffix(fi.name, ".png"))

			img, err := image.load(fi.fullpath, {.alpha_add_if_missing, .alpha_premultiply})
			assert(err == nil, fmt.tprintf("Failed to load sprite {}: {}", sprite.name, err))
			defer image.destroy(img)

			img_pixels := slice.reinterpret([]image.RGBA_Pixel, bytes.buffer_to_bytes(&img.pixels))

			sprite.pixels = slice.clone(img_pixels)
			sprite.size = {cast(u32)img.width, cast(u32)img.height}
		}
	}
	{ // Add sounds
		dir, _ := os.open("../../res/sounds")
		files_info, _ := os.read_dir(dir, -1)

		assets.sounds = make([]Sound_Asset, len(files_info))
		for &sound, idx in assets.sounds {
			fi := files_info[idx]
			data, ok := os.read_entire_file(fi.fullpath)
			assert(ok)

			sound.name = strings.clone_to_cstring(sound_from_name(strings.trim_suffix(fi.name, ".ogg")))
			sound.data = data
		}
	}

	// Pack assets
	os.write_entire_file("../../res/assets.pack", packer.pack(assets, 4 * mem.Megabyte))

	{ // Unpack and compare
		data, ok := os.read_entire_file("../../res/assets.pack")
		assert(ok)

		test_assets := packer.unpack(data, Assets)
		for glyph, i in test_assets.default_font {
			glyph := packer.unpack_value(data, glyph)
			assert(reflect.equal(assets.default_font[i], glyph, including_indirect_array_recursion = true))
		}
		for sprite, i in test_assets.sprites {
			sprite := packer.unpack_value(data, sprite)
			assert(reflect.equal(assets.sprites[i], sprite, including_indirect_array_recursion = true))
		}
		for sound, i in test_assets.sounds {
			sound := packer.unpack_value(data, sound)
			assert(reflect.equal(assets.sounds[i], sound, including_indirect_array_recursion = true))
		}
	}

	fmt.printf("res/assets.pack [{} glyphs; {} sprites; {} sounds]\n", len(assets.default_font), len(assets.sprites), len(assets.sounds))
}

rune_from_name :: proc(name: string) -> rune {
	switch name {
	case "question": return '?'
	case "exclamation": return '!'
	case "dot": return '.'
	case "comma": return ','
	case "colon": return ':'
	case "semicolon": return ';'
	case "quote": return '\''
	case "double_quote": return '"'
	case "tilde": return '~'
	case "at": return '@'
	case "hash": return '#'
	case "dollar": return '$'
	case "caret": return '^'
	case "ampersand": return '&'
	case "pipe": return '|'
	case "slash": return '/'
	case "backslash": return '\\'
	case "percent": return '%'
	case "star": return '*'
	case "plus": return '+'
	case "minus": return '-'
	case "equals": return '='
	case "less": return '<'
	case "greater": return '>'
	case "underline": return '_'
	case "bracket0": return '['
	case "bracket1": return ']'
	case "brace0": return '{'
	case "brace1": return '}'
	case "parenthesis0": return '('
	case "parenthesis1": return ')'

	case "a_": return 'A'
	case "b_": return 'B'
	case "c_": return 'C'
	case "d_": return 'D'
	case "e_": return 'E'
	case "f_": return 'F'
	case "g_": return 'G'
	case "h_": return 'H'
	case "i_": return 'I'
	case "j_": return 'J'
	case "k_": return 'K'
	case "l_": return 'L'
	case "m_": return 'M'
	case "n_": return 'N'
	case "o_": return 'O'
	case "p_": return 'P'
	case "q_": return 'Q'
	case "r_": return 'R'
	case "s_": return 'S'
	case "t_": return 'T'
	case "u_": return 'U'
	case "v_": return 'V'
	case "w_": return 'W'
	case "x_": return 'X'
	case "y_": return 'Y'
	case "z_": return 'Z'

	case "a": return 'a'
	case "b": return 'b'
	case "c": return 'c'
	case "d": return 'd'
	case "e": return 'e'
	case "f": return 'f'
	case "g": return 'g'
	case "h": return 'h'
	case "i": return 'i'
	case "j": return 'j'
	case "k": return 'k'
	case "l": return 'l'
	case "m": return 'm'
	case "n": return 'n'
	case "o": return 'o'
	case "p": return 'p'
	case "q": return 'q'
	case "r": return 'r'
	case "s": return 's'
	case "t": return 't'
	case "u": return 'u'
	case "v": return 'v'
	case "w": return 'w'
	case "x": return 'x'
	case "y": return 'y'
	case "z": return 'z'

	case "0": return '0'
	case "1": return '1'
	case "2": return '2'
	case "3": return '3'
	case "4": return '4'
	case "5": return '5'
	case "6": return '6'
	case "7": return '7'
	case "8": return '8'
	case "9": return '9'
	}

	// Return the first rune
	for r in name do return r

	unreachable()
}

sprite_from_name :: proc(name: string) -> string {
	switch name {
	case "skull": return "Skull"
	case "wabbit": return "Wabbit"
	}

	unreachable()
}

sound_from_name :: proc(name: string) -> string {
	switch name {
	case "boom": return "Boom"
	case "reconstruction_science": return "Reconstruction_Science"
	}

	unreachable()
}
