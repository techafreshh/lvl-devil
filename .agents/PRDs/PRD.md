# PRD: Level Devil–Style Troll Platformer (working title: lvl-devil)

**Status:** Approved (owner, 2026-11-03) — companion design doc approved same day
**Date:** 2026-11-03
**Related design doc:** `docs/superpowers/specs/2026-11-03-level-devil-clone-design.md`
**Engine:** Godot 4.x (GDScript) · **Type:** Single-player desktop 2D platformer

---

## 1. Executive Summary

An intentionally minimal, single-screen troll platformer in the mold of Level Devil (by Unept). A small blob walks toward a door and the level betrays them: floors drop away mid-step, spikes spring up out of nowhere, the exit door dodges away, and some pits and walls are invisible until they kill you. The level itself is the antagonist.

The core value proposition is **comedy through betrayal with zero friction**: deaths are instant, restarts are instant, and every trap is legible in hindsight — the player laughs at a clever lie instead of raging at random unfairness. All graphics are code-drawn flat shapes and all audio is CC0 sound effects, so the project needs no art or audio assets.

**MVP goal:** a keyboard-playable desktop build of ~10 single-screen levels using all four trap types (falling floors, pop-up spikes, a runaway door, hidden pits & walls), with an instant death/restart loop, a persistent all-time deaths counter, and level structure defined as easy-to-edit ASCII text grids.

## 2. Mission

> Build a small game whose only job is to make its owner laugh at getting got — and, in doing so, be a complete, readable first Godot project.

**Core principles**

1. **Comedy over challenge.** A trap that reads as random rather than a clever lie is a bug and gets redesigned.
2. **Frictionless deaths.** Any restart the player can perceive as a load screen is a failure.
3. **Legible lies.** Traps may hide, but the moment one springs its joke must be instantly readable. No visual clutter.
4. **Fair hands, cruel level.** Controls are crisp and forgiving (coyote time, jump buffer); all cruelty lives in the level design.
5. **Beginner-readable code.** Small file count, plain GDScript, comments — the owner should be able to follow how a trap works.

## 3. Target Users

**Primary persona — the owner.** A hobbyist, complete Godot beginner, plays on a keyboard (Windows host, project lives in WSL2). Plays in short sessions; measures fun in laughs and death counters, not leaderboards. Also the project's only "stakeholder": they critique by playing, not by reading tickets. Success is *their* enjoyment.

**Secondary persona — the keyboard-lender.** Friends or family who pick up the same keyboard. They receive no tutorial beyond a one-screen key legend; the game must therefore be understandable from its first death onward. Publishing publicly is explicitly out of scope for v1 (IP note: a public release would require a rename and visual differentiation from Unept's game).

## 4. MVP Scope

### In Scope

**Core gameplay**
- [ ] Player controller: walk + jump only (26×26 rounded-square blob, eyes), crisp feel targets (§7.1)
- [ ] Trap: **falling floor** tiles (`X`) — shake ~0.12 s after first contact, then drop
- [ ] Trap: **pop-up spikes** (`^`) — hidden, spring on proximity, stay out until respawn
- [ ] Trap: **runaway door** (`D` + `T` landing marker) — dodges once per attempt, then catchable
- [ ] Trap: **hidden pits** (`H`) and **hidden walls** (`V`) — revealed on (lethal) contact
- [ ] Static doors (`d`) for fake-outs; solid blocks (`#`); falling below screen = death
- [ ] Instant death presentation: ~0.1 s freeze, shape-burst particles, squelch SFX
- [ ] Instant respawn: full level reset in < 0.5 s; manual restart with `R`

**Content**
- [ ] ~10 hand-designed single-screen levels escalating the four traps (ASCII grid strings)

**UI & meta**
- [ ] Top strip: `LEVEL n` + all-time deaths counter
- [ ] One-screen key legend (title/start screen), minimal end card (total deaths + congrats)
- [ ] Auto-resume at highest level reached; persisted in `user://`

**Technical**
- [ ] ASCII-level format + load-time validation (e.g., `D` without exactly one `T` fails loudly)
- [ ] CC0 sound effects (jump, trap sting, death, door chime, floor-whoosh)
- [ ] Fixed internal resolution 640×360 @ 32 px grid, 2× window, `canvas_items` stretch
- [ ] CI workflow as an early deliverable: GitHub Actions runs `godot --headless --import` (fail on script errors), `*.uid` cleanliness, and headless script tests — so the factory's `["*"]` merge gate has real checks from lap 2 on

### Out of Scope (deferred)

- [ ] Touch/mobile support; tuned web export (Godot keeps both open later)
- [ ] Menus, settings, accounts; music
- [ ] Level-editor UI; per-level metadata beyond grid characters
- [ ] More trap families (fake doors, crushers, teleporters, moving spikes) — v2 candidates
- [ ] Publishing to itch.io/Poki/Steam; any rename/branding work
- [ ] Multiplayer, networking, localization

## 5. User Stories

1. **As a player, I want one-button-obvious controls (arrows/WASD + jump + R), so that I only ever think about the trap, not the inputs.** *Example: I hold right, tap jump, and land the same first jump every attempt — the timing is never the joke.*
2. **As a player, I want to die instantly and be playing again within a blink, so that dying fuels "one more try" instead of frustration.** *Example: spike kills me mid-sentence; by the time I retell the joke to a friend, I'm already at the level start.*
3. **As a player, I want the floor to vanish under my feet, so that the level surprises me without any tutorial.** *Example: level 1's floor drops tile-by-tile as I walk; by level 3 I don't trust any floor — which is exactly when `H` gets me.*
4. **As a player, I want the exit door to visibly dodge away, so that I experience the game spitefully negotiating with me.** *Example: I approach the door, it hops to a ledge across the gap; catching it the second time is mine.*
5. **As a player, I want a big deaths counter, so that the toll becomes the scoreboard and the story.** *Example: "LEVEL 4 — 61" is funnier than any star rating.*
6. **As a player, I want the game to resume where I got got last session, so that a break doesn't erase progress.** *Example: close the game at level 7; tomorrow it opens at level 7.*
7. **As the owner-designer, I want levels to be ASCII text grids, so that I can design my own gags in a text editor without touching the game engine.** *Example: I change one row of `#` into `X` and the hall I signed off on becomes a trap corridor on next launch.*
8. **As the owner-learner, I want small, commented trap scripts, so that I can follow how each gag works.** *Example: `popup_spike.gd` fits on one screen and names its trigger radius in plain numbers.*

## 6. Core Architecture & Patterns

**Approach:** levels are data (ASCII strings), systems are small scenes/scripts; a builder instantiates everything at runtime. No tilemaps, no editor-placed per-level scenes, no addons. Repo layout: game project lives in the `lvl-devil/` subfolder (docs and `.agents/` at the repo root, jetpack-style); all Godot paths below are relative to that subfolder.

```
lvl-devil/
├── project.godot
├── docs/superpowers/specs/2026-11-03-level-devil-clone-design.md
├── .agents/PRDs/PRD.md
├── scenes/
│   ├── Main.tscn            # entry: owns title / game / end-card states
│   ├── Level.tscn           # generic level container, built per grid string
│   └── Player.tscn
├── scripts/
│   ├── game.gd              # autoload: level index, deaths, save/load, restart
│   ├── level_data.gd        # const LEVELS: Array[String] — the content
│   ├── level_builder.gd     # legend → nodes, load-time validation
│   ├── player.gd
│   └── traps/               # popup_spike.gd, falling_tile.gd, door.gd,
│                            #   hidden_pit.gd, hidden_wall.gd, solid_block.gd
├── assets/sfx/              # CC0 ogg/wav files
└── ui/                      # drawn top strip, title, end card
```

**Key patterns**

- **Data-driven levels:** each level = one multi-line string in `level_data.gd`; legend `# P D d T ^ X H V .` (semantics in §7).
- **Self-contained trap scripts:** each trap is short, stateless across levels, resets on respawn; that self-containment is what makes the code followable.
- **Autoload `Game` (singleton):** current level index, all-time deaths, `restart_level()`, `next_level()`, persistence — traps and UI depend on nothing else.
- **Reset-on-respawn discipline:** every actor derives its state from the grid each attempt; nothing carries over except the save file.
- **Drawn, not scene-chrome:** UI is in-game canvas drawing; keeps resolution scaling simple.

## 7. Tools/Features (specifications)

### 7.1 Player
- 26×26 px rounded square, black blob + two white eyes; starts at `P`.
- Feel targets (builder owns final tuning): walk ~170 px/s; gravity ~1500 px/s²; jump ≈ −420 px/s with early-release cut (×0.45); coyote ~0.08 s; jump buffer ~0.10 s.

### 7.2 Traps (v1 semantics; trigger numbers are tuning, rules are fixed)
| Legend | Behavior |
|---|---|
| `X` falling floor | Shakes ~0.12 s after first stand, drops; non-solid after; resets on respawn; chains drop independently |
| `^` pop-up spike | Springs when player on same row within ~1.2 tiles; extends ~instantly; stays out until respawn |
| `D` + `T` runaway door | Flees once per attempt to its `T` when player within ~5 tiles & approaching; must never trigger before the player has moved ~1 tile (dodge must be witnessed); then a normal exit |
| `d` static door | Ordinary exit, no theatrics |
| `H` hidden pit | Renders identical to `#`; not solid; falling out of the world is death |
| `V` hidden wall | Renders as background; blocks movement (use sparingly) |
| Death causes | Active spike contact; leaving screen bottom. (No crush mechanics in v1) |

### 7.3 Level format & validation
- One level per string, top-down rows, 20×11 target grid; `D` requires exactly one `T`; level strings longer/shorter than canvas are a load-time error.
- A validation pass logs a loud, human error (level index + reason) and refuses to start a broken level.

### 7.4 Death & restart loop
- Death: ~0.1 s freeze-frame → shape-burst particles → squelch SFX → reset. Total death-to-playing under 0.5 s. `R` works anywhere, anytime.

### 7.5 UI & persistence
- Top strip with `LEVEL n` and all-time deaths; auto-resume at highest level via `user://` save (index + total deaths); one-screen key legend at start; minimal end card after final level.

## 8. Technology Stack

| Layer | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x, latest stable** | 2D-first, web export later, free |
| Language | **GDScript only** | Beginner-readable, no build step |
| Addons | **None** | Keep dependency-free and followable |
| Art | Code-drawn flat shapes | Genre-faithful, zero assets |
| Audio | **CC0 SFX only** (Kenney / freesound-CC0) | No licensing, small files, no music in v1 |
| Save | `user://` (JSON) | One tiny file |
| Dev environment | Windows-side Godot editor over `\\wsl.localhost\…` | Owner is on WSL2 |
| Optional tooling | Headless Godot binary in WSL for smoke-test validation | Lets the agent verify levels/scripts without a display |

**Agent-side tooling (not shipped in the game):** 11 gamedev agent skills installed project-locally in `.agents/skills/` (godot-gdscript, godot-nodes-scenes, godot-2d-movement, godot-signals-groups, physics-tuning, game-feel, level-design, godot-ui-control, godot-audio, godot-gdscript-headless-testing, godot-export), with provenance in `skills-lock.json`. They shape how the agent writes code; no game dependency, consistent with the no-addons constraint.

## 9. Security & Configuration

- Single-player, offline, local save file → no authentication, no network calls, no telemetry; security scope is effectively out of scope.
- Configuration = Godot project settings (window 1280×720 over 640×360, `canvas_items` stretch, input map: arrows/WASD, Space/Z jump, R restart). No user-facing settings UI.
- Save tamper-proofing out of scope (it's a comedy death counter).

## 10. API Specification

Not applicable — no backend, no network surface. The only internal "contract" is the ASCII legend above and the `Game` autoload surface (`restart_level()`, `next_level()`, `deaths`, `current_level`).

## 11. Success Criteria

**MVP success:** the owner replays levels they've already beaten just to get got again, and can point at any trap script and explain it.

**Functional requirements**
- [ ] All 10 levels completable start to finish; zero instances where a level is unwinnable or a `T` is unreachable
- [ ] Every death → playing again in < 0.5 s on the same level
- [ ] All four trap types appear at least 3 times across the level set
- [ ] Manual `R` restart and auto-resume behave identically on repeat attempts
- [ ] Stable 60 fps, no frame hitches on trap triggers

**Quality indicators / UX goals**
- Deaths feel funny, never random: every trap obeys its stated rule so hindsight explains each death
- The dodge, the drop, and the spring are readable at 640×360 from sofa distance
- The deaths counter is visible in every playable frame

## 12. Implementation Phases

*(Sessions ≈ owner's evening play-and-watch sessions; the agent builds in between.)*

**Phase 1 — Skeleton & feel (1–2 sessions)**
- Goal: Godot installed and running for the owner; project skeleton; the *feel* of walking and jumping locked in.
- Deliverables: [ ] `project.godot` + input map · [ ] `Player.tscn`/`player.gd` with feel targets · [ ] test grid level in `level_data.gd` · [ ] solid blocks + level builder for `#` `P` `.` only
- Validation: owner plays the test room and signs off "controls feel crisp."

**Phase 2 — Traps & the death loop (1–2 sessions)**
- Goal: all four trap families live, plus death/restart.
- Deliverables: [ ] `^` `X` `H` `V` `D`/`d`/`T` · [ ] death presentation + respawn < 0.5 s · [ ] `R` restart · [ ] top-strip counters
- Validation: a 3–4-level gauntlet using every trap; each gag explains itself on death.

**Phase 3 — Content & meta (1–2 sessions)**
- Goal: the game is complete.
- Deliverables: [ ] ~10 final levels · [ ] CC0 sfx wired · [ ] `user://` auto-resume · [ ] title legend + end card
- Validation: full playthrough start→end card; closing and reopening resumes correctly.

**Phase 4 — Polish pass (1 session)**
- Goal: timing and feel; final pass on everything the owner noticed while playing.
- Deliverables: [ ] trigger radii/tweens tuned · [ ] palette/typography pass · [ ] loud load-time validation proven on a deliberately broken level
- Validation: owner replays every level once more, laughing; no trap feels random.

## 13. Future Considerations

- **V2 traps:** fake (unreachable) doors, crushers, teleporting doors, moving spike walls, gravity flips.
- **A hook of its own:** if v1 delights, find the owner's twist that makes it visitable beyond a clone (theme, meta-gag, level "episodes").
- **Web export** for a shareable link; **touch controls** after that.
- **Level sharing:** the ASCII format makes "paste a level string to a friend" trivially possible later.
- Music, captures (death replays), season content.

## 14. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Controls feel mushy/laggy** — kills the genre before any trap lands | Phase 1 is entirely a feel gate: nothing else is built until walking/jumping feel crisp to the owner |
| **Traps read as unfair, not funny** | Named anti-goal; each trap's rule is fixed & documented; any death a replay can't explain = redesign |
| **Broken level strings** (bad `T`, off-canvas) silently create unwinnable levels | Load-time validation fails loudly with level index + reason (tested in Phase 4 with a deliberately broken level) |
| **WSL2 workflow friction** (editor/agent split) | Editor on Windows host over `\\wsl.localhost`; optional headless Godot in WSL so the agent can smoke-test without a display |
| **Scope creep** (trap families, mobile, publishing) | v1 legend is frozen at 9 characters; new ideas go to §13, not the build |
| **SFX licensing mistakes** | CC0-only sources, recorded in `assets/sfx/` provenance note |

## 15. Appendix

- **Design doc (source of truth for design intent):** `docs/superpowers/specs/2026-11-03-level-devil-clone-design.md`
- **Grid legend (v1):** `#` solid · `P` spawn · `D` fleeing door · `d` static door · `T` door landing · `^` spike · `X` falling floor · `H` hidden pit · `V` hidden wall · `.` empty
- **IP note:** private fan project; public release requires rename + differentiation from Unept's Level Devil.
