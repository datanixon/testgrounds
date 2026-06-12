# Wraithspire Godot M10 — Audio (procedural synth + SFX → parity) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the JS procedural audio engine (6-track synth score + drums + reverb + per-event SFX) to Godot and wire the music/sfx volume settings M9 left inert, plus music on/off and track cycle.

**Architecture:** A pure harness-testable core (`data/tracks.gd` = the 6 TRACKS verbatim; `core/music_seq.gd` = `events_for_step` note-selection + `gen_wave` waveform math) drives a presentation autoload (`autoload/audio.gd`) that owns Godot audio nodes: Music/SFX buses with a native `AudioEffectReverb`, procedurally-generated waveform `AudioStreamWAV`s, a voice pool of `AudioStreamPlayer`s with `Tween` envelopes, and a `Timer` sequencer. Integration wires the M9 settings overlay, battle ducking, and per-event SFX.

**Tech Stack:** Godot 4.6.3 GDScript; `AudioServer` buses + effects; `AudioStreamWAV` (generated PCM); `AudioStreamPlayer` + `Tween`; headless harness `pwsh -File godot/tests/run_tests.ps1`.

**Spec:** `docs/superpowers/specs/2026-06-11-wraithspire-godot-m10-audio-design.md`
**Reference:** `game.js` sec. 15 (`musicTick`/`playSynth`/`playBass`/`playKick`/`playSnare`/`playHihat`/`beep`/`TRACKS`/`musicDuck`).

---

## Conventions (every task)

- **Harness gate:** `pwsh -File godot/tests/run_tests.ps1` → last line `== N passed, 0 failed ==`, EXIT 0. NO `-ExecutionPolicy Bypass`.
- **Headless-boot gate** (after any scene/autoload/`project.godot`/`main` change): `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches. (Run from a PowerShell context; the `Audio` autoload `_ready` runs for real under the headless dummy audio driver — it must not crash.)
- New harness tests live in `godot/tests/run_tests.gd`: a `const` preload near the top, a `_test_xxx()` method, a call in `_initialize()`. Helpers `_ok(cond,msg)` / `_eq(got,want,msg)`. For float compares use a tolerance helper (added in Task 2).
- New scripts declare `class_name` so the harness parse-checks them.
- Commit after each task: `git add <files> && git commit -m "[godot] M10 audio task N: <summary>"` (end body with the Co-Authored-By trailer).

## File structure (created / modified)

| File | Responsibility |
|------|----------------|
| `data/tracks.gd` (new) | 6 `TRACKS` ported verbatim |
| `core/music_seq.gd` (new) | pure `events_for_step` + `gen_wave` |
| `core/settings_store.gd` (edit) | + `music_on`, `track_index` |
| `autoload/audio.gd` (new) | Audio singleton: buses/streams/voices/sequencer/SFX/duck/vol |
| `project.godot` (edit) | register `Audio` autoload |
| `scenes/hud/settings_panel.gd` (edit) | wire vol → Audio; add MUSIC ON/OFF + TRACK cycler |
| `scenes/battle/battle_scene.gd` (edit) | duck on play / restore on finish |
| `scenes/match/match_scene.gd` (edit) | SFX at battle/summon/capture/ability/win |
| `scenes/title/title_scene.gd`, `scenes/hud/settings_panel.gd` (edit) | menu-click SFX |
| `tests/run_tests.gd` (edit) | `_test_tracks`, `_test_music_seq`, `_test_gen_wave`, extend `_test_settings` |

---

## Task 1: Tracks data

**Files:**
- Create: `godot/data/tracks.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

In `run_tests.gd` add preload near the others:
```gdscript
const Tracks = preload("res://data/tracks.gd")
```
Call in `_initialize()`:
```gdscript
	_test_tracks()
```
Method:
```gdscript
func _test_tracks() -> void:
	_eq(Tracks.TRACKS.size(), 6, "tracks: 6 tracks")
	var t0: Dictionary = Tracks.TRACKS[0]
	_eq(t0["name"], "WRAITHSPIRE FRONTIER", "tracks: t0 name")
	_eq(t0["chords"].size(), 4, "tracks: t0 has 4 chords")
	_eq(t0["chords"][0], {"root": 110.00, "third": 130.81, "fifth": 164.81}, "tracks: t0 Am chord")
	_eq(t0["arp"], [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 0, 2, 1, 2], "tracks: t0 arp")
	_eq(t0["arp"].size(), 16, "tracks: arp is 16 steps")
	_eq(t0["lead"][0][0], {"s": 4, "hz": 440.0}, "tracks: t0 lead bar0 note0")
	_eq(Tracks.TRACKS[5]["name"], "HEX STORM", "tracks: t5 name")
	# every track: 4 chords, 16-step arp, 4 lead bars
	for t in Tracks.TRACKS:
		_eq(t["chords"].size(), 4, "tracks: 4 chords each")
		_eq(t["arp"].size(), 16, "tracks: 16-step arp each")
		_eq(t["lead"].size(), 4, "tracks: 4 lead bars each")
```

- [ ] **Step 2: Run harness, verify fail**

Run: `pwsh -File godot/tests/run_tests.ps1` → FAIL (`Could not load res://data/tracks.gd`), EXIT 1.

- [ ] **Step 3: Implement `data/tracks.gd`** (verbatim port of `game.js` TRACKS)

```gdscript
class_name Tracks
extends RefCounted
## Port of game.js TRACKS (sec. 15) — 6 original 80s-dark-synth-fantasy loops.
## Each: name, chords (4 × {root,third,fifth} Hz), arp (16 step indices into the
## 3-note chord), lead (4 bars × [{s: step, hz}]). Numbers are a 1:1 copy of the JS.

const TRACKS := [
	{
		"name": "WRAITHSPIRE FRONTIER",
		"chords": [
			{"root": 110.00, "third": 130.81, "fifth": 164.81},
			{"root": 87.31, "third": 110.00, "fifth": 130.81},
			{"root": 65.41, "third": 82.41, "fifth": 98.00},
			{"root": 98.00, "third": 123.47, "fifth": 146.83},
		],
		"arp": [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 0, 2, 1, 2],
		"lead": [
			[{"s": 4, "hz": 440.0}, {"s": 8, "hz": 523.25}, {"s": 12, "hz": 392.0}],
			[{"s": 0, "hz": 349.23}, {"s": 8, "hz": 440.0}],
			[{"s": 4, "hz": 392.0}, {"s": 10, "hz": 329.63}, {"s": 14, "hz": 261.63}],
			[{"s": 2, "hz": 293.66}, {"s": 8, "hz": 392.0}, {"s": 12, "hz": 440.0}],
		],
	},
	{
		"name": "SHADOW VEIL",
		"chords": [
			{"root": 73.42, "third": 87.31, "fifth": 110.00},
			{"root": 58.27, "third": 73.42, "fifth": 87.31},
			{"root": 87.31, "third": 110.00, "fifth": 130.81},
			{"root": 65.41, "third": 82.41, "fifth": 98.00},
		],
		"arp": [2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1],
		"lead": [
			[{"s": 0, "hz": 293.66}, {"s": 8, "hz": 349.23}, {"s": 12, "hz": 440.0}],
			[{"s": 4, "hz": 466.16}, {"s": 10, "hz": 392.0}],
			[{"s": 0, "hz": 349.23}, {"s": 8, "hz": 261.63}],
			[{"s": 4, "hz": 261.63}, {"s": 8, "hz": 311.13}, {"s": 14, "hz": 233.08}],
		],
	},
	{
		"name": "IRON CATACOMBS",
		"chords": [
			{"root": 82.41, "third": 98.00, "fifth": 123.47},
			{"root": 65.41, "third": 82.41, "fifth": 98.00},
			{"root": 98.00, "third": 123.47, "fifth": 146.83},
			{"root": 73.42, "third": 92.50, "fifth": 110.00},
		],
		"arp": [0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2],
		"lead": [
			[{"s": 0, "hz": 329.63}, {"s": 6, "hz": 392.0}, {"s": 12, "hz": 493.88}],
			[{"s": 4, "hz": 523.25}, {"s": 10, "hz": 392.0}],
			[{"s": 2, "hz": 587.33}, {"s": 8, "hz": 493.88}, {"s": 12, "hz": 392.0}],
			[{"s": 0, "hz": 440.0}, {"s": 8, "hz": 369.99}, {"s": 14, "hz": 293.66}],
		],
	},
	{
		"name": "PYRE OF STARS",
		"chords": [
			{"root": 110.00, "third": 130.81, "fifth": 164.81},
			{"root": 98.00, "third": 123.47, "fifth": 146.83},
			{"root": 87.31, "third": 110.00, "fifth": 130.81},
			{"root": 82.41, "third": 98.00, "fifth": 123.47},
		],
		"arp": [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1],
		"lead": [
			[{"s": 0, "hz": 440.0}, {"s": 6, "hz": 523.25}, {"s": 12, "hz": 659.25}],
			[{"s": 0, "hz": 587.33}, {"s": 8, "hz": 392.0}],
			[{"s": 0, "hz": 523.25}, {"s": 6, "hz": 440.0}, {"s": 12, "hz": 349.23}],
			[{"s": 0, "hz": 329.63}, {"s": 4, "hz": 246.94}, {"s": 12, "hz": 329.63}],
		],
	},
	{
		"name": "TOWER WATCH",
		"chords": [
			{"root": 65.41, "third": 77.78, "fifth": 98.00},
			{"root": 98.00, "third": 116.54, "fifth": 146.83},
			{"root": 51.91, "third": 65.41, "fifth": 77.78},
			{"root": 58.27, "third": 73.42, "fifth": 87.31},
		],
		"arp": [0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2],
		"lead": [
			[{"s": 4, "hz": 261.63}, {"s": 12, "hz": 311.13}],
			[{"s": 0, "hz": 391.99}, {"s": 8, "hz": 466.16}],
			[{"s": 4, "hz": 415.31}, {"s": 12, "hz": 311.13}],
			[{"s": 0, "hz": 349.23}, {"s": 8, "hz": 466.16}, {"s": 14, "hz": 392.0}],
		],
	},
	{
		"name": "HEX STORM",
		"chords": [
			{"root": 82.41, "third": 98.00, "fifth": 123.47},
			{"root": 61.74, "third": 73.42, "fifth": 92.50},
			{"root": 65.41, "third": 82.41, "fifth": 98.00},
			{"root": 98.00, "third": 123.47, "fifth": 146.83},
		],
		"arp": [0, 2, 1, 2, 1, 0, 1, 2, 0, 2, 1, 2, 1, 0, 1, 2],
		"lead": [
			[{"s": 2, "hz": 329.63}, {"s": 6, "hz": 493.88}, {"s": 10, "hz": 587.33}, {"s": 14, "hz": 392.0}],
			[{"s": 0, "hz": 493.88}, {"s": 6, "hz": 587.33}, {"s": 12, "hz": 369.99}],
			[{"s": 4, "hz": 523.25}, {"s": 8, "hz": 659.25}, {"s": 14, "hz": 392.0}],
			[{"s": 0, "hz": 587.33}, {"s": 8, "hz": 392.0}, {"s": 12, "hz": 493.88}],
		],
	},
]
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**

```bash
git add godot/data/tracks.gd godot/tests/run_tests.gd
git commit -m "[godot] M10 audio task 1: Tracks data (6 TRACKS verbatim)"
```

---

## Task 2: MusicSeq — events_for_step + gen_wave (pure)

**Files:**
- Create: `godot/core/music_seq.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test** (+ a float-tolerance helper)

Add the preload:
```gdscript
const MusicSeq = preload("res://core/music_seq.gd")
```
Add a float-approx helper near `_eq` (used here and later):
```gdscript
func _approx(got: float, want: float, msg: String) -> void:
	_ok(absf(got - want) < 0.01, "%s  (got %f, want %f)" % [msg, got, want])
```
Call in `_initialize()`:
```gdscript
	_test_music_seq()
	_test_gen_wave()
```
Methods:
```gdscript
func _test_music_seq() -> void:
	# step 0, track 0 (bar 0 = Am root 110): kick + hat(accent? beat0%4==0 -> 0.06) + bass + arp + pad(6) ; lead bar0 has no s==0
	var e0 := MusicSeq.events_for_step(0, 0)
	var kinds0 := {}
	for e in e0:
		kinds0[e["kind"]] = kinds0.get(e["kind"], 0) + 1
	_eq(kinds0.get("kick", 0), 1, "seq: step0 has a kick")
	_eq(kinds0.get("hat", 0), 1, "seq: step0 has a hat")
	_eq(kinds0.get("bass", 0), 1, "seq: step0 has a bass")
	_eq(kinds0.get("synth", 0), 1 + 6, "seq: step0 arp(1) + pad(6) synths")  # arp + 3 saw + 3 sine
	# bass freq on the downbeat == chord root
	for e in e0:
		if e["kind"] == "bass":
			_approx(e["freq"], 110.0, "seq: step0 bass = root 110")
	# step 4: snare + hat(beat4%4==0 ->0.06) + bass-walk(fifth*0.5) + arp; lead bar0 s==4 -> 440
	var e4 := MusicSeq.events_for_step(4, 0)
	var kinds4 := {}
	for e in e4:
		kinds4[e["kind"]] = kinds4.get(e["kind"], 0) + 1
	_eq(kinds4.get("snare", 0), 1, "seq: step4 snare")
	_ok(kinds4.get("kick", 0) == 0, "seq: step4 no kick")
	var has_lead := false
	for e in e4:
		if e["kind"] == "synth" and absf(e["freq"] - 440.0) < 0.01:
			has_lead = true
	_ok(has_lead, "seq: step4 lead note 440")
	# step 2: hat accent (beat2%4==2 -> 0.10), arp only among drums; no kick/snare/bass
	var e2 := MusicSeq.events_for_step(2, 0)
	var hat_gain := -1.0
	var has_bass2 := false
	for e in e2:
		if e["kind"] == "hat":
			hat_gain = e["gain"]
		if e["kind"] == "bass":
			has_bass2 = true
	_approx(hat_gain, 0.10, "seq: step2 hat accent gain 0.10")
	_ok(not has_bass2, "seq: step2 no bass")
	# odd step 1: no drums, just arp (beat%2==1 -> no hat)
	var e1 := MusicSeq.events_for_step(1, 0)
	var only := {}
	for e in e1:
		only[e["kind"]] = only.get(e["kind"], 0) + 1
	_eq(only.get("hat", 0), 0, "seq: step1 no hat (odd beat)")
	_eq(only.get("synth", 0), 1, "seq: step1 arp only")
	# bar rollover: step 16 is bar 1 (chord index 1). track0 bar1 root = 87.31
	var e16 := MusicSeq.events_for_step(16, 0)
	for e in e16:
		if e["kind"] == "bass":
			_approx(e["freq"], 87.31, "seq: step16 bass = bar1 root 87.31")

func _test_gen_wave() -> void:
	var sq := MusicSeq.gen_wave("square", 200)
	_eq(sq.size(), 200, "gen_wave: length 200")
	_approx(sq[10], 1.0, "gen_wave: square first half +1")
	_approx(sq[120], -1.0, "gen_wave: square second half -1")
	var sine := MusicSeq.gen_wave("sine", 200)
	_approx(sine[0], 0.0, "gen_wave: sine starts at 0")
	_approx(sine[50], 1.0, "gen_wave: sine quarter +1")
	var saw := MusicSeq.gen_wave("sawtooth", 200)
	_ok(saw[0] < saw[100] and saw[100] < saw[199], "gen_wave: saw rises")
	var tri := MusicSeq.gen_wave("triangle", 200)
	_approx(tri[50], 1.0, "gen_wave: triangle peak at quarter")
	# all bounded to ±1
	for w in ["square", "triangle", "sawtooth", "sine"]:
		for s in MusicSeq.gen_wave(w, 64):
			_ok(s >= -1.0001 and s <= 1.0001, "gen_wave: %s bounded" % w)
```

- [ ] **Step 2: Run harness, verify fail**

Run: `pwsh -File godot/tests/run_tests.ps1` → FAIL (`Could not load res://core/music_seq.gd`), EXIT 1.

- [ ] **Step 3: Implement `core/music_seq.gd`**

```gdscript
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
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**

```bash
git add godot/core/music_seq.gd godot/tests/run_tests.gd
git commit -m "[godot] M10 audio task 2: MusicSeq events_for_step + gen_wave (pure)"
```

---

## Task 3: SettingsStore — music_on + track_index

**Files:**
- Modify: `godot/core/settings_store.gd`
- Modify: `godot/tests/run_tests.gd`

- [ ] **Step 1: Write the failing test** — extend `_test_settings()` (already exists). Append:

```gdscript
	# M10: music_on default true, track_index default 0, clamped to track range
	var dd := SettingsStore.defaults()
	_eq(dd.get("music_on"), true, "settings: default music_on")
	_eq(dd.get("track_index"), 0, "settings: default track_index")
	var m2 := SettingsStore.merge(dd, {"music_on": false, "track_index": 3})
	_eq(m2["music_on"], false, "settings: merge music_on")
	_eq(m2["track_index"], 3, "settings: merge track_index")
	var m3 := SettingsStore.merge(dd, {"track_index": 99})
	_eq(m3["track_index"], Tracks.TRACKS.size() - 1, "settings: track_index clamped to last")
	var m4 := SettingsStore.merge(dd, {"music_on": "yes"})
	_eq(m4["music_on"], true, "settings: bad music_on keeps default")
```

- [ ] **Step 2: Run harness, verify fail**

Run: `pwsh -File godot/tests/run_tests.ps1` → FAIL (`default music_on` / `track_index`), EXIT 1.

- [ ] **Step 3: Extend `core/settings_store.gd`**

Add the Tracks preload near the existing `Maps`/`AiProfiles`/`Campaign` preloads:
```gdscript
const Tracks = preload("res://data/tracks.gd")
```
In `defaults()`, add the two keys:
```gdscript
	return {
		"music_vol": 0.6, "sfx_vol": 0.6, "battle_scene": true,
		"difficulty": "normal", "map_index": 0, "campaign_progress": 0,
		"music_on": true, "track_index": 0,
	}
```
In `merge()`, before the final `return out`, add:
```gdscript
	if typeof(saved.get("music_on")) == TYPE_BOOL:
		out["music_on"] = saved["music_on"]
	if typeof(saved.get("track_index")) == TYPE_FLOAT or typeof(saved.get("track_index")) == TYPE_INT:
		out["track_index"] = clampi(int(saved["track_index"]), 0, Tracks.TRACKS.size() - 1)
```

- [ ] **Step 4: Run harness, verify pass**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.

- [ ] **Step 5: Commit**

```bash
git add godot/core/settings_store.gd godot/tests/run_tests.gd
git commit -m "[godot] M10 audio task 3: SettingsStore music_on + track_index"
```

---

## Task 4: Audio autoload

**Files:**
- Create: `godot/autoload/audio.gd`
- Modify: `godot/project.godot`

This is presentation (audio nodes); the pure logic it calls (`MusicSeq`, `gen_wave`) is already tested in Tasks 1-2. Verification here = the harness still green + the headless-boot gate clean (the autoload `_ready` runs for real under the dummy audio driver and must not crash).

- [ ] **Step 1: Implement `autoload/audio.gd`**

```gdscript
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
	var tw := create_tween()
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
	var tw := create_tween()
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
	var tw := create_tween()
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
```

- [ ] **Step 2: Register the autoload in `project.godot`**

Add an `[autoload]` section (after the `[application]` block):
```
[autoload]

Audio="*res://autoload/audio.gd"
```
(The `*` makes it a singleton accessible as `Audio` globally.)

- [ ] **Step 3: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → `== N passed, 0 failed ==`, EXIT 0.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → **no matches**. (The `Audio` autoload now loads at boot; its `_ready` builds buses + streams + pools + starts the sequencer Timer. Under the dummy audio driver the players' `play()` is a no-op — confirm NO errors. If `AudioServer.add_bus`/effects error headless, wrap the bus setup so failures are non-fatal, but they should be fine.)

- [ ] **Step 4: Commit**

```bash
git add godot/autoload/audio.gd godot/project.godot
git commit -m "[godot] M10 audio task 4: Audio autoload (buses/streams/voices/sequencer/SFX/duck)"
```

---

## Task 5: Wire settings overlay (vol live + music on/off + track cycle)

**Files:**
- Modify: `godot/scenes/hud/settings_panel.gd`

- [ ] **Step 1: Make the vol segments live + reflect state**

In `_set_vol`, after persisting, push to Audio:
```gdscript
func _set_vol(key: String, v: float) -> void:
	session.settings[key] = v
	SettingsStore.save_blob(session.settings)
	if key == "music_vol":
		Audio.set_music_vol(v)
	elif key == "sfx_vol":
		Audio.set_sfx_vol(v)
	_refresh()
```
Store the segment buttons so `_refresh` can fill them. Change `_add_vol_row` to keep references and tag each segment with its threshold; add a member dict:
```gdscript
var _vol_segs := {}   # key -> Array[Button]
```
In `_add_vol_row`, collect the buttons:
```gdscript
func _add_vol_row(vb: VBoxContainer, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	var segs: Array[Button] = []
	for i in range(10):
		var seg := Button.new()
		seg.custom_minimum_size = Vector2(16, 0)
		var v := (i + 1) / 10.0
		seg.pressed.connect(func(): _set_vol(key, v))
		row.add_child(seg)
		segs.append(seg)
	_vol_segs[key] = segs
	vb.add_child(row)
```
In `_refresh`, fill segments to the current value (filled "█" vs empty "·"):
```gdscript
	for key in _vol_segs:
		var val: float = session.settings.get(key, 0.6)
		var lit := int(round(val * 10.0))
		var segs: Array = _vol_segs[key]
		for i in range(segs.size()):
			segs[i].text = "█" if i < lit else "·"
```

- [ ] **Step 2: Add MUSIC ON/OFF + TRACK cycler to `_build`**

Add members:
```gdscript
var _music_on_btn: Button
var _music_off_btn: Button
var _track_label: Label
```
In `_build()`, after the battle-scene row (before the CLOSE button), add:
```gdscript
	# music on/off
	var mr := HBoxContainer.new()
	var ml := Label.new(); ml.text = "MUSIC"; ml.custom_minimum_size = Vector2(140, 0); mr.add_child(ml)
	_music_on_btn = Button.new(); _music_on_btn.text = "ON"; _music_on_btn.pressed.connect(func(): _set_music_on(true)); mr.add_child(_music_on_btn)
	_music_off_btn = Button.new(); _music_off_btn.text = "OFF"; _music_off_btn.pressed.connect(func(): _set_music_on(false)); mr.add_child(_music_off_btn)
	vb.add_child(mr)
	# track cycler
	var tr := HBoxContainer.new()
	var tl := Label.new(); tl.text = "TRACK"; tl.custom_minimum_size = Vector2(140, 0); tr.add_child(tl)
	var prevb := Button.new(); prevb.text = "◀"; prevb.pressed.connect(_cycle_track); tr.add_child(prevb)
	_track_label = Label.new(); _track_label.custom_minimum_size = Vector2(130, 0); tr.add_child(_track_label)
	var nextb := Button.new(); nextb.text = "▶"; nextb.pressed.connect(_cycle_track); tr.add_child(nextb)
	vb.add_child(tr)
```
(Both ◀ and ▶ cycle forward — the JS only cycles one direction; a single cycle action is parity-faithful.) Add the handlers:
```gdscript
func _set_music_on(on: bool) -> void:
	session.settings["music_on"] = on
	SettingsStore.save_blob(session.settings)
	if on:
		Audio.start_music()
	else:
		Audio.stop_music()
	_refresh()

func _cycle_track() -> void:
	var name := Audio.cycle_track()
	session.settings["track_index"] = Audio.track_index
	SettingsStore.save_blob(session.settings)
	_refresh()
```
Extend `_refresh` to reflect music-on + track name:
```gdscript
	if _music_on_btn != null and _music_off_btn != null:
		var on: bool = session.settings.get("music_on", true)
		_music_on_btn.disabled = on
		_music_off_btn.disabled = not on
	if _track_label != null:
		_track_label.text = Audio.current_track_name()
```
Also grow the panel so the new rows fit: in `_build`, change `_panel.size = Vector2(360, 240)` to `Vector2(360, 320)` and `_panel.position = Vector2(640 - 180, 400 - 160)`.

- [ ] **Step 3: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 4: Commit**

```bash
git add godot/scenes/hud/settings_panel.gd
git commit -m "[godot] M10 audio task 5: wire settings overlay — live vol + music on/off + track cycle"
```

---

## Task 6: Battle ducking

**Files:**
- Modify: `godot/scenes/battle/battle_scene.gd`

- [ ] **Step 1: Duck on play, restore on finish**

In `play(record)`, at the end of the function (after `queue_redraw()`), add:
```gdscript
	Audio.duck(0.35)
```
In `_process`, where the cutaway ends — the block that does `set_process(false); visible = false; finished.emit(); return` (the `if _phase == "done":` branch) — add `Audio.duck(1.0)` BEFORE `finished.emit()`:
```gdscript
			if _phase == "done":
				set_process(false)
				visible = false
				Audio.duck(1.0)
				finished.emit()
				return
```

- [ ] **Step 2: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/battle/battle_scene.gd
git commit -m "[godot] M10 audio task 6: battle cutaway ducks the music"
```

---

## Task 7: Per-event SFX

Wire `Audio.beep(...)` at the Godot game events, copying the exact `(freq, dur, wave, gain)` from the cited JS `beep()` call sites. `Audio` is a global autoload, so call it directly.

**Files:**
- Modify: `godot/scenes/match/match_scene.gd`
- Modify: `godot/scenes/battle/battle_scene.gd`
- Modify: `godot/scenes/title/title_scene.gd`
- Modify: `godot/scenes/hud/settings_panel.gd`

- [ ] **Step 1: Battle-start + impact SFX (`battle_scene.gd`)**

In `play(record)`, right after `Audio.duck(0.35)`, add the battle-start cue (JS game.js:1046 `beep(150,0.08,"square",0.18)`):
```gdscript
	Audio.beep(150.0, 0.08, "square", 0.18)
```
In `_process`, the phase-transition block sets `flash=1.0; shake=6.0` on `aCharge`/`cCharge` end — that's the impact moment. Add an impact thwack there (JS battle impact ≈ `beep(140..200,0.08,"square",0.18)`, game.js:2409):
```gdscript
				if _phase == "aCharge" or _phase == "cCharge":
					flash = 1.0
					shake = 6.0
					Audio.beep(170.0, 0.08, "square", 0.18)
```

- [ ] **Step 2: Match-event SFX (`match_scene.gd`)**

- **Summon** — in `_on_summon_chosen`, after `var u := state.spawn_unit(...)` (JS game.js:4646 `beep(660,0.08,"triangle",0.18)`):
```gdscript
	Audio.beep(660.0, 0.08, "triangle", 0.18)
```
- **Ability cast** — in `_arm_ability`, in the `"none"` (instant) branch after `AbilityResolve.resolve_instant(...)` (JS game.js:4274 `beep(700,0.1,"triangle",0.2)`):
```gdscript
	Audio.beep(700.0, 0.1, "triangle", 0.2)
```
- **Capture** — in `_on_action_chosen`, the `"capture"` branch after `state.capture_tower(...)` (JS game.js:1171 `beep(520,0.12,"triangle",0.18)`):
```gdscript
	Audio.beep(520.0, 0.12, "triangle", 0.18)
```
- **Win/lose fanfare** — in `_end_match`, after `match_ended.emit(...)` would be too late (scene swaps); put it at the START of `_end_match`, right after the `_match_over` guard sets true (JS game.js:1081-1082, ascending triangle):
```gdscript
	Audio.fanfare([
		{"freq": 440.0, "dur": 0.2, "wave": "triangle", "gain": 0.25},
		{"freq": 660.0, "dur": 0.3, "wave": "triangle", "gain": 0.25, "delay": 0.2},
	])
```

- [ ] **Step 3: Menu-click SFX (`title_scene.gd`, `settings_panel.gd`)**

- **Title clicks** — in `title_scene.gd` `_gui_input`, at the top of the handled mouse-click branch (after confirming it's a left press, before the rect tests), add a soft click (JS title click ≈ `beep(620,0.06,"triangle",0.15)`, game.js:4188):
```gdscript
	Audio.beep(620.0, 0.06, "triangle", 0.15)
```
(Place it once so any title button/selection clicks it; if that double-fires with begin_skirmish, acceptable — one short tick.)
- **Settings clicks** — in `settings_panel.gd`, add the same tick in `_set_vol`, `_set_bs`, `_set_music_on`, `_cycle_track` (JS settings click `beep(660,0.12,"triangle",0.18)`, game.js:3953). Add to each:
```gdscript
	Audio.beep(660.0, 0.06, "triangle", 0.15)
```

- [ ] **Step 4: Harness + boot gates**

Run: `pwsh -File godot/tests/run_tests.ps1` → green.
Run: `godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT ERROR|Parse Error|Failed to load"` → no matches.

- [ ] **Step 5: Commit**

```bash
git add godot/scenes/match/match_scene.gd godot/scenes/battle/battle_scene.gd godot/scenes/title/title_scene.gd godot/scenes/hud/settings_panel.gd
git commit -m "[godot] M10 audio task 7: per-event SFX (battle/summon/capture/ability/win/menu)"
```

**Deferred SFX (carry-forward):** level-up / evolution chime (game.js:2351-2352) — needs a level-up signal from `Combat`/`Units` that doesn't exist yet; wire when that signal is added. Logged, not shipped this milestone.

---

## Manual (windowed) verification — after Task 7

Headless can't render audio. Run `godot --path godot` and confirm by ear:
- Music plays at boot and loops; the 4-bar progression is audible (bass + arp + pad + drums).
- MUSIC VOL slider changes loudness live; SFX VOL changes click loudness; OFF silences each.
- MUSIC OFF stops the score; ON restarts it; TRACK ◀▶ cycles through the 6 named loops (label updates).
- Triggering a battle ducks the music for the cutaway, restores after.
- SFX fire: summon, attack (battle start + impact), capture, ability cast, win fanfare, menu clicks.

---

## Final milestone review

After Task 7: whole-sub-milestone opus review over `git diff <base>..HEAD -- godot/` (base = the commit before Task 1). Then:
- Update `ROADMAP_GODOT.md`: M10 is "Art + audio" — note **audio done; art pending assets** (don't fully check M10 until art ships).
- Update `SESSION_STATE.md`: audio complete; art is the only remaining port work, gated on a sprite batch from the art brief.
- Record accepted divergences (native reverb; single-bus reverb send; approximated bass sweep/drum filters; seeded noise; desktop autostart; level-up SFX deferred).

---

## Self-review notes (author)

- **Spec coverage:** Tracks data (T1) ✓; MusicSeq events + gen_wave (T2) ✓; settings music_on/track_index (T3) ✓; Audio autoload buses/streams/voices/sequencer/beep/duck/vol/cycle (T4) ✓; settings overlay wiring + music controls (T5) ✓; battle duck (T6) ✓; per-event SFX (T7) ✓; reverb via AudioEffectReverb (T4) ✓; autostart at boot via apply_settings (T4) ✓.
- **Type consistency:** `Audio.set_music_vol/set_sfx_vol/start_music/stop_music/cycle_track/track_index/current_track_name/beep/fanfare/duck/apply_settings` used identically in T5/T6/T7 as defined in T4. `MusicSeq.events_for_step/gen_wave` signatures match T2. `Tracks.TRACKS` shape matches T1.
- **Headless caveat:** the `Audio` autoload runs under the dummy audio driver — `AudioServer.add_bus`/`add_bus_effect` and `AudioStreamPlayer.play()` are no-ops/safe but the boot gate confirms no crash. If a headless error appears at T4, guard `_setup_buses` in a check, but it is expected to be clean.
- **Float test compares** use the `_approx` helper (added in T2); chord-dict equality in T1 relies on exact JS-copied literals.
