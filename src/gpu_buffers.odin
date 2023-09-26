package main

import "core:mem"

import d3d "vendor:directx/d3d11"

// Input buffer is an instanced dynamically mapped buffer that grows in blocks and never frees
Input_Buffer :: struct($T: typeid) {
	using gpu_buffer: ^d3d.IBuffer,

	block_size: uint,
	len: uint,
	cap: uint,
	mapped_ptr: rawptr,
}

input_buffer_init :: proc(buf: ^$B/Input_Buffer($T), block_size: uint) {
	buf.block_size = block_size
	buf.len = 0
	buf.cap = 0
	buf.mapped_ptr = nil

	// preallocate one block
	_input_buffer_expand(buf)
}

input_buffer_push :: proc(buf: ^$B/Input_Buffer($T), items: ..T) {
	// expand buffer if items do not fit
	for buf.len + len(items) > buf.cap {
		if buf.mapped_ptr != nil {
			graphics.device_context->Unmap(buf.gpu_buffer, 0)
			buf.mapped_ptr = nil
		}
		_input_buffer_expand(buf)
	}

	// map if not mapped
	if buf.mapped_ptr == nil {
		mapped_resource: d3d.MAPPED_SUBRESOURCE
		graphics.device_context->Map(buf.gpu_buffer, 0, .WRITE_DISCARD, {}, &mapped_resource)
		buf.mapped_ptr = mapped_resource.pData
	}

	// push item to the mapped buffer
	data_ptr := mem.ptr_offset(cast(^byte)buf.mapped_ptr, buf.len * size_of(T))
	mem.copy(data_ptr, raw_data(items), len(items) * size_of(T))
	buf.len += 1
}

input_buffer_clear :: proc(buf: ^$B/Input_Buffer($T)) {
	buf.len = 0
}

_input_buffer_expand :: proc(buf: ^$B/Input_Buffer($T)) {
	buffer_size := buf.cap + buf.block_size

	gpu_buffer: ^d3d.IBuffer
	gpu_buffer_desc: d3d.BUFFER_DESC = {
		ByteWidth = u32(buffer_size * size_of(T)),
		Usage = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	// TODO: Handle error
	graphics.device->CreateBuffer(&gpu_buffer_desc, nil, &gpu_buffer)

	// Copy old data to the new buffer
	if buf.gpu_buffer != nil {
		graphics.device_context->CopySubresourceRegion(gpu_buffer, 0, 0, 0, 0, buf.gpu_buffer, 0, nil)
		buf.gpu_buffer->Release()
	}

	buf.gpu_buffer = gpu_buffer
	buf.cap = buffer_size
}

input_buffer_bind :: proc(buf: ^$B/Input_Buffer($T)) {
	if buf.gpu_buffer == nil {
		return
	}

	if buf.mapped_ptr != nil {
		graphics.device_context->Unmap(buf.gpu_buffer, 0)
		buf.mapped_ptr = nil
	}

	stride := u32(size_of(T))
	offset := u32(0)
	graphics.device_context->IASetVertexBuffers(0, 1, &buf.gpu_buffer, &stride, &offset)
}


// Constant buffer is a static buffer in which you can upload the data for the draw call
Constant_Buffer :: struct($T: typeid) {
	using gpu_buffer: ^d3d.IBuffer,
}

constant_buffer_init :: proc(buf: ^$B/Constant_Buffer($T)) {
	// Constant buffer size must be aligned to 16 bytes
	buffer_size := cast(u32)mem.align_forward_uint(size_of(T), 16)
	// D3D10 limits number of elements in a constant buffer to 4096
	assert(buffer_size <= 4096, "Constant buffer is too big")

	constant_buffer_desc: d3d.BUFFER_DESC = {
		ByteWidth = buffer_size,
		Usage = .DEFAULT,
		BindFlags = {.CONSTANT_BUFFER},
		CPUAccessFlags = {},
	}
	graphics.device->CreateBuffer(&constant_buffer_desc, nil, &buf.gpu_buffer)
}

constant_buffer_update :: proc(buf: ^$B/Constant_Buffer($T), data: ^T) {
	graphics.device_context->UpdateSubresource(buf.gpu_buffer, 0, nil, data, 0, 0)
}

constant_buffer_bind :: proc(buf: ^$B/Constant_Buffer($T)) {
	graphics.device_context->VSSetConstantBuffers(0, 1, &buf.gpu_buffer)
	graphics.device_context->PSSetConstantBuffers(0, 1, &buf.gpu_buffer)
}
