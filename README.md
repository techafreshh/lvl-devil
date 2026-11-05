<div align="center">

<img src="lvl-devil/icon.svg" alt="lvl-devil logo" width="128" />

# lvl-devil

*A Level Devil-style troll platformer in Godot 4 — the level is the antagonist.*

[Quickstart](#quickstart) • [Usage](#usage) • [Configuration](#configuration) • [Testing](#testing) • [Project structure](#project-structure) • [Limitations](#limitations--roadmap)

</div>

A single-screen troll platformer built with Godot 4: a small blob walks toward a door while floors drop away, spikes spring up, the exit dodges aside, and some pits and walls are invisible until they kill you. Ten ASCII-grid levels, instant respawns, and a persistent all-time death counter.

The comedy only works because deaths are frictionless: every trap resets to grid state on respawn, and there is no load screen to perceive.

> [!NOTE]
> This is the product front door. The deep-dive dev reference — per-level layouts, suite-by-suite proof notes — lives in [`lvl-devil/README.md`](lvl-devil/README.md). Design intent is captured in [`.agents/PRDs/PRD.md`](.agents/PRDs/PRD.md).

## Why it exists

Short sessions, big laughs. Each level teaches exactly one lie (a falling floor, a pop-up spike, a fleeing door, a fake pit), then chapters 6–10 stack the lies into a gauntlet ending on a real door. Controls stay crisp and forgiving — coyote time, jump buffering, instant walk — so all cruelty lives in the level design, never in the hands. Every trap is legible in hindsight: you laugh at a clever lie, not at random unfairness.

## Quickstart

Prerequisites: [Godot 4.7.2](https://godotengine.org/download/) (the version CI pins in [`.github/workflows/ci.yml`](.github/workflows/ci.yml); the project targets Godot 4.7 per `lvl-devil/project.godot`). No servers, no ports, no environment variables — it is a desktop game.

```sh
git clone https://github.com/techafreshh/lvl-devil.git
cd lvl-devil
# Smoke test: headless import (mirrors CI; should exit 0 with no SCRIPT ERROR lines)
godot --headless --path lvl-devil --import
# Boot check: runs the game headless for 60 frames, then quits
godot --headless --path lvl-devil --quit-after 60
```

Or play it in the editor: open `lvl-devil/project.godot` in Godot, press Play (the main scene `res://main.tscn` boots through `GameManager` to the title). Expected first screen: the `LVL-DEVIL` title with the key legend (`Arrows/WASD move`, `Space/Z jump`, `R restart`) and a `press any key to start` prompt — any key starts play at the saved highest level (`LEVEL 1` on a fresh boot). A persistent top strip shows `LEVEL n` (1-based) on the left and the all-time `DEATHS n` total on the right. Clearing the chapter-10 door shows a one-screen end card (`CONGRATULATIONS` plus the all-time `DEATHS n`); `R` there replays from level 1 while keeping all-time deaths.

## Usage

### Controls

Effective bindings come from the `[input]` map in `lvl-devil/project.godot`:

| Action | Keys |
|---|---|
| Move left / right | Left/Right arrows or `A` / `D` |
| Jump | `Space` or `Z` (with 0.08 s coyote time, 0.10 s jump buffer, early-release jump cut) |
| Restart level / replay | `R` |

Player feel numbers are exports in `lvl-devil/scripts/player.gd`: speed 170, gravity 1500, jump velocity −420. The game runs at a 640×360 viewport (window override 1280×720, `canvas_items` stretch, `keep` aspect).

### Rules

- Touch a door to advance. The chapter-10 door shows the end card instead of wrapping (`R` replays from chapter 1, deaths kept).
- Falling below the level (`KILL_Y`, y > 376) or touching an armed spike kills the blob: the death counter and strip update the same frame, a 0.1 s wall-clock freeze plays, then the level rebuilds from grid state — respawn lands back at `P` in under half a second with every trap reset.
- `R` during play respawns instantly with no freeze (safe even mid-death).
- Progress and the all-time death total persist across sessions (see [Configuration](#configuration)).

### Levels

Each chapter is an 11-row × 20-column ASCII grid (`lvl-devil/scripts/levels.gd`), one cell per character on a 32 px grid (640×360). The spawn `P` sits at column 2, row 8 in every chapter. Levels 1–5 each teach one trap; levels 6–10 stack them into a gauntlet.

| Glyph | Meaning |
|---|---|
| `#` | Solid |
| `P` | Player spawn (exactly one per level) |
| `.` | Empty |
| `^` | Pop-up spike |
| `X` | Falling tile |
| `d` | Static exit door |
| `D` | Fleeing door |
| `T` | Fleeing-door landing cell |
| `H` | Fake floor (looks solid, never collides) |
| `V` | Hidden wall (collides, never drawn) |

- `LVL_1` — `X` fall teach: chained falling tiles over a safety net, lone static `d`.
- `LVL_2` — `^` singles: two isolated pop-up spikes, jumpable, static `d`.
- `LVL_3` — fleeing `D` → `T`: one fleeing door, one landing cell, no static exit; the dodge fires once after leaving spawn and stays catchable.
- `LVL_4` — `H` pit: fake floor over open air (neighbors stay `#`), static `d` past the jump.
- `LVL_5` — static `d` baited by a nearby `^`.
- `LVL_6` — chained-`X` hall: eight falling tiles over a safety net, lone static `d`.
- `LVL_7` — `^` + `X` combo: two isolated pop-up spikes past a falling run-up, static `d`.
- `LVL_8` — sparing-`V` mind-game corridor: one hidden wall in an otherwise promising hall, static `d`.
- `LVL_9` — everything gauntlet: `H` pit plus `V` wall plus `X` run-up plus a fleeing `D` → `T` pair.
- `LVL_10` — finale stack ending on a real door: a spike-guarded bait `d`, then the true exit `d`.

Sound is five CC0 one-shots on a persistent `SfxBus` (`lvl-devil/assets/sfx/`: `jump.wav`, `sting.wav`, `squelch.wav`, `chime.wav`, `whoomph.wav`) — jump blip, trap sting, death squelch, door chime, falling-floor whoosh.

## Configuration

There are **no environment variables** and no config flags. The only persistent state is the save file:

| Key | Meaning |
|---|---|
| `highest_level` | Highest chapter reached, 0-based |
| `total_deaths` | All-time death total, never reset by replay |

The contract lives in `lvl-devil/scripts/save.gd`: a single slot at `user://save.json` holding exactly those two keys. A missing or corrupt file falls back to `{0, 0}` and is repaired (rewritten with a warning, never an error or crash). Out-of-range values are clamped to the shipped chapter count.

## Testing

Godot has no `--test` flag; each suite is a `--script` entry. These are the exact commands CI runs (`.github/workflows/ci.yml`), and every suite exits 0 on success, non-zero on any failure:

```sh
godot --headless --path lvl-devil --script res://tests/test_player.gd
godot --headless --path lvl-devil --script res://tests/test_level_builder.gd
godot --headless --path lvl-devil --script res://tests/test_spike.gd
godot --headless --path lvl-devil --script res://tests/test_death_loop.gd
godot --headless --path lvl-devil --script res://tests/test_persistence.gd
godot --headless --path lvl-devil --script res://tests/test_ui_strip.gd
godot --headless --path lvl-devil --script res://tests/test_title_end.gd
godot --headless --path lvl-devil --script res://tests/test_falling_tile.gd
godot --headless --path lvl-devil --script res://tests/test_door.gd
godot --headless --path lvl-devil --script res://tests/test_hidden_tiles.gd
godot --headless --path lvl-devil --script res://tests/test_traps.gd
godot --headless --path lvl-devil --script res://tests/test_levels_1_5.gd
godot --headless --path lvl-devil --script res://tests/test_levels_6_10.gd
godot --headless --path lvl-devil --script res://tests/test_sfx.gd
```

CI additionally runs a headless import (failing on any `SCRIPT ERROR` / parse error), a stale `.uid` / `.tscn` check, and a `--check-only` parse of every `lvl-devil/**/*.gd` file. Save-related suites back up and restore the save file so repeated runs stay side-effect free.

> [!TIP]
> Start with `test_traps.gd` (chapter validity and trap timing across all 10 levels), then `test_levels_1_5.gd` / `test_levels_6_10.gd` (scripted completion of every chapter), then `test_title_end.gd` (title labels, any-key start, end card, `R` replay).

## Project structure

```text
lvl-devil/                  Godot project (open lvl-devil/project.godot in the editor)
├── main.tscn / main.gd     Bootstrap: hosts GameManager, boots to title
├── project.godot           Main scene, 640×360 display, [input] map
├── icon.svg                Game/project icon (also the README header logo)
├── scripts/                GDScript sources
│   ├── game.gd             GameManager: state machine (TITLE/PLAYING/END), death/respawn, HUD
│   ├── levels.gd           All 10 chapters as ASCII grids + legend
│   ├── level_builder.gd    Grid → nodes
│   ├── player.gd           Blob mover (speed/gravity/jump/coyote/buffer exports)
│   ├── spike.gd            Pop-up spike trap
│   ├── falling_tile.gd     Falling-floor trap
│   ├── door.gd             Static + fleeing doors
│   ├── hidden_tiles.gd     Fake floors (H) and hidden walls (V)
│   ├── save.gd             user://save.json persistence
│   ├── ui_strip.gd         LEVEL n / DEATHS n top strip
│   ├── title_screen.gd     LVL-DEVIL title + key legend
│   ├── end_card.gd         CONGRATULATIONS + all-time deaths card
│   └── audio.gd            SfxBus: five CC0 voices
├── scenes/                 Thin scene shells (labels are code-built so scenes can't drift)
├── assets/sfx/             Five CC0 WAV one-shots (see its README for recipes)
└── tests/                  14 headless --script suites (mirrored 1:1 in CI)
.agents/PRDs/PRD.md         Product requirements + design intent
docs/superpowers/specs/     Companion design doc
```

## Limitations / Roadmap

- **Desktop keyboard only.** No touch input, no gamepad mapping, no web/mobile export. The title legend names `Arrows/WASD`, but the shipped `[input]` map binds arrows plus `A`/`D` — `W`/`S` do nothing.
- **No settings or audio controls.** Fixed 640×360 viewport, fixed volumes, no mute toggle; the five SFX voices are the whole soundscape (no music stream ships).
- **ASCII legend is frozen.** `levels.gd` documents 10 glyphs (`# P . ^ X d D T H V`); new trap types need new glyphs and builder support.
- **Single save slot.** One `user://save.json` with two keys — no profiles, no level select, no cloud sync.
- **Fan-project scope.** A public release would need a rename and visual differentiation from Unept's Level Devil (see the IP note in the PRD) — until then, this is a private game that likes to watch you die.
