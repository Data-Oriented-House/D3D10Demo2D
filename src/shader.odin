package main

import "core:log"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:strconv"
import "core:math/bits"

import "vendor:directx/dxgi"
import d3d "vendor:directx/d3d11"
import d3dc "vendor:directx/d3d_compiler"

D3DShader :: struct {
	topology: d3d.PRIMITIVE_TOPOLOGY,
	vertex: ^d3d.IVertexShader,
	pixel: ^d3d.IPixelShader,
	input_layout: ^d3d.IInputLayout,
}

shader_load :: proc(
	shader: ^D3DShader,
	topology: d3d.PRIMITIVE_TOPOLOGY,
	vertex_data: []byte,
	pixel_data: []byte,
	input_type: typeid,
) {
	shader.topology = topology
	graphics.device->CreateVertexShader(raw_data(vertex_data), len(vertex_data), nil, &shader.vertex)
	graphics.device->CreatePixelShader(raw_data(pixel_data), len(pixel_data), nil, &shader.pixel)

	if input_type == nil {
		return
	}

	is_struct :: proc(T: typeid) -> bool {
		ti := reflect.type_info_base(type_info_of(T))
		if ti != nil {
			#partial switch info in ti.variant {
			case reflect.Type_Info_Struct:
				return true
			}
		}
		return false
	}

	assert(is_struct(input_type), "input_type must be a tagged struct, or a nil")

	get_format_from_type :: proc(type: d3d.REGISTER_COMPONENT_TYPE, type_size: u8) -> dxgi.FORMAT {
		#partial switch type {
		case .UINT32:
			switch type_size {
			case 1: return .R32_UINT
			case 2: return .R32G32_UINT
			case 3: return .R32G32B32_UINT
			case 4: return .R32G32B32A32_UINT
			}
		case .SINT32:
			switch type_size {
			case 1: return .R32_SINT
			case 2: return .R32G32_SINT
			case 3: return .R32G32B32_SINT
			case 4: return .R32G32B32A32_SINT
			}
		case .FLOAT32:
			switch type_size {
			case 1: return .R32_FLOAT
			case 2: return .R32G32_FLOAT
			case 3: return .R32G32B32_FLOAT
			case 4: return .R32G32B32A32_FLOAT
			}
		}

		unreachable()
	}

	// Auto-fill and verify input layout
	reflection: ^d3d.IShaderReflection
	d3dc.Reflect(raw_data(vertex_data), len(vertex_data), d3d.ID3D11ShaderReflection_UUID, cast(^rawptr)&reflection)
	defer reflection->Release()

	shader_desc: d3d.SHADER_DESC
	reflection->GetDesc(&shader_desc)
	params_desc := make([]d3d.SIGNATURE_PARAMETER_DESC, shader_desc.InputParameters, context.temp_allocator)

	// First pass - fill input layout array
	layout_desc := make([dynamic]d3d.INPUT_ELEMENT_DESC, context.temp_allocator)
	for &param_desc, idx in params_desc {
		reflection->GetInputParameterDesc(u32(idx), &param_desc)

		// Skip all system-defined types
		if param_desc.SystemValueType != .UNDEFINED {
			continue
		}

		layout_element: d3d.INPUT_ELEMENT_DESC
		layout_element.SemanticName = param_desc.SemanticName
		layout_element.SemanticIndex = param_desc.SemanticIndex
		layout_element.InputSlotClass = .INSTANCE_DATA
		// NOTE: I do not plan on using N-rate instanced data in the near future.
		layout_element.InstanceDataStepRate = 1

		type_size: u32
		if param_desc.SemanticName == "COL" {
			layout_element.Format = .R8G8B8A8_UNORM
			type_size = 4
		} else {
			type_len := bits.count_ones(param_desc.Mask)
			layout_element.Format = get_format_from_type(param_desc.ComponentType, type_len)
			type_size = 4 * u32(type_len)
		}

		// Temporarily save type size to AlignedByteOffset for second pass
		layout_element.AlignedByteOffset = type_size

		append(&layout_desc, layout_element)

		// Temporarily save semantic length to InputSlot for second pass
		layout_len := len(layout_desc)
		for i in 0..<param_desc.SemanticIndex + 1 {
			layout_desc[(layout_len - 1) - int(i)].InputSlot = param_desc.SemanticIndex + 1
		}
	}

	// Second pass - assign proper offsets, verify fields and their size
	for &layout_element, idx in layout_desc {
		type_size := layout_element.AlignedByteOffset
		semantic_len := layout_element.InputSlot
		field_size := type_size * semantic_len

		if layout_element.SemanticIndex == 0 {
			// Find field with the same tag
			field_found: bool
			struct_fields := reflect.struct_fields_zipped(input_type)
			for sf in struct_fields {
				if string(layout_element.SemanticName) == string(sf.tag) {
					// Verify field size
					assert(u32(reflect.size_of_typeid(sf.type.id)) == field_size, string(layout_element.SemanticName))
					// Assign AlignedByteOffset to tagged field's offset
					layout_element.AlignedByteOffset = cast(u32)sf.offset

					assert(!field_found, fmt.tprint("Found 2 fields with the same tag:", sf.tag))
					field_found = true
				}
			}
			if !field_found {
				log.info("Unassigned shader field:", layout_element.SemanticName)
			}
		} else {
			// Align to previous field
			prev_offset := layout_desc[idx - 1].AlignedByteOffset
			layout_element.AlignedByteOffset = prev_offset + type_size
		}
		layout_element.InputSlot = 0
	}

	graphics.device->CreateInputLayout(
		raw_data(layout_desc), cast(u32)len(layout_desc),
		raw_data(vertex_data), len(vertex_data),
		&shader.input_layout,
	)
}

shader_unload :: proc(shader: ^D3DShader) {
	shader.vertex->Release()
	shader.pixel->Release()
}

shader_bind :: proc(shader: ^D3DShader) {
	graphics.device_context->IASetPrimitiveTopology(shader.topology)

	if shader.input_layout != nil {
		graphics.device_context->IASetInputLayout(shader.input_layout)
	}

	graphics.device_context->VSSetShader(shader.vertex, nil, 0)
	graphics.device_context->PSSetShader(shader.pixel, nil, 0)
}
