package app

import "core:os"
import "core:fmt"
import "core:time"
import "core:sync"
import "core:runtime"
import "core:container/small_array"

import win32 "core:sys/windows"

import "vendor:directx/dxgi"
import d3d "vendor:directx/d3d11"

SWAPCHAIN_FLAGS : dxgi.SWAP_CHAIN_FLAG : .FRAME_LATENCY_WAITABLE_OBJECT

Graphics_Context_OS_Specific :: struct {
	device: ^d3d.IDevice,
	device_context: ^d3d.IDeviceContext,

	dxgi_factory: ^dxgi.IFactory2,
	swapchain: ^dxgi.ISwapChain2,
	waitable_object: win32.HANDLE,

	rt_view: ^d3d.IRenderTargetView,
}

_graphics_init :: proc() {
	// Create D3D device
	feature_level: d3d.FEATURE_LEVEL = ._10_0
	device_flags: d3d.CREATE_DEVICE_FLAGS
	when ODIN_DEBUG {
		device_flags += {.DEBUG}
	}
	// TODO: check if return value is good, otherwise retry with .WARP driver
	d3d.CreateDevice(
		pAdapter = nil,
		DriverType = .HARDWARE,
		Software = nil,
		Flags = device_flags,
		pFeatureLevels = &feature_level,
		FeatureLevels = 1,
		SDKVersion = d3d.SDK_VERSION,
		ppDevice = &window.device,
		pFeatureLevel = nil,
		ppImmediateContext = &window.device_context,
	)

	when ODIN_DEBUG {
		// D3D debug breaks
		d3d_info: ^d3d.IInfoQueue
		window.device->QueryInterface(d3d.IInfoQueue_UUID, cast(^rawptr)&d3d_info)
		d3d_info->SetBreakOnSeverity(.CORRUPTION, true)
		d3d_info->SetBreakOnSeverity(.ERROR, true)
		d3d_info->Release()

		// DXGI debug breaks
		dxgi_info: ^dxgi.IInfoQueue
		dxgi.DXGIGetDebugInterface1(0, dxgi.IInfoQueue_UUID, cast(^rawptr)&dxgi_info)
		dxgi_info->SetBreakOnSeverity(dxgi.DEBUG_ALL, .CORRUPTION, true)
		dxgi_info->SetBreakOnSeverity(dxgi.DEBUG_ALL, .ERROR, true)
		dxgi_info->Release()
	}

	// Create swapchain
	// NOTE: This will safely work on modern Windows 10/11, 8.1 might work (need to test), 7 definitely will not
	dxgi_adapter := _get_dxgi_adapter()
	dxgi_factory2: ^dxgi.IFactory2
	dxgi_adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&window.dxgi_factory))
	dxgi_adapter->Release()

	swapchain_desc: dxgi.SWAP_CHAIN_DESC1 = {
		Width  = 0, // use window width
		Height = 0, // use window height
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {
			Count = 1,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling = .NONE,
		SwapEffect  = .FLIP_DISCARD,
		Flags = cast(u32)SWAPCHAIN_FLAGS,
	}
	swapchain1: ^dxgi.ISwapChain1
	window.dxgi_factory->CreateSwapChainForHwnd(window.device, window.id, &swapchain_desc, nil, nil, &swapchain1)
	swapchain1->QueryInterface(dxgi.ISwapChain2_UUID, cast(^rawptr)&window.swapchain)
	swapchain1->Release()

	// Get latency-reducing miracle object
	window.waitable_object = window.swapchain->GetFrameLatencyWaitableObject()

	// Disable silly Alt+Enter changing monitor resolution to match window size
	window.dxgi_factory->MakeWindowAssociation(window.id, cast(u32)dxgi.MWA{.NO_ALT_ENTER})
}

_get_dxgi_device :: proc() -> ^dxgi.IDevice1 {
	dxgi_device: ^dxgi.IDevice1
	window.device->QueryInterface(dxgi.IDevice1_UUID, (^rawptr)(&dxgi_device))
	return dxgi_device
}

_get_dxgi_adapter :: proc() -> ^dxgi.IAdapter {
	dxgi_device := _get_dxgi_device()
	dxgi_adapter: ^dxgi.IAdapter
	dxgi_device->GetAdapter(&dxgi_adapter)
	dxgi_device->Release()

	return dxgi_adapter
}

_graphics_resize_framebuffer :: proc(new_framebuffer_size: [2]u32) {
	// Release old framebuffer
	if window.rt_view != nil {
		window.device_context->ClearState()
		window.rt_view->Release()
	}

	// Resize framebuffer
	resize_result := cast(u32)window.swapchain->ResizeBuffers(
		BufferCount = 0,
		Width = new_framebuffer_size[0],
		Height = new_framebuffer_size[1],
		NewFormat = .UNKNOWN,
		SwapChainFlags = cast(u32)SWAPCHAIN_FLAGS,
	)
	assert(resize_result == 0, fmt.tprintf("{:x}", resize_result))

	{ // Framebuffer view
		backbuffer: ^d3d.ITexture2D
		window.swapchain->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&backbuffer))
		window.device->CreateRenderTargetView(backbuffer, nil, &window.rt_view)
		backbuffer->Release()
	}

	{ // Rasterizer Stage
		viewport: d3d.VIEWPORT = {
			TopLeftX = 0,
			TopLeftY = 0,
			Width = f32(new_framebuffer_size[0]),
			Height = f32(new_framebuffer_size[1]),
			MinDepth = 0,
			MaxDepth = 1,
		}
		window.device_context->RSSetViewports(1, &viewport)
	}
}

// Only prints debug stuff
@(disabled=!ODIN_DEBUG)
_graphics_finish :: proc() {
	win32.CloseHandle(window.waitable_object)

	when false {
		// Print leaked objects
		dxgi_debug: ^dxgi.IDebug
		dxgi.DXGIGetDebugInterface1(0, dxgi.IDebug_UUID, cast(^rawptr)&dxgi_debug)
		dxgi_debug->ReportLiveObjects(dxgi.DEBUG_ALL, .SUMMARY)
		dxgi_debug->Release()
	}

	// Mute printing of leaked objects, since DXGI prints them automatically
	dxgi_info: ^dxgi.IInfoQueue
	dxgi.DXGIGetDebugInterface1(0, dxgi.IInfoQueue_UUID, cast(^rawptr)&dxgi_info)
	dxgi_info->SetMuteDebugOutput(dxgi.DEBUG_ALL, true)
	dxgi_info->Release()
}

_graphics_frame_prepare :: proc() {
	win32.WaitForSingleObject(window.waitable_object, 1000)
}

_graphics_frame_present :: proc() {
	window.swapchain->Present(1, 0)
}
