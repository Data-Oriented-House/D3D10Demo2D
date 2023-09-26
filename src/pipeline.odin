package main

import d3d "vendor:directx/d3d11"

Pipeline_State :: struct {
	depth_stencil_state: ^d3d.IDepthStencilState,
	blend_state: ^d3d.IBlendState,
	rasterizer_state: ^d3d.IRasterizerState,
	sampler_state: ^d3d.ISamplerState,
}

Depth :: enum {
	Disabled,
}
Stencil :: enum {
	Disabled,
}
Blending :: enum {
	Disabled,
	Alpha_Premultiply,
}
Face_Culling :: enum {
	Disabled,
	Front,
	Back,
}
Texture_Filter :: enum {
	Linear,
}
Texture_Wrapping :: enum {
	Clamp,
	Wrap,
}

pipeline_make :: proc(
	depth: Depth,
	stencil: Stencil,
	blending: Blending,
	face_culling: Face_Culling,
	texture_filter: Texture_Filter,
	texture_wrapping: Texture_Wrapping,
) -> Pipeline_State {
	depth_stencil: d3d.DEPTH_STENCIL_DESC
	blend_desc: d3d.BLEND_DESC
	rasterizer_desc: d3d.RASTERIZER_DESC
	sampler_desc: d3d.SAMPLER_DESC

	switch depth {
	case .Disabled:
		depth_stencil.DepthEnable = false
		depth_stencil.DepthWriteMask = .ALL
		depth_stencil.DepthFunc = .LESS
	}

	switch stencil {
	case .Disabled:
		depth_stencil.StencilEnable = false
		depth_stencil.StencilReadMask = d3d.DEFAULT_STENCIL_READ_MASK
		depth_stencil.StencilWriteMask = d3d.DEFAULT_STENCIL_WRITE_MASK
		// depth_stencil.FrontFace = ...
		// depth_stencil.BackFace = ...
	}

	switch blending {
	case .Disabled:
	case .Alpha_Premultiply:
		// NOTE: This should probably be enabled for 8 targets, but I have no need of it yet.
	        blend_desc.RenderTarget[0] = {
			BlendEnable = true,

			SrcBlend = .ONE,
			DestBlend = .INV_SRC_ALPHA,
			BlendOp = .ADD,

			SrcBlendAlpha = .ONE,
			DestBlendAlpha = .ZERO,
			BlendOpAlpha = .ADD,

			RenderTargetWriteMask = cast(u8)d3d.COLOR_WRITE_ENABLE_ALL,
		}
	}

	switch face_culling {
	case .Disabled:
        	rasterizer_desc.FillMode = .SOLID
        	rasterizer_desc.CullMode = .NONE
	case .Front:
        	rasterizer_desc.FillMode = .SOLID
        	rasterizer_desc.CullMode = .FRONT
	case .Back:
        	rasterizer_desc.FillMode = .SOLID
        	rasterizer_desc.CullMode = .BACK
	}

	switch texture_filter {
	case .Linear:
		sampler_desc.Filter = .MIN_MAG_MIP_LINEAR
		sampler_desc.MaxLOD = max(f32)
	}

	switch texture_wrapping {
	case .Clamp:
		sampler_desc.AddressU = .CLAMP
		sampler_desc.AddressV = .CLAMP
		sampler_desc.AddressW = .CLAMP
	case .Wrap:
		sampler_desc.AddressU = .WRAP
		sampler_desc.AddressV = .WRAP
		sampler_desc.AddressW = .WRAP
	}


	state: Pipeline_State
	graphics.device->CreateDepthStencilState(&depth_stencil, &state.depth_stencil_state)
	graphics.device->CreateBlendState(&blend_desc, &state.blend_state)
	graphics.device->CreateRasterizerState(&rasterizer_desc, &state.rasterizer_state)
	graphics.device->CreateSamplerState(&sampler_desc, &state.sampler_state)
	return state
}

pipeline_set :: proc(state: Pipeline_State) {
	// Rasterizer
	graphics.device_context->RSSetState(state.rasterizer_state)
	// Output Merger
	graphics.device_context->OMSetDepthStencilState(state.depth_stencil_state, 0)
	graphics.device_context->OMSetBlendState(state.blend_state, nil, ~u32(0))
	// Shader
	samplers: [1]^d3d.ISamplerState = {state.sampler_state}
	graphics.device_context->PSSetSamplers(0, len(samplers), raw_data(&samplers))
}
