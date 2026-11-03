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
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			var ch: String = row.substr(c, 1)
			if ch != "#" and ch != "P" and ch != "." and ch != "^" and ch != "X":
				return "level %d: invalid char '%s' at row %d col %d" % [level_idx, ch, r, c]
			if ch == "P":
				spawns += 1
	if spawns == 0:
		return "level %d: missing P (no player spawn)" % level_idx
	if spawns > 1:
		return "level %d: extra P (found %d, expected exactly 1)" % [level_idx, spawns]
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
	visual.color = Color(0.85, 0.82, 0.75)
	body.add_child(visual)
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
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			var center := Vector2(c * TILE_SIZE + TILE_SIZE / 2, r * TILE_SIZE + TILE_SIZE / 2)
			match row.substr(c, 1):
				"#":
					level.add_child(_make_solid(c, r, center))
				"X":
					var tile := FallingTile.new()
					tile.name = "FallingTile_%d_%d" % [c, r]
					tile.position = center
					level.add_child(tile)
				"P":
					spawn = center
				"^":
					spike_cells.append(Vector2i(c, r))
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
