# ROADMAP — Wraithspire Godot 4 port (`godot-port`)

Port-to-parity milestone tracker. Protocol: one milestone → verify
(`pwsh godot/tests/run_tests.ps1` green) → commit `[godot] N: <summary>` →
check off here. Spec: `docs/superpowers/specs/2026-06-10-wraithspire-godot-port-design.md`.
The Godot project lives in `godot/`; the JS build at repo root stays the frozen
reference. ROADMAP2 Phases 2–8 are deferred to their own specs post-parity.

- [x] **M1 — Skeleton + headless harness + hex core**
- [x] M2 — Data tables + deterministic map gen (placeholder tiles)
- [ ] M3 — Units + movement/pathfinding + selection
- [ ] M4 — Combat resolution + status engine + weather (logic + forecast)
- [ ] M5 — All 12 abilities
- [ ] M6 — AI (threat map + decision tree + summon economy)
- [ ] M7 — HUD/UI as Control nodes
- [ ] M8 — Battle cutaway scene
- [ ] M9 — Title + gameover + save/load + maps + campaign → parity
- [ ] M10 — Art + audio pass (real sprites swap in)
