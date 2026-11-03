class_name Levels extends RefCounted
## Teach-beat chapters as plain text (ordered L1-L5 trap lessons).
## Legend: `#` solid, `P` player spawn (exactly one per level), `.` empty,
## `^` pop-up spike, `X` falling tile, `d` static exit, `D` fleeing door,
## `T` fleeing-door landing cell, `H` fake floor, `V` hidden wall.
## One cell per char, rows stored top-down on the 32px grid (20x11, 640x360).
## `P` stays at col 2 row 8 so the spawn is (80, 272) on every chapter.
## Teach order: L1 `X` fall, L2 `^` singles, L3 fleeing `D`->`T`,
## L4 `H` pit, L5 static `d` baited by `^`.


const LVL_1: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P.............d...",
	"#######XXX##########",
	"####################",
]

const LVL_2: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P....^....^...d...",
	"####################",
	"####################",
]

const LVL_3: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P..........D..T...",
	"####################",
	"####################",
]

const LVL_4: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P.............d...",
	"##########H#########",
	"##########.#########",
]

const LVL_5: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P...........^.d...",
	"####################",
	"####################",
]

const ALL: Array[PackedStringArray] = [LVL_1, LVL_2, LVL_3, LVL_4, LVL_5]


## Number of teach chapters.
static func count() -> int:
	return ALL.size()


## Bounds-checked level fetch; loud empty-grid failure on a bad index.
static func get_level(idx: int) -> PackedStringArray:
	if idx < 0 or idx >= ALL.size():
		push_error("[Levels] level %d: bad level index (have %d levels)" % [idx, ALL.size()])
		return PackedStringArray()
	return ALL[idx]
