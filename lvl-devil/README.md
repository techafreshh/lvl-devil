# lvl-devil

Batch-1 trap gauntlet: four dev levels proving every trap family
(pop-up spikes `^`, falling tiles `X`, fleeing doors `D`, fake floors `H`,
hidden walls `V`) with a deterministic headless behavior suite.

## How to run the game

```sh
godot --headless --path lvl-devil --quit-after 60
```

Expected: boots to dev level 0 with exit code 0 and no missing-autoload
errors. Or open `lvl-devil/project.godot` in the Godot 4.x editor and
press Play (the `main.tscn` main scene starts level 0 through
`GameManager`). Move with arrows/`AD`, jump with space/`Z`, restart
with `R`; falling below the level kills the player and respawns at `P`
in <0.5s. A persistent top strip always shows `LEVEL n` (1-based) on
the left and the all-time `DEATHS n` total on the right.

## Legend

`#` solid, `P` player spawn (exactly one per level), `.` empty,
`^` pop-up spike, `X` falling tile, `d` static exit door,
`D` fleeing door, `T` fleeing-door landing cell, `H` fake floor
(looks solid, never collides), `V` hidden wall (collides, never draws).

## Dev levels

The game boots to dev level 0; touching a door advances to the next dev
level and wraps around the gauntlet forever. Death respawns at `P` in
<0.5s with every trap reset to grid state.

- `DEV_0` — chained-`X` crossing with `^` on solid and a static `d`.
- `DEV_1` — `D` + `d` fakeout: one fleeing door, one static look-alike,
  exactly one `T` landing cell.
- `DEV_2` — `H`/`V` ambush corridor: fake floor over a pit, invisible wall.
- `DEV_3` — combined `^` + `X` gauntlet into a static `d`.

## How to run the headless suites

Godot has no `--test` flag; each suite is a `--script` entry:

```sh
godot --headless --path lvl-devil --script res://tests/test_traps.gd
godot --headless --path lvl-devil --script res://tests/test_player.gd
godot --headless --path lvl-devil --script res://tests/test_level_builder.gd
godot --headless --path lvl-devil --script res://tests/test_spike.gd
godot --headless --path lvl-devil --script res://tests/test_death_loop.gd
godot --headless --path lvl-devil --script res://tests/test_falling_tile.gd
godot --headless --path lvl-devil --script res://tests/test_door.gd
godot --headless --path lvl-devil --script res://tests/test_hidden_tiles.gd
godot --headless --path lvl-devil --script res://tests/test_ui_strip.gd
```

The trap-gauntlet suite (`test_traps.gd`) is the primary proof: dev-level
validity (20x11, one `P`, `D`/`T` pairing), trigger-radius (~1.2 tiles
spikes, ~5 tiles doors), drop-timing (~0.12s), flee-once, reset-on-respawn
for `^XDHV`, <0.5s respawn, and 300-frame stability per dev level.
Every suite exits 0 on success and non-zero on any failure.
