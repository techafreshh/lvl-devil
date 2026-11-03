# lvl-devil

Teach-beat chapters 1-5: five single-screen levels teaching each joke in
order (falling floors `X`, pop-up spikes `^`, the fleeing door `D`, fake
floors `H`, and the baited static exit) with a deterministic headless
behavior suite.

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

The game boots to chapter 1; touching a door advances to the next chapter
and wraps around the gauntlet forever. Death respawns at `P` in
<0.5s with every trap reset to grid state.

- `LVL_1` — `X` fall teach: chained falling tiles over a safety net,
  lone static `d`.
- `LVL_2` — `^` singles: two isolated pop-up spikes, jumpable, static `d`.
- `LVL_3` — fleeing `D`->`T`: one fleeing door, one landing cell, no
  static exit; the dodge fires once after leaving spawn and stays
  catchable.
- `LVL_4` — `H` pit: fake floor over open air (neighbors stay `#`),
  static `d` past the jump.
- `LVL_5` — static `d` baited by a nearby `^`.

## How to run the headless suites

Godot has no `--test` flag; each suite is a `--script` entry:

```sh
godot --headless --path lvl-devil --script res://tests/test_traps.gd
godot --headless --path lvl-devil --script res://tests/test_levels_1_5.gd
godot --headless --path lvl-devil --script res://tests/test_player.gd
godot --headless --path lvl-devil --script res://tests/test_level_builder.gd
godot --headless --path lvl-devil --script res://tests/test_spike.gd
godot --headless --path lvl-devil --script res://tests/test_death_loop.gd
godot --headless --path lvl-devil --script res://tests/test_falling_tile.gd
godot --headless --path lvl-devil --script res://tests/test_door.gd
godot --headless --path lvl-devil --script res://tests/test_hidden_tiles.gd
godot --headless --path lvl-devil --script res://tests/test_ui_strip.gd
```

The trap-gauntlet suite (`test_traps.gd`) is a supporting proof: chapter
validity (20x11, one `P`, `D`/`T` pairing), trigger-radius (~1.2 tiles
spikes, ~5 tiles doors), drop-timing (~0.12s), flee-once, reset-on-respawn
for `^XDHV`, <0.5s respawn, and 300-frame stability per chapter. The
teach suite (`test_levels_1_5.gd`) is the primary proof: 11x20 shape and
charset for chapters 1-5, the L3 dodge witnessed once with a catchable
exit, the L4 pit falling through against its solid neighbor, and scripted
completion of every chapter. Every suite exits 0 on success and non-zero
on any failure.
