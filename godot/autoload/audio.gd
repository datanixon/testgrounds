extends Node
## M10 Audio singleton (autoload). Owns Godot audio nodes: Music + SFX buses with
## a native reverb, procedurally-generated waveform streams, a voice pool of
## AudioStreamPlayers driven by Tween volume envelopes, and a Timer sequencer that
## plays MusicSeq.events_for_step each 16th note. Ports game.js sec. 15. Headless-safe
## (dummy audio driver: play() is a no-op, no crash). (No class_name: autoload node.)

const MusicSeq = preload("res://core/music_seq.gd")
const Tracks = preload("res://data/tracks.gd")
const SettingsStore = preload("res://core/settings_store.gd")

const MIX_RATE := 44100
const CYCLE := 200                       # samples per generated cycle
const BASE_FREQ := float(MIX_RATE) / float(CYCLE)   # 220.5 Hz reference pitch
const MUSIC_VOICES := 24
const SFX_VOICES := 8

var _streams := {}                       # wave name -> AudioStreamWAV
var _noise: AudioStreamWAV
var _music_pool: Array[AudioStreamPlayer] = []
var _sfx_pool: Array[AudioStreamPlayer] = []
var _voice_tweens := {}   # AudioStreamPlayer -> Tween (kill the old before reusing a voice)
var _seq_timer: Timer
var _step := 0
var track_index := 0
var music_on := true
var _music_vol := 0.6
var _sfx_vol := 0.6
var _duck := 1.0

func _ready() -> void:
	_setup_buses()
	_build_streams()
	_build_pools()
	_seq_timer = Timer.new()
	_seq_timer.wait_time = 0.17           # ~88 BPM 16ths (setInterval(musicTick,170))
	_seq_timer.one_shot = false
	_seq_timer.timeout.connect(_on_tick)
	add_child(_seq_timer)
	apply_settings(SettingsStore.load_blob())

func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var mi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(mi, "Music")
		AudioServer.set_bus_send(mi, "Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.6
		rev.wet = 0.30
		rev.dry = 0.85
		AudioServer.add_bus_effect(mi, rev)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 6000.0
		AudioServer.add_bus_effect(mi, lp)
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		var si := AudioServer.bus_count - 1
		AudioServer.set_bus_name(si, "SFX")
		AudioServer.set_bus_send(si, "Master")

## _wav_from_samples — pack a ±1 float buffer into a looping 16-bit mono AudioStreamWAV.
func _wav_from_samples(samples: PackedFloat32Array, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _build_streams() -> void:
	for w in ["square", "triangle", "sawtooth", "sine"]:
		_streams[w] = _wav_from_samples(MusicSeq.gen_wave(w, CYCLE), true)
	# noise buffer for drums (seeded — deterministic, non-looping one-shot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var n := PackedFloat32Array()
	n.resize(MIX_RATE)        # 1s of noise
	for i in range(n.size()):
		n[i] = rng.randf_range(-1.0, 1.0)
	_noise = _wav_from_samples(n, false)

func _build_pools() -> void:
	for i in range(MUSIC_VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music_pool.append(p)
	for i in range(SFX_VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

func _free_voice(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]   # steal the oldest if all busy

## _voice_tween — start a fresh tween on player `p`, killing any tween still
## animating it (so a stolen voice doesn't get its old stop()-callback fired).
func _voice_tween(p: AudioStreamPlayer) -> Tween:
	if _voice_tweens.has(p) and is_instance_valid(_voice_tweens[p]):
		_voice_tweens[p].kill()
	var tw := create_tween()
	_voice_tweens[p] = tw
	return tw

## _play_voice — play `stream` at `freq` with a linear-attack / decay envelope on
## the given pool. peak is a linear gain; converted to dB. Mirrors the JS osc+gain.
func _play_voice(pool: Array[AudioStreamPlayer], stream: AudioStream, freq: float, peak: float, dur: float, attack: float) -> void:
	if peak <= 0.0:
		return
	var p := _free_voice(pool)
	p.stream = stream
	p.pitch_scale = clampf(freq / BASE_FREQ, 0.05, 16.0)
	p.volume_db = -60.0
	p.play()
	var tw := _voice_tween(p)
	tw.tween_property(p, "volume_db", linear_to_db(peak), max(attack, 0.001))
	tw.tween_property(p, "volume_db", -60.0, max(dur - attack, 0.02))
	tw.tween_callback(p.stop)

func _on_tick() -> void:
	if not music_on:
		return
	var events := MusicSeq.events_for_step(_step, track_index)
	_step += 1
	for e in events:
		_play_event(e)

func _play_event(e: Dictionary) -> void:
	var mv := _music_vol * _duck
	match e["kind"]:
		"synth":
			_play_voice(_music_pool, _streams[e["wave"]], e["freq"], e["gain"] * mv, e["dur"], e["attack"])
		"bass":
			_play_voice(_music_pool, _streams["sawtooth"], e["freq"], e["gain"] * mv, e["dur"], 0.005)
		"kick":
			_play_drum_kick(e["gain"] * mv)
		"snare":
			_play_drum_noise(e["gain"] * mv, 0.13, 3.0)
		"hat":
			_play_drum_noise(e["gain"] * mv, 0.04, 8.0)

func _play_drum_kick(peak: float) -> void:
	if peak <= 0.0:
		return
	var p := _free_voice(_music_pool)
	p.stream = _streams["sine"]
	p.pitch_scale = clampf(110.0 / BASE_FREQ, 0.05, 16.0)
	p.volume_db = linear_to_db(peak)
	p.play()
	var tw := _voice_tween(p)
	tw.parallel().tween_property(p, "pitch_scale", clampf(40.0 / BASE_FREQ, 0.05, 16.0), 0.08)
	tw.parallel().tween_property(p, "volume_db", -60.0, 0.22)
	tw.chain().tween_callback(p.stop)

## _play_drum_noise — noise burst (snare/hat). `pitch` raises the noise stream's
## pitch_scale to brighten it (cheap stand-in for the JS band/high-pass).
func _play_drum_noise(peak: float, dur: float, pitch: float) -> void:
	if peak <= 0.0:
		return
	var p := _free_voice(_music_pool)
	p.stream = _noise
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(peak)
	p.play()
	var tw := _voice_tween(p)
	tw.tween_property(p, "volume_db", -60.0, dur)
	tw.tween_callback(p.stop)

# ---- public API (mirrors game.js) ----

func beep(freq: float, dur: float, wave := "square", gain := 0.1) -> void:
	var peak := gain * _sfx_vol
	if peak <= 0.0:
		return
	_play_voice(_sfx_pool, _streams.get(wave, _streams["square"]), freq, peak, dur, 0.005)

## fanfare — play a short multi-note SFX sequence (each {freq,dur,wave,gain,delay}).
func fanfare(notes: Array) -> void:
	for nd in notes:
		var d: float = nd.get("delay", 0.0)
		if d <= 0.0:
			beep(nd["freq"], nd["dur"], nd.get("wave", "triangle"), nd.get("gain", 0.2))
		else:
			get_tree().create_timer(d).timeout.connect(
				func(): beep(nd["freq"], nd["dur"], nd.get("wave", "triangle"), nd.get("gain", 0.2)))

func duck(level: float) -> void:
	_duck = clampf(level, 0.0, 1.0)
	_apply_music_volume()

func start_music() -> void:
	music_on = true
	if _seq_timer != null and _seq_timer.is_stopped():
		_seq_timer.start()

func stop_music() -> void:
	music_on = false
	if _seq_timer != null:
		_seq_timer.stop()

func toggle_music() -> void:
	if music_on:
		stop_music()
	else:
		start_music()

func cycle_track() -> String:
	track_index = (track_index + 1) % Tracks.TRACKS.size()
	_step = 0
	return Tracks.TRACKS[track_index]["name"]

func set_music_vol(v: float) -> void:
	_music_vol = clampf(v, 0.0, 1.0)
	_apply_music_volume()

func set_sfx_vol(v: float) -> void:
	_sfx_vol = clampf(v, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("SFX")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(_sfx_vol, 0.0001)))
		AudioServer.set_bus_mute(idx, _sfx_vol <= 0.0)

func _apply_music_volume() -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx != -1:
		var v := _music_vol * _duck
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.0)

func apply_settings(s: Dictionary) -> void:
	track_index = clampi(int(s.get("track_index", 0)), 0, Tracks.TRACKS.size() - 1)
	music_on = bool(s.get("music_on", true))
	set_music_vol(float(s.get("music_vol", 0.6)))
	set_sfx_vol(float(s.get("sfx_vol", 0.6)))
	if music_on:
		start_music()
	else:
		stop_music()

func current_track_name() -> String:
	return Tracks.TRACKS[track_index]["name"]
