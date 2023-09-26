package timer

import "core:time"

wait :: proc(interval: time.Duration, cycle_start: time.Tick) {
	end := time.tick_since(cycle_start)

	// In a situation where simulation consistently takes too long, sleep interval will be less than zero.
	// Which means it won't sleep at all, thus running the simulation as fast as possible.
	// With this approach, simulation will instead always wait for multiples of an interval.
	// So instead of having all-over-the-place timings, it will just slow down by N.
	to_sleep := interval - (end % interval)
	// To go back to all-over-the-place timings do this instead:
	// to_sleep := interval - end

	time.accurate_sleep(to_sleep)
}

// Turns tick rate into cycle time, e.g. 60 -> 16.6ms
tick_duration_from_rate :: proc(tick_rate: uint) -> time.Duration {
	return time.Duration(f32(time.Second) * (1 / f32(tick_rate)))
}
