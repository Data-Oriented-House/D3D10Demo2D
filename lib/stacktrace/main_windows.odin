package stacktrace

// https://github.com/DaseinPhaos/pdb
import "pdb-f3314d5/pdb"

_setup :: proc() {
	pdb.SetUnhandledExceptionFilter(pdb.dump_stack_trace_on_exception)
}
