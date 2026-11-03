class_name Levels extends RefCounted
## Dev-level gauntlet grids as plain text (batch-1 trap proof set).
## Legend: `#` solid, `P` player spawn (exactly one per level), `.` empty,
## `^` pop-up spike, `X` falling tile, `d` static exit, `D` fleeing door,
## `T` fleeing-door landing cell, `H` fake floor, `V` hidden wall.
## One cell per char, rows stored top-down on the 32px grid (20x11, 640x360).
## `P` stays at col 2 row 8 so the spawn is (80, 272) on every dev level.


const DEV_0: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P..^.XXX....d.....",
	"#######...##########",
	"#######...##########",
]

const DEV_1: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P..T..D.....d.....",
	"####################",
	"####################",
]

const DEV_2: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P.....H...V..d....",
	"########.###########",
	"########.###########",
]

const DEV_3: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P...XX^X....d.....",
	"######....##########",
	"######....##########",
]

const DEV_LEVELS: Array[PackedStringArray] = [DEV_0, DEV_1, DEV_2, DEV_3]

const ALL: Array[PackedStringArray] = [DEV_0, DEV_1, DEV_2, DEV_3]


## Number of dev levels.
static func count() -> int:
	return ALL.size()


## Bounds-checked level fetch; loud empty-grid failure on a bad index.
static func get_level(idx: int) -> PackedStringArray:
	if idx < 0 or idx >= ALL.size():
		push_error("[Levels] level %d: bad level index (have %d levels)" % [idx, ALL.size()])
		return PackedStringArray()
	return ALL[idx]
