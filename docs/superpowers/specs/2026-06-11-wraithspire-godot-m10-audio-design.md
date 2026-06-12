# Wraithspire Godot port — M10 (Audio): procedural synth + SFX → parity

Date: 2026-06-11
Branch: `godot-m10-art-audio`
Milestone: M10 is "Art + audio". This spec covers the **AUDIO half only** — a
self-contained, fully-codeable sub-milestone. The **ART half** (44 generated
sprite PNGs + engine integration) is deferred to its own milestone, gated on the
user producing a sprite batch from the art brief
(`docs/superpowers/specs/2026-06-10-wraithspire-art-brief.md`).
Reference: `game.js` section 15 (Audio) — `ensureAudio`/`startMusicOnGesture`/
`musicTick`/`playSynth`/`playBass`/`playKick`/`playSnare`/`playHihat`/`beep`/
`TRACKS`/`musicDuck`/`cycleTrack` (≈ lines 5120–5525) and the ~26 `beep()` SFX
call sites scattered through the game.

## Goal

Port the JS procedural audio engine to Godot so the game has its 80s-dark-synth
music bed and event SFX, and wire the music/sfx volume settings that M9 left
inert. After this sub-milestone the audio matches the JS reference in feel: a
looping 6-track minor-key synth score (bass / arp / pad / lead / drums + reverb),
per-event SFX, music ducking during battle cutaways, and live volume + on/off +
track-cycle controls in the settings overlay.

## Scope decisions (locked with user, 2026-06-11)

- **Synthesis:** generated waveform streams + native Godot bus effects (NOT a
  real-time GDScript sample synth, NOT pre-rendered .ogg files).
- **Fidelity:** full parity — all 6 tracks, drums (kick/snare/hat), bass, pad,
  lead, reverb, the full `beep()` SFX wired at game events, music on/off, track
  cycle, battle duck.
- **Music controls:** MUSIC ON/OFF toggle + TRACK ◀ name ▶ cycler added to the
  M9 settings overlay; `track_index` + `music_on` persisted. Music autostarts at
  boot (desktop — no browser-autoplay gesture gate needed).
- **Reverb:** Godot's native `AudioEffectReverb` on the Music bus (accepted
  divergence from the JS delay-feedback-lowpass network — same spacious intent).

## Architecture

Split into a **pure, harness-testable core** (the parity-locked data + sequencer
logic) and a **presentation autoload** (the actual Godot audio nodes). The JS
mixes synthesis and scheduling in one `musicTick`; the port separates *what plays
on each step* (pure) from *how it's played* (nodes).

### Pure core (no nodes — headless-testable)

**`data/tracks.gd`** (class `Tracks`) — the 6 `TRACKS` ported verbatim as a const
array. Each track: `name` (String), `chords` (4 × `{root, third, fifth}` Hz),
`arp` (16 ints, indices into the 3-note chord), `lead` (4 bars × array of
`{s: step, hz}`). Faithful 1:1 copy of the JS `TRACKS` numbers.

**`core/music_seq.gd`** (class `MusicSeq`) — pure functions:
- `events_for_step(step: int, track_index: int) -> Array[Dictionary]` — reproduces
  `musicTick`'s note selection for a global 16th-note step. Returns a list of
  voice events, each `{kind, ...params}`:
  - `bar = (step / 16) % chords.size()`, `beat = step % 16`, `chord = chords[bar]`,
    `notes = [root, third, fifth]`.
  - **kick** `{kind:"kick", gain:0.5}` on `beat == 0 or 8`.
  - **snare** `{kind:"snare", gain:0.22}` on `beat == 4 or 12`.
  - **hat** `{kind:"hat", gain: beat%4==2 ? 0.10 : 0.06}` on `beat % 2 == 0`.
  - **bass** on `beat==0||8` → `{kind:"bass", freq:chord.root, dur:0.42, gain:0.22, sweep:2400}`;
    `beat==4` → `{freq:chord.fifth*0.5, dur:0.28, gain:0.13, sweep:1600}`;
    `beat==12` → `{freq:chord.third*0.5, dur:0.28, gain:0.13, sweep:1600}`.
  - **arp** every step → `{kind:"synth", freq: notes[arp[beat]%3]*2, wave:"triangle",
    dur:0.14, gain:0.05, filter:4000, attack:0.05, reverb:0.18}`.
  - **pad** on `beat==0` → for each `n` in notes: `{kind:"synth", freq:n*2, wave:"sawtooth",
    dur:1.8, gain:0.028, filter:1100, attack:0.04, reverb:0.45}` and `{freq:n*4, wave:"sine",
    dur:1.8, gain:0.014, filter:4000, attack:0.04, reverb:0.35}`.
  - **lead** → for each `{s,hz}` in `lead[bar]` where `s == beat`:
    `{kind:"synth", freq:hz, wave:"sawtooth", dur:0.50, gain:0.07, filter:1900, attack:0.06, reverb:0.55}`.
  Pure: no randomness, no nodes. The hat-accent / bass-walk / arp-index / lead-timing
  logic is exactly the JS, so a parity test can assert the event list per step.
- `gen_wave(wave: String, length: int) -> PackedFloat32Array` — one cycle of
  square/triangle/sawtooth/sine, amplitude ±1. Pure; testable (period, bounds,
  zero-crossings). Used by the autoload to build streams.

### Presentation autoload `autoload/audio.gd` (class `Audio`)

Registered in `project.godot` `[autoload]` as `Audio` (global singleton). Owns all
Godot audio nodes. Headless-safe (dummy audio driver — `play()` is a no-op, no crash).

- **Buses** (created at `_ready` via `AudioServer.add_bus` + `add_bus_effect`):
  a **Music** bus and an **SFX** bus, both routing to Master. Music bus carries an
  `AudioEffectReverb` (wet ≈ 0.3, room ≈ 0.6 — tuned for the spacious feel) and an
  `AudioEffectLowPassFilter` (≈ 3500 Hz, approximating the JS reverb-path filter).
- **Generated streams** (at `_ready`): build looping `AudioStreamWAV`s for
  square / triangle / sawtooth / sine (one cycle of `gen_wave`, `loop_mode = FORWARD`),
  plus a white-noise `AudioStreamWAV` (seeded fill) for drums.
- **Voice pool**: a fixed pool of `AudioStreamPlayer`s per bus. To play a note:
  pick the waveform stream, set `pitch_scale = freq / base_freq`, route to the bus,
  start, and drive a `Tween` on the player's `volume_db`: linear attack to peak over
  `attack`, then to silence over `dur` (exponential-ish via `TRANS_EXPO`). This is
  the native analog of the JS `osc → gain (ramp envelope) → filter`. Per-note
  `reverb` send is approximated by routing reverb-heavy voices through the Music bus
  (which has the reverb effect) vs a dry sub-bus for low-send voices — OR by a
  simpler single Music-bus reverb with the mix tuned (acceptable; reverb-send
  per-note is the one place we simplify).
- **Drums**: `kick` = sine voice pitch-swept 110→40 Hz (Tween `pitch_scale`) + a
  short noise click; `snare` = band-ish noise (noise voice on a filtered sub-path) +
  a 220→110 triangle body; `hat` = high-passed noise voice, very short envelope.
  These mirror `playKick`/`playSnare`/`playHihat`; filter shaping uses bus effects
  or pre-baked filtered noise (accepted approximation).
- **Sequencer**: a `Timer` (`wait_time = 0.17`, autostart, repeat) → on timeout,
  `step += 1`, call `MusicSeq.events_for_step(step, track_index)`, and play each
  event through the pool. Mirrors `setInterval(musicTick, 170)` (~88 BPM 16ths).
- **Public API** (mirrors the JS):
  - `start_music()` / `stop_music()` / `toggle_music()` — start/stop the sequencer
    Timer; `music_on` state.
  - `cycle_track()` — `track_index = (track_index+1) % Tracks.TRACKS.size()`, reset
    `step = 0`, persist, return the new track name (for a banner).
  - `beep(freq, dur, wave := "square", gain := 0.1)` — one-shot SFX on the SFX bus
    (a synth voice with a quick attack + `dur` decay). Mirrors `beep()`.
  - `duck(level)` — set a Music-bus duck multiplier (lower `volume_db`); battle
    cutaways call `duck(0.35)`/`duck(1.0)`.
  - `set_music_vol(v)` / `set_sfx_vol(v)` — `AudioServer.set_bus_volume_db(bus,
    linear_to_db(v))`; `v <= 0` mutes (skip playback to avoid `-inf` dB ramps).
  - `apply_settings(settings: Dictionary)` — pull `music_vol`/`sfx_vol`/`music_on`/
    `track_index` from a settings blob (called at boot + when the settings panel changes).
- **Boot**: `_ready` builds buses + streams, reads the persisted settings
  (`SettingsStore.load_blob()`), applies volumes, sets `track_index`, and autostarts
  music if `music_on`.

## Integration (wiring the inert M9 pieces)

- **Settings overlay** (`scenes/hud/settings_panel.gd`): the MUSIC VOL / SFX VOL
  segment rows (inert since M9) now call `Audio.set_music_vol` / `set_sfx_vol` on
  click (in addition to persisting). The `_refresh` fills segments to reflect the
  current value. ADD a **MUSIC ON/OFF** toggle (→ `Audio.toggle_music`, persists
  `music_on`) and a **TRACK ◀ name ▶** cycler (→ `Audio.cycle_track`, shows the
  current track name, persists `track_index`).
- **Battle cutaway** (`scenes/battle/battle_scene.gd`): on `play()` start
  `Audio.duck(0.35)`; on `finished` (or the `done` phase) `Audio.duck(1.0)`. Mirrors
  JS `musicDuck` at battle begin/end (game.js 1052/1059).
- **SFX call sites** — port the ~26 JS `beep()` calls to the equivalent Godot game
  events, copying each call's exact `(freq, dur, wave, gain)` from the cited JS
  lines. Mapping (the implementation plan will pin each to a precise Godot call site
  + the exact JS params):
  - **battle start** (game.js:1046, `beep(150,0.08,"square",0.18)`) → `Combat`/
    `MatchScene` at battle resolve.
  - **victory/defeat fanfare** (1081-1082 ascending triangle) → `MatchScene._end_match`
    or `GameoverScene` entry.
  - **level-up / evolve** (2351-2352, 523→784 triangle) → where leveling/evolution
    fires (`Units.gain_xp` result surfaced, or in MatchScene after resolve).
  - **attack impact** (2409/2429 noisy square) → battle scene impact frames.
  - **summon** (4646) → `MatchScene._on_summon_chosen`.
  - **ability cast** (4274, 1419) → `MatchScene._arm_ability` / instant fire.
  - **capture** → tower capture in `MatchScene`.
  - **menu / title clicks** (3953, 4158-4196, 4374-4380) → title/campaign/settings
    button presses.
  - **save/load** (4180-4181) → CONTINUE load success/corrupt.
  - **select / move** (1171) → unit select / move commit.
  Events with no clean Godot home in this milestone may be deferred (logged as
  carry-forwards), but the prominent ones (battle, win, summon, capture, level-up,
  menu click) ship.
- **`SettingsStore`** (`core/settings_store.gd`): extend the blob + `defaults()` +
  `merge()` with `music_on` (bool, default true) and `track_index` (int, clamped to
  `[0, Tracks.TRACKS.size()-1]`). Mirrors the existing `music_vol`/`sfx_vol` handling.

## Project structure (new / changed)

```
data/tracks.gd              (new) 6 TRACKS verbatim
core/music_seq.gd           (new) pure events_for_step + gen_wave
autoload/audio.gd           (new) Audio singleton — buses/streams/voices/sequencer/SFX/duck
project.godot               (edit) register Audio autoload
core/settings_store.gd      (edit) + music_on, track_index
scenes/hud/settings_panel.gd (edit) wire vol; add music on/off + track cycle
scenes/battle/battle_scene.gd (edit) duck on play / restore on finish
scenes/match/match_scene.gd  (edit) SFX at game events (battle/summon/capture/level/win)
scenes/title|campaign|gameover/*.gd (edit) menu-click SFX
tests/run_tests.gd          (edit) _test_tracks, _test_music_seq, _test_gen_wave
```

## Testing

Harness (`pwsh -File godot/tests/run_tests.ps1`, `== N passed, 0 failed ==`, EXIT
0) after every task. Covers the pure core:
- **`_test_tracks`** — 6 tracks present; chord/arp/lead shapes + representative
  values match the JS (e.g. track 0 Am `{root:110, third:130.81, fifth:164.81}`,
  `arp[0..3] == [0,1,2,1]`, `lead[0][0] == {s:4, hz:440}`).
- **`_test_music_seq`** — `events_for_step` parity for representative steps across a
  full 64-step loop: step 0 (kick+hat+bass+arp+pad×6+any lead), step 4 (snare+hat+
  bass-walk+arp+lead), step 2 (hat-accent+arp), an odd step (arp only), bar
  rollover (bar index cycles 0→1→2→3→0). Assert kinds/freqs/gains for known steps.
- **`_test_gen_wave`** — square/triangle/saw/sine one-cycle buffers: length, ±1
  amplitude bound, sign pattern (square half +1 / half −1; sine zero-crossings).
- **`_test_settings`** (extend) — `music_on`/`track_index` round-trip + clamping.

**Headless-boot gate** after any scene/`autoload`/`main`/`project.godot` change:
`godot --headless --path godot --quit-after 30 2>&1 | Select-String "SCRIPT
ERROR|Parse Error|Failed to load"` → clean. The `Audio` autoload `_ready` must run
clean under the headless dummy audio driver (bus creation + stream gen must not
crash; `play()` is a no-op).

**Audible verification is manual/windowed** (`godot --path godot`): music plays and
loops; vol sliders change loudness live; MUSIC OFF silences; TRACK cycles through
the 6 named loops; battle cutaway ducks the music; SFX fire on summon/attack/
capture/win/menu clicks.

## Accepted divergences from the JS reference

- **Reverb** is Godot's native `AudioEffectReverb` on the Music bus, not the JS
  delay→feedback→lowpass network — same spacious 80s intent, different impl.
- **Per-note reverb send** is simplified to a single Music-bus reverb (tuned mix)
  rather than per-voice send gains; lead/pad still read as "wetter" via their
  longer envelopes.
- **Bass filter sweep** (the synthwave "wow") is approximated via the
  bake/tween/bus-filter rather than a live per-note biquad frequency envelope.
- **Filter shaping** on drums uses bus effects / pre-baked filtered noise rather
  than per-hit biquads.
- Noise buffer is **seeded** (deterministic fill) rather than `Math.random()`.
- Music **autostarts at boot** on desktop (the JS browser-autoplay gesture gate is
  web-only and not needed in a native Godot build).
- SFX events with no clean Godot home this milestone may be deferred (logged).

## Success criteria

The game has its synth score and event SFX with the same feel as the JS reference:
6 looping tracks (bass/arp/pad/lead/drums/reverb), live volume + on/off + track
cycle in settings, music ducking during battles, per-event SFX. Pure core
(`Tracks`/`MusicSeq`/`gen_wave`) harness-green; `Audio` autoload boots clean
headless; both gates green at every commit. Audible behavior confirmed windowed.
This closes the **audio** half of M10; the **art** half remains, gated on real
sprite assets.
