# Wraithspire — Summoner's War

A 16-bit-styled, turn-based hex strategy game with cinematic battle cutaways and a procedural 80s synth fantasy score. Two summoning archons fight over a frontier of spires and citadels. Original work inspired by Genesis-era summoner strategy.

## Play locally

Just open `index.html` in any modern browser — no build step, no dependencies.

```
start index.html      # Windows
open  index.html      # macOS
xdg-open index.html   # Linux
```

The canvas scales to fit your viewport while preserving 16:10 aspect ratio, so it works well on anything from a small laptop screen up to large 4K monitors.

## Controls

- **Mouse hover** — inspect a hex (terrain stats, unit stats in sidebar).
- **Click your unit** — selects it; blue tiles are movable, red rings are attackable.
- **Click a blue tile** — moves there and opens an action menu (Attack / Capture / Summon / Wait).
- **Click a red ring** — attacks directly (only when in range without moving).
- **Arrow keys / WASD in menus** — navigate. **Enter** confirms. **Esc** cancels.
- **E** — end your turn.
- **M** — toggle the music on/off.
- **Arrow keys (no menu open)** — pan the map.

## Battle scenes

When any combat happens — your monster vs. an enemy, your archon clashing with theirs — the camera cuts away to a side-view cinematic arena. Combatants charge, attacks land with screen shake and impact bursts, counterattacks fire, then the camera returns to the map. The arena background reflects the terrain the defender was standing on. Each unit gets a unique attack animation flavor (melee swing, breath cone, water spray, arcane bolt, dive bomb, etc.).

## Goal

Reduce the enemy Archon to 0 HP. The game ends immediately when a master falls.

## Game flow

1. Each turn your Archon regenerates MP. Captured spires add +2 MP/turn each.
2. Move your master onto a Spire hex and choose **Capture** to claim it.
3. With enough MP, move and choose **Summon** to spawn a creature in an adjacent hex (summoned units cannot act on their summon turn).
4. Elemental matchups: **Pyro ▶ Zephyr ▶ Terra ▶ Hydro ▶ Pyro**. Off-element attacks do 70% damage; strong matchups do 130%.
5. Standing on your own Spire heals +2 HP/turn; on your Citadel, +4 HP/turn.
6. Press **E** to end your turn; the AI takes over.

## Audio

The score is generated live with Web Audio — a four-chord minor-key progression (A minor → F → C → G) with a square-wave bass pluck, triangle arp, sawtooth pad, and occasional lead. Auto-starts on first click/keypress (browser autoplay policy). Press **M** any time to toggle.

## Test hooks

URL hash modes used for verification:

- `index.html#autostart` — skip the title screen and drop straight into a new game.
- `index.html#demo` — start a game, summon two creatures, and hand the turn to the AI immediately.
- `index.html#battle` — start a game and immediately trigger a battle cutaway between the two archons.
- `index.html#gameover` — jump to the victory screen.
