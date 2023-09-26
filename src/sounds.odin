package main

import "core:fmt"

import ma "vendor:miniaudio"

Sounds :: enum {
	Boom,
	Reconstruction_Science,
}

Sound_State :: enum {
	Stopped,
	Playing,
	Paused,
}

Sound_Info :: struct {
	name: cstring,
	data: []byte,
	sound: ma.sound,
	state: Sound_State,
}

Sounds_Context :: struct {
	resource_manager: ma.resource_manager,
	engine: ma.engine,
	info: [Sounds]Sound_Info,
}
sounds: Sounds_Context

sound_play :: proc(sound: Sounds) {
	info := &sounds.info[sound]
	if info.state == .Stopped {
		// ma.sound_init_from_file(&sounds.engine, info.name, auto_cast ma.sound_flags. DECODE, nil, nil, &info.sound)
	}
	ma.sound_start(&info.sound)
	info.state = .Playing
}

sound_pause :: proc(sound: Sounds) {
	info := &sounds.info[sound]
	ma.sound_stop(&info.sound)
	info.state = .Paused
}

sound_stop :: proc(sound: Sounds) {
	info := &sounds.info[sound]
	ma.sound_stop(&info.sound)
	ma.sound_seek_to_pcm_frame(&info.sound, 0)

	// ma.sound_uninit(&info.sound)

	sounds.info[sound].state = .Stopped
}

sound_restart :: proc(sound: Sounds) {
	info := &sounds.info[sound]

	if info.state == .Stopped {
		sound_play(sound)
		return
	}

	ma.sound_seek_to_pcm_frame(&info.sound, 0)
	ma.sound_start(&info.sound)
	info.state = .Playing
}

sound_state :: proc(sound: Sounds) -> Sound_State {
	return sounds.info[sound].state
}
