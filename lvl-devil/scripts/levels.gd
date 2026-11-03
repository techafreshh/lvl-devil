class_name Levels extends RefCounted
## Batch-1 level grids as plain text.
## Legend: `#` solid, `P` player spawn (exactly one per level), `.` empty, `^` pop-up spike.
## One cell per char, rows stored top-down on the 32px grid (20x11, 640x360).
## `d` static exit, `D` fleeing door, `T` its landing cell.
## Later issues extend the legend (`X HV`) and reuse this table.


const LEVEL_1: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"......####..........",
	"....................",
	"..P....^......####..",
	"####################",
	"####################",
]

const LEVEL_2: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..P...............d.",
	"####################",
	"####################",
]

const LEVEL_3: PackedStringArray = [
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"....................",
	"..........T.........",
	"..P...D..####.......",
	"####################",
	"####################",
]

const ALL: Array[PackedStringArray] = [LEVEL_1, LEVEL_2, LEVEL_3]


## Number of shipped levels.
static func count() -> int:
	return ALL.size()


## Bounds-checked level fetch; loud empty-grid failure on a bad index.
static func get_level(idx: int) -> PackedStringArray:
	if idx < 0 or idx >= ALL.size():
		push_error("[Levels] level %d: bad level index (have %d levels)" % [idx, ALL.size()])
		return PackedStringArray()
	return ALL[idx]
