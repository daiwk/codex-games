# Tianque Arena / 天阙试炼

A Godot 4.7 top-down 3D combat prototype with a lightweight, deterministic Chinese-inspired courtyard. The distant pagoda decoration has been removed; playable arena geometry, collisions, characters, combat and layered skill VFX are preserved.

For source layout, gameplay entry points, character rebuilding, tests, and redistribution notes, read `DEVELOPMENT.md`. Third-party terms are summarized in `THIRD_PARTY_LICENSES.md`.

## Run

On macOS, double-click `play.command`. It uses an installed Godot when available; otherwise it downloads the free official Godot 4.7.2 runtime to `/private/tmp` and starts the game. No paid dependency is used.

Alternatively, install Godot 4.7.2 or a compatible Godot 4.x release, open this folder and run `main.tscn`, or execute:

```bash
godot --path /path/to/tianque-arena
```

## Controls

- `WASD`: move
- Moving automatically turns the hero toward the movement direction
- `J`: three-hit combo
- `K`: heavy guard-breaking slash
- `Space`: invulnerable dash
- `L`: Falling Star area attack
- `H`: heal 50 HP (5 uses per run; full health does not consume a use)
- `R`: restart after victory or defeat

Attacks use forward-cone aim assist: an enemy in front of the hero can be selected automatically, while enemies behind the hero do not force an abrupt 180-degree turn.

## macOS package

The project includes a universal (Apple Silicon and Intel) macOS export preset and `tools/package_macos.sh`. The final free/ad-hoc-signed DMG is written to `dist/TianqueArena-macOS.dmg`. Because it is not Apple-notarized, the DMG includes `一键安装.command`, which verifies the fixed app bundle, installs it to the current user's `~/Applications`, removes quarantine only from that app, and launches it without disabling Gatekeeper globally. Chinese fallback instructions are included.

## Source development package

Run `bash tools/package_source.sh` to create `dist/TianqueArena-Source-v1.0.zip`. It contains the portable Godot project, current runtime assets, editable Blender cast, original CC0 character inputs, stable build tools, QA images, and development documentation while excluding caches, release binaries, backups, and abandoned experiments.

## Content pipeline

- Environment: procedural courtyard, platforms, bridges, walls and lanterns in `scripts/main.gd`
- Runtime player hero: Quaternius RPG Characters Warrior, converted to `assets/characters/tianque_hero.glb`
- Runtime enemy cast: Rogue guards, Monk brute, Wizard caster, and Cleric boss under `assets/characters/enemies/`
- Every cast member uses its native 44-bone skeleton, equipment, hand-painted texture, and authored combat animations
- The Warrior has subtle eyes and a mouth rasterized directly into the face UV texture, so facial details follow the original skinned mesh
- Editable runtime hero: `source/hero/quaternius_warrior.blend`
- Editable enemy sources: `source/cast/guard_rogue.blend`, `brute_monk.blend`, `caster_wizard.blend`, and `boss_cleric.blend`
- Repeatable full-cast build: `tools/build_rpg_cast.py`
- Original FBX and texture inputs: `source/third_party/quaternius/rpg-characters/upstream/`
- Runtime characters and animations: Quaternius, CC0 1.0 Universal; no retargeting is used
- Procedural characters remain only as a missing-asset fallback; normal gameplay uses the authored GLB cast
- No paid models or animation services are required

Third-party provenance and license notes are retained under `source/third_party/`. This directory is ignored by Godot so only final generated GLBs are imported. The code separates authored character visuals from gameplay (`player.gd`, `enemy.gd`, `combatant.gd`), so body shape, clothes, hair, skeleton, or animation clips can change without rewriting combat.
