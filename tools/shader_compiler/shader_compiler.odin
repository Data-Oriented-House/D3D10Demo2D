package shader_compiler

import "core:os"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:path/filepath"

import d3d "vendor:directx/d3d11"
import d3dc "vendor:directx/d3d_compiler"

import packer "../../lib/data_packer"

Shader_Asset :: struct {
	name: string,
	topology: d3d.PRIMITIVE_TOPOLOGY,
	vso, pso: []byte,
}

compile_shader :: proc(type: d3d.SHADER_VERSION_TYPE, data: []byte, src_filepath: string, debug: bool) -> []byte {
	DEFAULT_FLAGS : d3dc.D3DCOMPILE : {
		.PACK_MATRIX_ROW_MAJOR, // Odin uses row-major matrix layout
		.ENABLE_STRICTNESS,
		.WARNINGS_ARE_ERRORS,
	}
	DEBUG_FLAGS :: DEFAULT_FLAGS + {.DEBUG, .SKIP_OPTIMIZATION}
	RELEASE_FLAGS :: DEFAULT_FLAGS + d3dc.D3DCOMPILE_OPTIMIZATION_LEVEL3

	shader_path := strings.clone_to_cstring(src_filepath)
	compile_flags := DEBUG_FLAGS if debug else RELEASE_FLAGS

	entrypoint, target: cstring
	switch type {
	case .PIXEL_SHADER:
		entrypoint = "ps_main"
		target = "ps_4_0"
	case .VERTEX_SHADER:
		entrypoint = "vs_main"
		target = "vs_4_0"
	case .GEOMETRY_SHADER, .HULL_SHADER, .DOMAIN_SHADER:
		panic("Are these even useful?")
	case .COMPUTE_SHADER:
		panic("My PC doesn't support compute shaders.")
	case .RESERVED0:
		unreachable()
	}

	blob: ^d3dc.ID3DBlob
	errs: ^d3dc.ID3DBlob
	if d3dc.Compile(
		raw_data(data), len(data), shader_path,
		nil, d3dc.D3DCOMPILE_STANDARD_FILE_INCLUDE,
		entrypoint, target, transmute(u32)compile_flags, 0,
		&blob, &errs,
	) != 0 {
		err := cast(cstring)errs->GetBufferPointer()
		fmt.eprint(err)
	}

	return mem.byte_slice(blob->GetBufferPointer(), blob->GetBufferSize())
}

main :: proc() {
	exe_path := filepath.dir(os.args[0])
	os.change_directory(exe_path)

	// TODO: shader_packer shader.hlsl shader2.hlsl -o shaders.pack

	shaders_debug, shaders_release: [dynamic]Shader_Asset
	src_dir, _ := os.open("../../src/shaders")
	files_info, _ := os.read_dir(src_dir, -1)
	for fi in files_info {
		if !strings.has_suffix(fi.name, ".hlsl") do continue

		shader_code, ok := os.read_entire_file(fi.fullpath)
		assert(ok)

		name := shader_from_name(strings.trim_suffix(fi.name, ".hlsl"))
		topology := topology_from_name(strings.trim_suffix(fi.name, ".hlsl"))

		{
			vso := compile_shader(.VERTEX_SHADER, shader_code, fi.fullpath, debug = true)
			pso := compile_shader(.PIXEL_SHADER, shader_code, fi.fullpath, debug = true)
			fmt.printf("{} (debug): vso [{} KB]; pso [{} KB]\n", name, len(vso) / mem.Kilobyte, len(pso) / mem.Kilobyte)
			append(&shaders_debug, Shader_Asset{name = name, topology = topology, vso = vso, pso = pso})
		}
		{
			vso := compile_shader(.VERTEX_SHADER, shader_code, fi.fullpath, debug = false)
			pso := compile_shader(.PIXEL_SHADER, shader_code, fi.fullpath, debug = false)
			fmt.printf("{} (release): vso [{} KB]; pso [{} KB]\n", name, len(vso) / mem.Kilobyte, len(pso) / mem.Kilobyte)
			append(&shaders_release, Shader_Asset{name = name, topology = topology, vso = vso, pso = pso})
		}
	}

	// Pack the shaders
	DEBUG_PACK_PATH :: "../../res/shaders_debug.pack"
	RELEASE_PACK_PATH :: "../../res/shaders_release.pack"
	debug_asset: []Shader_Asset = shaders_debug[:]
	release_asset: []Shader_Asset = shaders_release[:]
	os.write_entire_file(DEBUG_PACK_PATH, packer.pack(debug_asset, 1 * mem.Megabyte))
	os.write_entire_file(RELEASE_PACK_PATH, packer.pack(release_asset, 1 * mem.Megabyte))
	// Unpack and compare
	{
		data, ok := os.read_entire_file(DEBUG_PACK_PATH)
		assert(ok)
		test_asset := packer.unpack(data, []Shader_Asset)

		for a, i in test_asset {
			a := packer.unpack_value(data, a)
			assert(reflect.equal(debug_asset[i], a, including_indirect_array_recursion = true))
		}
	}
	{
		data, ok := os.read_entire_file(RELEASE_PACK_PATH)
		assert(ok)
		test_asset := packer.unpack(data, []Shader_Asset)

		for a, i in test_asset {
			a := packer.unpack_value(data, a)
			assert(reflect.equal(release_asset[i], a, including_indirect_array_recursion = true))
		}
	}

	fmt.println("Done!")
}

topology_from_name :: proc(name: string) -> d3d.PRIMITIVE_TOPOLOGY {
	switch name {
	case "shapes": return .TRIANGLESTRIP
	case "font": return .TRIANGLESTRIP
	}

	unreachable()
}

shader_from_name :: proc(name: string) -> string {
	switch name {
	case "shapes": return "Shapes"
	case "font": return "Font"
	}

	unreachable()
}
