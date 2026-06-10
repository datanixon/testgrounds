# Wraithspire — Sprite Art Brief

Companion to `2026-06-10-wraithspire-godot-port-design.md`. This is the shared
target for generated sprite art. Paste the block below into an image-generation
agent. Both any external generation and the in-project generation at the art
milestone work to this brief, so outputs are comparable apples-to-apples.

The brief locks the **pipeline**, not the final pixels: faction-NEUTRAL,
element-colored monster art + engine-side team identity (a colored base-ring on
the board token, a colored frame in battle); two scales per creature (small board
token + large battle portrait); the two Archons bespoke per-faction.

---

```
ROLE: You are a game sprite artist producing a cohesive 2D creature set for
"Wraithspire," a dark-fantasy hex tactics game (Master of Monsters lineage).
Output is real sprite art replacing programmer-art placeholders.

=== STYLE BIBLE (hold constant across the ENTIRE set) ===
- Dark high-fantasy, painterly-but-clean. Bold, readable silhouettes first —
  each creature must be identifiable as a tiny token AND as a large portrait.
- Single consistent key light from top-left; element-colored rim light on the
  opposite edge. Same lighting on every sprite.
- Cohesion is the #1 requirement: same implied artist, same line/shading
  language, same level of detail, same palette discipline across all 22.
- Mood: moody, arcane, slightly grim. Not cute, not cartoony, not chibi.

=== TECHNICAL SPECS ===
- Transparent background (PNG, alpha). No scene, no ground, no baked drop
  shadow (the engine adds shadows/bases).
- Faction-NEUTRAL: color each creature by its ELEMENT (hexes below), NOT by
  team. The engine adds team identity (a colored base-ring on the board, a
  colored frame in battle). Do not put red/blue team colors on monster bodies.
  EXCEPTION: the two Archons are bespoke per-faction (see roster).
- Two deliverables PER creature:
    1) BOARD TOKEN  — 512x512, full-body, 3/4 view facing forward-right,
       centered with even margin, designed to still read at ~80px.
    2) BATTLE PORTRAIT — 1024x1024, full-body, dynamic combat pose, facing
       RIGHT (the engine mirrors it for the defender — so avoid asymmetric
       text/insignia that breaks when flipped).
- Consistent footing/baseline within each deliverable type so placement is
  uniform. No text, no labels, no UI, no borders.

=== ELEMENT PALETTE (key each body to its element) ===
  pyro   #e07050 (fire orange-red)     hydro  #5aa8d8 (water blue)
  terra  #9a7a4a (earth brown)         zephyr #c8c8d8 (pale wind grey)
  arcane #b078c8 (arcane purple)

=== ROSTER (22) ===
BASE MONSTERS (12):
  Cinderling  | pyro   | small impish fire creature, ember-cracked skin, flame crest, claws | melee
  Pyrowyrm    | pyro   | legless fire serpent-wyrm, glowing throat mid-breath | ranged breath
  Tidekin     | hydro  | merfolk warrior, finned limbs, coral/shell accents | melee
  Mistlevy    | hydro  | coiling misty sea serpent, semi-translucent, spitting water | ranged spray
  Stoneward   | terra  | blocky mossy stone golem, heavy fists, defensive bulk | melee tank
  Geomaul     | terra  | hulking earth ogre hefting a massive stone maul | heavy melee
  Galewisp    | zephyr | small floating air-elemental wisp, swirling wind, faint sparks | FLYING, spark
  Skyharrow   | zephyr | fierce wind-swept raptor/bird of prey, talons bared | FLYING, dive
  Hexwisp     | arcane | floating arcane mote/eye, orbiting runic glyphs, purple energy | FLYING, bolt
  Runeward    | arcane | armored sentinel covered in glowing runes, shield-bearer | melee defender
  Frostmaw    | hydro  | hulking ice beast, frost mane, icicle fangs (cooler/whiter blue) | melee
  Duneskink   | terra  | quick low-slung desert lizard, sand-scaled (warmer tan) | fast melee

EVOLVED FORMS (8) — bigger, more ornate version of the base, clearly the same lineage:
  Infernite   | pyro   | (Cinderling+) larger fire demon, full flame body, horns
  Emberdrake  | pyro   | (Pyrowyrm+) full four-limbed winged fire drake, molten scales
  Tidelord    | hydro  | (Tidekin+) regal armored merfolk lord, coral crown, great trident
  Leviathan   | hydro  | (Mistlevy+) colossal deep-sea serpent, many coils, menacing
  Colossus    | terra  | (Stoneward+) towering rune-carved stone colossus
  Earthbreaker| terra  | (Geomaul+) titanic earth ogre, boulder fists, ground-cracking
  Stormwisp   | zephyr | (Galewisp+) storm elemental, crackling lightning core | FLYING
  Skytyrant   | zephyr | (Skyharrow+) apex raptor-tyrant, vast storm-feathered wings | FLYING

ARCHONS (2) — bespoke PER-FACTION robed spellcaster commanders (NOT neutral):
  AZURE Archon   | robed caster, ROUND hood/hat, CRESCENT-topped staff;
                   blue robes  body #5aa8d8 / shadow #1f4870 / trim #bce0ff
  CRIMSON Archon | robed caster, SPIKED crown/hat, FLAME-topped staff;
                   crimson robes body #cc6a4a / shadow #6a2818 / trim #ffc4a0

=== CONSISTENCY WORKFLOW ===
1) First generate ONE style anchor (suggest Pyrowyrm battle portrait). Lock
   the look — lighting, render level, palette feel.
2) Generate every other sprite using that anchor as a style reference (same
   seed family / same prompt scaffold), so the set stays cohesive.
3) Keep framing, margins, lighting direction, and transparency identical.

=== SUGGESTED FIRST COMPARISON BATCH (8 images, before committing to all 44) ===
  Cinderling (token + portrait), Skyharrow (token + portrait),
  Stoneward (token + portrait), AZURE Archon (token + portrait).
Covers small-melee/pyro, flyer/zephyr, tank/terra, and a bespoke faction caster.

=== DO NOT ===
text, watermarks, backgrounds, baked shadows, team-color tinting on monster
bodies (archons excepted), inconsistent scale, multiple creatures per image.
```

---

## Notes for integration (engine side)

- Board token rendered at ~80px in a 36px hex; battle portrait at the cutaway's
  large scale (the JS `drawMapSprite` vs `drawBattleSprite` split).
- Team identity is an engine overlay (base-ring on the board, frame in battle),
  so the same neutral sprite serves both factions. Archons are the exception and
  ship two bespoke designs.
- Battle portraits face right; the engine mirrors horizontally for the defender —
  keep designs that read when flipped.
- Final faction-ID method (engine ring/frame vs an optional palette-swap shader)
  is confirmed at the art milestone; neutral element-true art supports either.
