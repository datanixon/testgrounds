class_name MusicSeq
extends RefCounted
## Pure music sequencer + waveform math — the parity-locked core of the audio port.
## events_for_step reproduces game.js musicTick's note selection for one 16th-note
## step; gen_wave builds one cycle of a named waveform. No nodes, no randomness —
## the Audio autoload turns these events/buffers into sound.

const Tracks = preload("res://data/tracks.gd")

## events_for_step — the list of voice events to play on global 16th step `step`
## for track `track_index`. Mirrors musicTick exactly. Each event is a Dictionary
## tagged by "kind": "kick"/"snare"/"hat"/"bass"/"synth".
static func events_for_step(step: int, track_index: int) -> Array:
	var out: Array = []
	var track: Dictionary = Tracks.TRACKS[track_index] if track_index >= 0 and track_index < Tracks.TRACKS.size() else Tracks.TRACKS[0]
	var chords: Array = track["chords"]
	var bar: int = (step / 16) % chords.size()
	var beat: int = step % 16
	var chord: Dictionary = chords[bar]
	var notes := [chord["root"], chord["third"], chord["fifth"]]

	# drums
	if beat == 0 or beat == 8:
		out.append({"kind": "kick", "gain": 0.5})
	if beat == 4 or beat == 12:
		out.append({"kind": "snare", "gain": 0.22})
	if beat % 2 == 0:
		out.append({"kind": "hat", "gain": 0.10 if beat % 4 == 2 else 0.06})

	# bass (downbeats + walking offbeats)
	if beat == 0 or beat == 8:
		out.append({"kind": "bass", "freq": chord["root"], "dur": 0.42, "gain": 0.22, "sweep": 2400.0})
	elif beat == 4:
		out.append({"kind": "bass", "freq": chord["fifth"] * 0.5, "dur": 0.28, "gain": 0.13, "sweep": 1600.0})
	elif beat == 12:
		out.append({"kind": "bass", "freq": chord["third"] * 0.5, "dur": 0.28, "gain": 0.13, "sweep": 1600.0})

	# arp (every 16th, triangle, *2 octave)
	var arp_note: float = notes[int(track["arp"][beat]) % notes.size()] * 2.0
	out.append({"kind": "synth", "freq": arp_note, "wave": "triangle", "dur": 0.14, "gain": 0.05, "filter": 4000.0, "attack": 0.05, "reverb": 0.18})

	# pad (bar downbeat: saw *2 + sine *4 for each chord note)
	if beat == 0:
		for n in notes:
			out.append({"kind": "synth", "freq": n * 2.0, "wave": "sawtooth", "dur": 1.8, "gain": 0.028, "filter": 1100.0, "attack": 0.04, "reverb": 0.45})
		for n in notes:
			out.append({"kind": "synth", "freq": n * 4.0, "wave": "sine", "dur": 1.8, "gain": 0.014, "filter": 4000.0, "attack": 0.04, "reverb": 0.35})

	# lead (saw, from track.lead[bar] where s == beat)
	for ln in track["lead"][bar]:
		if int(ln["s"]) == beat:
			out.append({"kind": "synth", "freq": float(ln["hz"]), "wave": "sawtooth", "dur": 0.50, "gain": 0.07, "filter": 1900.0, "attack": 0.06, "reverb": 0.55})

	return out

## gen_wave — one cycle of `wave` over `length` samples, amplitude ±1.
static func gen_wave(wave: String, length: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(length)
	for i in range(length):
		var phase := float(i) / float(length)   # 0..1
		var v := 0.0
		match wave:
			"square":
				v = 1.0 if phase < 0.5 else -1.0
			"sawtooth":
				v = 2.0 * phase - 1.0
			"triangle":
				# peaks +1 at phase 0.25, -1 at 0.75 (matches the gen_wave test)
				if phase < 0.25:
					v = 4.0 * phase
				elif phase < 0.75:
					v = 2.0 - 4.0 * phase
				else:
					v = 4.0 * phase - 4.0
			"sine":
				v = sin(phase * TAU)
			_:
				v = sin(phase * TAU)
		out[i] = v
	return out
