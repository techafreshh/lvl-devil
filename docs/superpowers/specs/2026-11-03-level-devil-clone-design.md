# Level Devil–Style Troll Platformer — Design

Date: 2026-11-03
Status: **Approved by owner, 2026-11-03**
Working folder: `/home/techafresh/projects/lvl-devil`

## Why

A personal, just-for-fun project: a faithful clone of the game Level Devil (by Unept) built in Godot. The owner has never used Godot before and wants to watch a complete small game get built, understand it, and laugh at it. There is no deadline and no publishing pressure. The measure of success is: the owner replays levels they've already beaten just to get got again.

## What it is

A minimalist, single-screen troll platformer. A small blob character walks left-to-right across one screen toward a door. The level actively betrays them: floors drop away mid-step, spikes spring out of nowhere, the door runs off when approached, and some walls and pits are invisible until they kill you. The level is the antagonist.

Deaths are instant and restarts are instant. The emotional target is comedy, not challenge: the player should feel the game *lied* to them, laugh, and be back at the start within a second.

## Goals (v1)

- Faithful troll-platformer feel: instant deaths, instant restarts, comedic betrayals.
- Four trap types: **falling floors**, **pop-up spikes**, **runaway door**, **hidden pits & walls**.
- Roughly 10 single-screen levels that use all four traps and escalate the jokes.
- A structure where adding tens of later levels is editing text, not building scenes.
- All graphics drawn from code primitives (flat shapes, zero art assets).
- Free CC0 sound effects only.
- Keyboard-first desktop game; engine choice (Godot) keeps web export open later with no rework.
- Beginner-readable build: small file count, plain GDScript, code commented so a first-timer can follow it.

## Non-goals (v1)

- Touch or mobile support.
- Menus, settings, accounts, save systems beyond a trivial "highest level reached" note.
- Music.
- A level-editor UI (levels are text).
- Additional trap families (crushers, moving spike walls, teleporters, fake doors) — candidates for v2.

## Anti-goals (these would make the project a failure even if it "works")

- **Unfair-but-not-funny traps.** If a death reads as random noise rather than a clever lie, the trap gets redesigned. The gag is always legible in hindsight.
- **Slow restarts.** Anything the player can perceive as a load screen.
- **Visual clutter.** Every trap must be readable the instant it springs; nothing hides behind decoration (except the traps whose hiding *is* the joke — they must read as "nothing").

## Constraints

- Godot 4.x (latest stable), GDScript only, no third-party addons or plugins.
- Must run at 60 fps on ordinary integrated graphics.
- Lives in the working folder above. The owner is on WSL2: the Godot editor will most likely be installed on the Windows host and open the project via `\\wsl.localhost`; running a headless Godot binary inside WSL for validation/testing is optional builder tooling, not a requirement.
- IP note: this is a private fan project for personal use. If it is ever published publicly it must be renamed and visually differentiated from Unept's game; assume v1 is never published.

## Decisions made with the owner

- Goal: just for fun. Faithful clone, own levels.
- All four trap types in v1.
- Levels are defined as ASCII text grids in code (chosen from three approaches below).
- Division of labor: the agent builds and explains everything; the owner watches, plays, and critiques feel.

## Approaches considered for how levels are built

1. **Editor-built scenes** — every object is a reusable scene piece dragged into a per-level scene in the editor. Visual and clicky: more seconds per level, and only someone fluent in the editor can author levels. Rejected: level content is data, and data-as-code iterates fastest here and lets the owner tweak levels in a text file.
2. **TileMap painting** — paint floors with Godot's tilemap tools. Fast for painting big maps, but the genre's core behaviors (tiles that vanish, a door that flees, walls that look like background) fight tilemaps' static grid data and get messy fast. Rejected: wrong tool for behavior-heavy levels.
3. **ASCII text grids (chosen)** — each level is a small multi-line string constant; a level builder script instantiates objects from it. Levels are quick to write and edit in plain text, diffs are readable, and the owner can design their own levels without touching the editor. Cost: no WYSIWYG preview; accepted (running the level *is* the preview).

## Design

### Screen and world

- Internal resolution **640×360**, on a **32 px grid** → **20 × 11 cells**, one screen per level, static camera (no scrolling — faithful to the original and keeps jokes legible).
- Window opens at 2× (1280×720), stretch mode `canvas_items`, so the same build looks right fullscreen and in a browser later.
- Palette (starting point, builder may refine): near-black background; warm light gray solids; the player is a black rounded blob with two white eyes; the door darker with a lighter frame; spikes light triangles. Flat colors only, no gradients or textures.
- Falling below the bottom of the screen is death (needed for pits and dropped floors).

### ASCII legend (v1)

```
#  solid block (normal floor/wall)
P  player spawn
D  door — dodges once per attempt, then is a real exit: dodge first, catch
   second. A level may have at most one D and must give it a T marker.
d  door — static, this one is real (used late in a level for fake-outs)
T  door landing marker: where the fleeing D dodges to. Exactly one per D.
^  pop-up spike: hidden until triggered
X  falling floor tile
H  hidden pit: renders exactly like a solid '#', but is not solid
V  hidden wall: renders as empty background, but blocks movement
.  empty space
```

One character per cell, one level per string, levels stored top-down. The legend is deliberately small; joke variety comes from *arrangement*, which is the Level Devil way. Unreachable bait doors are out of v1's vocabulary (they're in the v2 "fake doors" family) — every D in v1 can be caught, the joke is the delay.

### Player feel

Starting numbers — the builder owns feel-tuning. Player is a 26×26 px rounded square.

- Walk ~170 px/s, gravity ~1500 px/s², jump velocity ~ −420 px/s, releasing jump early cuts upward speed (~×0.45).
- Coyote time ~0.08 s, jump buffer ~0.10 s. Controls must feel crisp even though the game cruelly lies: fairness lives in the controls.
- No double jump, no run button — the original's vocabulary is walk + jump only.

### Trap semantics (v1 starting rules, tunable)

- **X — falling floor:** ~0.12 s after the player first stands on it, it shakes briefly and drops; non-solid thereafter. Resets only on respawn. Chained X tiles drop independently — walking across a hall of them can open the whole floor under you.
- **^ — pop-up spike:** springs when the player is on the same row within ~1.2 tiles horizontally. Extends essentially instantly, then stays out until respawn. Between trigger and toll: the classic "you are already dead" beat.
- **D — runaway door:** proximity-based trigger, not a mid-level tripwire: when the player is within ~5 tiles *and moving toward it*, it dodges once per attempt (~0.3 s tween) to the cell marked `T`, then behaves as a normal, catchable exit. If the player spawns already inside trigger range, the door holds its nerve until the player has moved at least ~1 tile from spawn — the player must always *witness* the dodge for the joke to land. Trigger radius and tween feel are tuning.
- **H — hidden pit:** drawn identical to a solid block. Player walks in and falls out of the world. On death the trap no longer needs to hide (dead men tell no jokes) — leave it revealed after the corpse burst, until respawn resets it.
- **V — hidden wall:** drawn as empty background, blocks movement. Used sparingly; funniest when the visible corridor is shaped like it obviously leads somewhere.

- **Death causes:** touching an active spike; leaving the screen bottom; (v1 has no crush mechanics).
- **Death presentation:** ~0.1 s freeze-frame, a burst of the player's shape into particles, a cartoonish squelch/boing SFX, respawn in under 0.5 s total including the level reset. R restarts the level manually at any time.

### Flow and UI

- Linear progression: touch the door → next level loads almost immediately (~0.3 s), keeping momentum.
- Persistent top strip (drawn, not scene-chrome): `LEVEL n` and a **deaths** counter. The death counter is half the fun and should be unmissable. One number, all-time total from the save file — "LEVEL 4 — 61" reads funnier than any per-session accounting.
- On launch the game resumes automatically at the highest level reached (saved in `user://` along with the death count). No continue-screen ceremony; replaying from level 1 can be a key on the end card later if the owner asks.
- End of the last level: a minimal end card (deaths total, a congratulations line). A tiny title/start screen exists only to say what the keys are; keep it to one screen.
- Level-designer safeguard: a level containing `D` without exactly one `T` (or with more levels' worth of mismatch) is an authoring error the builder surfaces loudly at load time rather than silently misbehaving.

### Sound

CC0 effects only (Kenney or freesound CC0): soft blip for jump, a rising "uh-oh" sting when a trap triggers, a cartoon squelch for death, a happy chime for reaching the door, a "whoomph" for a dropped floor. Modest volumes. No music in v1.

### Structure sketch (the builder may improve it)

- Autoload `Game` — current level index, death count, restart/load-level entry points.
- `LevelData.gd` — the array of level strings (plus any per-level notes).
- `LevelBuilder.gd` — maps legend → nodes, one reusable `Level` scene.
- Small actor scripts: `Player`, `Door`, `PopupSpike`, `FallingTile`, `HiddenPit`, `HiddenWall`, `SolidBlock` — each trap is a short, self-contained script; that self-containment is what makes the code followable for a beginner.

## What's left to the builder

Exact physics numbers, trigger radii and timing feel; GDScript idioms and file naming; implementation details of the level builder (how cells become nodes, reset-on-respawn bookkeeping); whether to use a headless Godot binary for validation; minor palette and UI typography choices. None of these require going back to the owner — the owner critiques by playing.
