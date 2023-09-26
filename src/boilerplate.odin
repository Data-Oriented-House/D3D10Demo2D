package main

import "core:os"
import "core:log"
import "core:fmt"
import "core:time"
import "core:mem"
import "core:runtime"

import "lib:msgbox"
import "lib:spall"
import "lib:stacktrace"

// You can use this directly to ignore the tracking allocator (for things I want to allocate but don't care about freeing)
heap_allocator := runtime.default_allocator()
// NOTE: Used by default in debug builds
tracking_allocator: mem.Tracking_Allocator
// This allocator will be tracked in debug mode; otherwise it is equivalent to heap_allocator
program_allocator: runtime.Allocator
// For actual unrecoverable errors
exception: Maybe(string)

main :: proc() {
	program_allocator = heap_allocator
	when ODIN_DEBUG {
		stacktrace.setup()
		mem.tracking_allocator_init(&tracking_allocator, heap_allocator)
		program_allocator = mem.tracking_allocator(&tracking_allocator)
	}

	context = setup_context()

	spall.init("perf.spall")
	spall.thread_init()
	start()
	spall.thread_finish()
	spall.finish()
	log_leaked_memory()

	if error, bad := exception.?; bad {
		log.fatal(error)
	}
}

setup_context :: proc "contextless" () -> (ctx: runtime.Context) {
	ctx = runtime.default_context()
	ctx.allocator = program_allocator
	ctx.assertion_failure_proc = assertion_failure_proc
	ctx.logger.procedure = logger_proc
	return
}

@(disabled=!ODIN_DEBUG)
log_leaked_memory :: proc() {
	for _, leak in tracking_allocator.allocation_map {
		log.infof("%v leaked %v bytes", leak.location, leak.size)
	}

	for bf in tracking_allocator.bad_free_array {
		log.infof("%v allocation %p was freed badly", bf.location, bf.memory)
	}
}

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	error := fmt.tprintf("{}({}:{}) {}", loc.file_path, loc.line, loc.column, prefix)
	if len(message) > 0 {
		error = fmt.tprintf("{}: {}", error, message)
	}

	fmt.eprintln(error)
	when !ODIN_DEBUG {
		msgbox.show(.Error, "Error!", fmt.tprintf("{}: {}", prefix, message))
	}
	os.exit(1)
}

logger_proc :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
	if level == .Fatal {
		fmt.eprintf("[{}] {}\n", level, text)
		when !ODIN_DEBUG {
			msgbox.show(.Error, "Error!", text)
		}
		os.exit(1)
	} else if level == .Info {
		fmt.eprintf("{}\n", text)
	} else {
		fmt.eprintf("[{}] {}\n", level, text)
	}
}

array_cast :: proc "contextless" ($Elem_Type: typeid, v: [$N]$T) -> (w: [N]Elem_Type) #no_bounds_check {
	for i in 0..<N {
		w[i] = Elem_Type(v[i])
	}
	return
}
