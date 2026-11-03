class_name LevelBuilder extends RefCounted
## Instantiates `#` solids and the `P` spawn from a Levels text grid.
## Entry points: `build(idx)` for real levels, `build_from_rows(rows, idx)`
## for fault-injection tests. Every failure is loud (push_error naming the
## level index) and aborts the load by returning null.


const TILE_SIZE := 32
const GRID_W := 20
const GRID_H := 11
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"
const SPIKE_SCENE_PATH := "res://scenes/spike.tscn"
const DOOR_SCENE_PATH := "res://scenes/door.tscn"

## Shared floor color so fake floors (`H`) draw pixel-identical to solids (`#`).
const FLOOR_COLOR := Color(0.85, 0.82, 0.75)


## Fixed validation order: shape first, then content, then spawn count.
## Returns "" when the grid is valid, else the loud-failure reason.
static func validate_grid(rows: PackedStringArray, level_idx: int) -> String:
	if rows.is_empty():
		return "level %d: grid not rectangular (empty grid)" % level_idx
	var width: int = rows[0].length()
	for r: int in rows.size():
		if rows[r].length() != width:
			return "level %d: grid not rectangular (row %d width %d, expected %d)" % [level_idx, r, rows[r].length(), width]
	if width > GRID_W or rows.size() > GRID_H:
		return "level %d: grid too large (%dx%d, max 20x11)" % [level_idx, width, rows.size()]
	var spawns := 0
	var flee_count := 0
	var t_count := 0
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			var ch: String = row.substr(c, 1)
			if ch != "#" and ch != "P" and ch != "." and ch != "^" and ch != "d" and ch != "D" and ch != "T" and ch != "H" and ch != "V":
				return "level %d: invalid char '%s' at row %d col %d" % [level_idx, ch, r, c]
			if ch == "P":
				spawns += 1
			elif ch == "D":
				flee_count += 1
			elif ch == "T":
				t_count += 1
	if spawns == 0:
		return "level %d: missing P (no player spawn)" % level_idx
	if spawns > 1:
		return "level %d: extra P (found %d, expected exactly 1)" % [level_idx, spawns]
	if flee_count > 1:
		return "level %d: extra D (found %d, expected at most 1)" % [level_idx, flee_count]
	if flee_count == 1 and t_count != 1:
		return "level %d: D requires exactly one T (found %d)" % [level_idx, t_count]
	if flee_count == 0 and t_count > 0:
		return "level %d: stray T without D" % level_idx
	return ""


static func _make_solid(col: int, row: int, center: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Solid_%d_%d" % [col, row]
	body.position = center
	body.add_to_group("solid_tiles")
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape_node.shape = rect
	body.add_child(shape_node)
	var visual := ColorRect.new()
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
	visual.color = FLOOR_COLOR
	body.add_child(visual)
	return body


## Fake floor (`H`): looks exactly like a solid but never collides.
## A plain Node2D (never StaticBody2D, never in `solid_tiles`).
static func _make_fake_floor(col: int, row: int, center: Vector2) -> Node2D:
	var tile := Node2D.new()
	tile.name = "FakeFloor_%d_%d" % [col, row]
	tile.position = center
	var visual := ColorRect.new()
	visual.size = Vector2(TILE_SIZE, TILE_SIZE)
	visual.position = Vector2(-TILE_SIZE / 2, -TILE_SIZE / 2)
	visual.color = FLOOR_COLOR
	tile.add_child(visual)
	return tile


## Hidden wall (`V`): blocks like a solid but draws nothing (background).
## A normal StaticBody2D in `solid_tiles` with zero visual children.
static func _make_hidden_wall(col: int, row: int, center: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Solid_%d_%d" % [col, row]
	body.position = center
	body.add_to_group("solid_tiles")
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE, TILE_SIZE)
	shape_node.shape = rect
	body.add_child(shape_node)
	return body


## Builds a level container (origin at 0,0, no offset) from raw rows.
static func build_from_rows(rows: PackedStringArray, level_idx: int) -> Node2D:
	var reason := validate_grid(rows, level_idx)
	if reason != "":
		push_error("[LevelBuilder] " + reason)
		return null
	var level := Node2D.new()
	level.name = "Level"
	var spawn := Vector2.ZERO
	var spike_cells: Array[Vector2i] = []
	var door_cells: Array[Vector2i] = []
	var flee_cells: Array[Vector2i] = []
	var t_cells: Array[Vector2i] = []
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			var center := Vector2(c * TILE_SIZE + TILE_SIZE / 2, r * TILE_SIZE + TILE_SIZE / 2)
			match row.substr(c, 1):
				"#":
					level.add_child(_make_solid(c, r, center))
				"H":
					level.add_child(_make_fake_floor(c, r, center))
				"V":
					level.add_child(_make_hidden_wall(c, r, center))
				"P":
					spawn = center
				"^":
					spike_cells.append(Vector2i(c, r))
				"d":
					door_cells.append(Vector2i(c, r))
				"D":
					door_cells.append(Vector2i(c, r))
					flee_cells.append(Vector2i(c, r))
				"T":
					t_cells.append(Vector2i(c, r))
	var spike_packed := load(SPIKE_SCENE_PATH) as PackedScene
	if not spike_cells.is_empty():
		if spike_packed == null:
			push_error("[LevelBuilder] level %d: could not load spike scene %s" % [level_idx, SPIKE_SCENE_PATH])
			level.free()
			return null
		for cell: Vector2i in spike_cells:
			var spike := spike_packed.instantiate() as Node2D
			if spike == null:
				push_error("[LevelBuilder] level %d: could not instantiate spike scene %s" % [level_idx, SPIKE_SCENE_PATH])
				level.free()
				return null
			spike.name = "Spike_%d_%d" % [cell.x, cell.y]
			spike.position = Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)
			spike.add_to_group("spikes")
			level.add_child(spike)
	if not door_cells.is_empty():
		var door_packed := load(DOOR_SCENE_PATH) as PackedScene
		if door_packed == null:
			push_error("[LevelBuilder] level %d: could not load door scene %s" % [level_idx, DOOR_SCENE_PATH])
			level.free()
			return null
		var t_center := Vector2.ZERO
		if t_cells.size() == 1:
			t_center = Vector2(t_cells[0].x * TILE_SIZE + TILE_SIZE / 2, t_cells[0].y * TILE_SIZE + TILE_SIZE / 2)
		for cell: Vector2i in door_cells:
			var door := door_packed.instantiate() as Node2D
			if door == null:
				push_error("[LevelBuilder] level %d: could not instantiate door scene %s" % [level_idx, DOOR_SCENE_PATH])
				level.free()
				return null
			door.name = "Door_%d_%d" % [cell.x, cell.y]
			door.position = Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2, cell.y * TILE_SIZE + TILE_SIZE / 2)
			door.add_to_group("doors")
			level.add_child(door)
			if door.has_method("setup"):
				door.call("setup", flee_cells.has(cell), t_center, spawn)
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[LevelBuilder] level %d: could not load player scene %s" % [level_idx, PLAYER_SCENE_PATH])
		level.free()
		return null
	var player := packed.instantiate() as Node2D
	if player == null:
		push_error("[LevelBuilder] level %d: could not instantiate player scene %s" % [level_idx, PLAYER_SCENE_PATH])
		level.free()
		return null
	player.name = "Player"
	player.position = spawn
	player.add_to_group("player")
	level.add_child(player)
	return level


## Builds a shipped level by index; loud null on a bad index or bad grid.
static func build(level_idx: int) -> Node2D:
	if level_idx < 0 or level_idx >= Levels.count():
		push_error("[LevelBuilder] level %d: bad level index (have %d levels)" % [level_idx, Levels.count()])
		return null
	return build_from_rows(Levels.get_level(level_idx), level_idx)
