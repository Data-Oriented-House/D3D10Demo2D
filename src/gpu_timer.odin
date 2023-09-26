package main

import "core:log"
import "core:time"
import "core:thread"

import d3d "vendor:directx/d3d11"

// 1 frame delay is too little on my PC, eats 30% of the CPU, 2 and up calms it down
GPU_TIMER_FRAME_DELAY :: 2

GPU_TIMER_CACHE_SIZE :: GPU_TIMER_FRAME_DELAY + 1

D3DTimer_Query :: struct {
	start, end, disjoint: ^d3d.IQuery,
}

D3DTimer :: struct {
	frame: uint,
	queries: [GPU_TIMER_CACHE_SIZE]D3DTimer_Query,
}

gpu_timer_init :: proc(gpu_timer: ^D3DTimer) {
	for &query in gpu_timer.queries {
		query_desc: d3d.QUERY_DESC
		query_desc.Query = .TIMESTAMP_DISJOINT
		graphics.device->CreateQuery(&query_desc, &query.disjoint)

		query_desc.Query = .TIMESTAMP
		graphics.device->CreateQuery(&query_desc, &query.start)
		graphics.device->CreateQuery(&query_desc, &query.end)
	}
}

gpu_timer_frame_begin :: proc(gpu_timer: ^D3DTimer) {
	index := gpu_timer.frame % GPU_TIMER_CACHE_SIZE
	graphics.device_context->Begin(gpu_timer.queries[index].disjoint)
	graphics.device_context->End(gpu_timer.queries[index].start)
}

gpu_timer_frame_end :: proc(gpu_timer: ^D3DTimer) {
	index := gpu_timer.frame % GPU_TIMER_CACHE_SIZE
	graphics.device_context->End(gpu_timer.queries[index].end)
	graphics.device_context->End(gpu_timer.queries[index].disjoint)
}

gpu_timer_collect :: proc(gpu_timer: ^D3DTimer) -> (work_time: time.Duration, ok: bool) {
	gpu_timer.frame += 1
	if gpu_timer.frame < GPU_TIMER_CACHE_SIZE {
		return
	}
	index := gpu_timer.frame % GPU_TIMER_CACHE_SIZE

	frame_data: d3d.QUERY_DATA_TIMESTAMP_DISJOINT
	for graphics.device_context->GetData(gpu_timer.queries[index].disjoint, &frame_data, size_of(frame_data), 0) != 0 {
		// prevents thread from being taken hostage
		thread.yield()
	}
	if frame_data.Disjoint {
		return
	}

	frame_start_t, frame_end_t: u64
	graphics.device_context->GetData(gpu_timer.queries[index].start, &frame_start_t, size_of(frame_start_t), 0)
	graphics.device_context->GetData(gpu_timer.queries[index].end, &frame_end_t, size_of(frame_end_t), 0)

	freq := f64(frame_data.Frequency) / f64(time.Second)
	work_time = time.Duration(f64(frame_end_t - frame_start_t) / freq)

	return work_time, true
}
