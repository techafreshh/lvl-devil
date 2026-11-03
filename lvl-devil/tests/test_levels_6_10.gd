extends SceneTree
## Headless escalation proof: levels 6-10 are single-screen 20x11 grids
## using only legend chars, L8 hides a sparing V wall, L9 stacks H+V+X+D+T,
## L10 baits with a spike-guarded d before the true exit, and every chapter
## completes through scripted inputs. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_levels_6_10.gd
## Exits 1 when any check fails so CI can gate on the exit code.


var passed := 0
var failed := 0
var _backup_exists := false
var _backup_text := ""


func _initialize() -> void:
	await run_all()
	print("Results: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS escalation chapters 6-10 shape and charset")
		print("PASS finale first-door trapped with reachable exit")
		print("PASS scripted completion 6-10")
	quit(1 if failed > 0 else 0)


func run_all() -> void:
	# Nodes need a frame before they can enter the tree cleanly.
	await process_frame
	_backup_save()
	var tests := [
		"test_shape_11x20_charset_spawn",
		"test_l10_first_door_trapped",
		"test_completion_all_paths",
	]
	for t: String in tests:
		release_all()
		var ok = await call(t)
		release_all()
		if ok == true:
			passed += 1
			print("PASS " + t)
		else:
			failed += 1
			push_error("FAIL " + t + ": did not finish (runtime error?)")
		# Flush freed nodes so the next test starts from a clean tree.
		await process_frame
	_restore_save()


## Non-counting check helper: never use bare assert() in a SceneTree runner.
func expect(cond: bool, label: String) -> bool:
	if not cond:
		push_error("FAIL " + label)
	return cond


func release_all() -> void:
	for a: String in ["move_left", "move_right", "jump"]:
		Input.action_release(a)


func count_char(rows: PackedStringArray, target: String) -> int:
	var n := 0
	for row: String in rows:
		for c: int in row.length():
			if row.substr(c, 1) == target:
				n += 1
	return n


func cell_center(col: int, row: int) -> Vector2:
	return Vector2(col * 32 + 16, row * 32 + 16)


func make_manager() -> GameManager:
	var mgr := GameManager.new()
	mgr.name = "Game"
	root.add_child(mgr)
	return mgr


func cleanup_manager(mgr: GameManager) -> void:
	if is_instance_valid(mgr):
		mgr.queue_free()
	await sweep_strays()


## Frees stray level/group nodes, then settles two frames of hygiene.
func sweep_strays() -> void:
	for n: Node in root.get_children():
		if n.is_in_group("player") or n.is_in_group("spikes") or n.is_in_group("doors") or n.is_in_group("falling_tiles") or n.is_in_group("solid_tiles") or n.name == "Level":
			n.queue_free()
	await process_frame
	await physics_frame


func free_level(level: Node) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await sweep_strays()


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _backup_save() -> void:
	_backup_exists = FileAccess.file_exists(Save.SAVE_PATH)
	if _backup_exists:
		_backup_text = _read_text(Save.SAVE_PATH)


func _restore_save() -> void:
	if _backup_exists:
		_write_text(Save.SAVE_PATH, _backup_text)
	else:
		_wipe(Save.SAVE_PATH)


func first_door_cell(rows: PackedStringArray) -> Vector2i:
	for r: int in rows.size():
		for c: int in rows[r].length():
			var ch: String = rows[r].substr(c, 1)
			if ch == "d" or ch == "D":
				return Vector2i(c, r)
	return Vector2i(-1, -1)


func test_shape_11x20_charset_spawn() -> bool:
	var ok := true
	ok = expect(Levels.count() == 10, "shape: exactly 10 chapters (got %d)" % Levels.count()) and ok
	ok = expect(Levels.ALL.size() == 10, "shape: ALL holds 10 grids") and ok
	var allowed := "#P.^XdDTHV."
	for i: int in range(5, 10):
		var rows: PackedStringArray = Levels.get_level(i)
		ok = expect(rows.size() == 11, "shape: level %d has 11 rows (got %d)" % [i, rows.size()]) and ok
		for r: int in rows.size():
			ok = expect(rows[r].length() == 20, "shape: level %d row %d is 20 wide (got %d)" % [i, r, rows[r].length()]) and ok
			for c: int in rows[r].length():
				var ch: String = rows[r].substr(c, 1)
				ok = expect(allowed.contains(ch), "shape: level %d row %d col %d char '%s' allowed" % [i, r, c, ch]) and ok
		ok = expect(count_char(rows, "P") == 1, "shape: level %d has exactly one P" % i) and ok
		var reason := LevelBuilder.validate_grid(rows, i)
		ok = expect(reason == "", "shape: level %d validates (got '%s')" % [i, reason]) and ok
		var level := LevelBuilder.build(i)
		ok = expect(level != null, "shape: level %d builds" % i) and ok
		if level == null:
			continue
		root.add_child(level)
		await process_frame
		var spawn: Vector2 = (level.get_node_or_null("Player") as Node2D).global_position
		ok = expect(spawn.distance_to(Vector2(80, 272)) <= 1.0, "shape: level %d spawns at (80, 272) (got %s)" % [i, spawn]) and ok
		await free_level(level)
	# L6 chains falling tiles and keeps a lone static exit.
	var l6: PackedStringArray = Levels.get_level(5)
	var l6r9: String = l6[9]
	ok = expect(l6r9.contains("XX"), "shape: L6 chains X") and ok
	ok = expect(count_char(l6, "d") == 1 and count_char(l6, "D") == 0, "shape: L6 has a lone static d") and ok
	# L7 pairs pop-up spikes with a falling run-up and a static exit.
	var l7: PackedStringArray = Levels.get_level(6)
	ok = expect(count_char(l7, "^") == 2, "shape: L7 keeps two ^ singles (got %d)" % count_char(l7, "^")) and ok
	ok = expect(count_char(l7, "X") >= 1, "shape: L7 keeps its X run-up") and ok
	ok = expect(count_char(l7, "d") == 1, "shape: L7 has a static d") and ok
	# L8 hides a sparing wall: one to three V cells, static exit, no gauntlet.
	var l8: PackedStringArray = Levels.get_level(7)
	var nv := count_char(l8, "V")
	ok = expect(nv >= 1 and nv <= 3, "shape: L8 hides 1-3 V cells (got %d)" % nv) and ok
	ok = expect(count_char(l8, "d") == 1, "shape: L8 has a static d") and ok
	ok = expect(count_char(l8, "D") == 0 and count_char(l8, "T") == 0, "shape: L8 has no fleeing pair") and ok
	# L9 stacks every family: H, V and X plus one fleeing D->T pair.
	var l9: PackedStringArray = Levels.get_level(8)
	ok = expect(count_char(l9, "H") >= 1, "shape: L9 hides at least one H") and ok
	ok = expect(count_char(l9, "V") >= 1, "shape: L9 hides at least one V") and ok
	ok = expect(count_char(l9, "X") >= 1, "shape: L9 chains at least one X") and ok
	ok = expect(count_char(l9, "D") == 1 and count_char(l9, "T") == 1, "shape: L9 pairs one D with one T") and ok
	ok = expect(count_char(l9, "d") == 0, "shape: L9 has no static d") and ok
	# L10 finale: at least two door cells, no fleeing pair.
	var l10: PackedStringArray = Levels.get_level(9)
	var doors := count_char(l10, "d") + count_char(l10, "D")
	ok = expect(doors >= 2, "shape: L10 holds at least two door cells (got %d)" % doors) and ok
	ok = expect(count_char(l10, "D") == 0 and count_char(l10, "T") == 0, "shape: L10 has no fleeing pair") and ok
	return ok


func test_l10_first_door_trapped() -> bool:
	var ok := true
	var rows: PackedStringArray = Levels.get_level(9)
	var first := first_door_cell(rows)
	ok = expect(first.x >= 0, "l10-trap: L10 has a door cell") and ok
	if first.x < 0:
		return ok
	# Row-major first door is the bait: a pop-up spike within Chebyshev 2.
	var guarded := false
	for r: int in rows.size():
		for c: int in rows[r].length():
			if rows[r].substr(c, 1) == "^" and maxi(abs(c - first.x), abs(r - first.y)) <= 2:
				guarded = true
	ok = expect(guarded, "l10-trap: first d at (%d, %d) is spike-guarded" % [first.x, first.y]) and ok
	# A second door cell exists whose below-cell is solid (#) or net (X),
	# so the true exit is reachable by walking/jumping.
	var second := Vector2i(-1, -1)
	for r: int in rows.size():
		for c: int in rows[r].length():
			var ch: String = rows[r].substr(c, 1)
			if (ch == "d" or ch == "D") and Vector2i(c, r) != first:
				second = Vector2i(c, r)
				break
		if second.x >= 0:
			break
	ok = expect(second.x >= 0, "l10-trap: L10 has a second door cell") and ok
	if second.x >= 0:
		var below := ""
		if second.y + 1 < rows.size():
			below = rows[second.y + 1].substr(second.x, 1)
		ok = expect(below == "#" or below == "X", "l10-trap: exit door at (%d, %d) stands on '%s'" % [second.x, second.y, below]) and ok
	return ok


## Position-triggered full jumps: press `jump` one frame when grounded in
## the window, hold ~20 physics frames past the apex so `cut_jump` never
## shortens the arc. Trench escapes jump when grounded deep (py > 295).
## L8 has a full floor, so its window only fires ahead of the V wall face
## (the upper bound includes the wall-clamp x for missed-jump retries).
func wants_jump(idx: int, px: float, py: float) -> bool:
	match idx:
		5:
			return (px >= 150.0 and px <= 205.0) or py > 295.0
		6:
			return (px >= 245.0 and px <= 270.0) or (px >= 372.0 and px <= 390.0) or py > 295.0
		7:
			return px >= 295.0 and px <= 345.0
		8:
			return (px >= 395.0 and px <= 440.0) or (px >= 270.0 and px <= 310.0) or py > 295.0
		9:
			return (px >= 310.0 and px <= 335.0) or py > 295.0
	return false


func try_complete_level(idx: int) -> bool:
	var mgr := make_manager()
	await process_frame
	if not mgr.start_level(idx):
		await cleanup_manager(mgr)
		return false
	await process_frame
	await physics_frame
	var want := (idx + 1) % Levels.count()
	Input.action_press("move_right")
	var hold := 0
	var known_player: Node = mgr.player
	var completed := false
	for f: int in 1800:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			break
		if mgr.current_level == want and mgr.level_idx == want:
			completed = true
			break
		if mgr.player == null or not is_instance_valid(mgr.player):
			hold = 0
			Input.action_release("jump")
			known_player = null
			continue
		if mgr.player != known_player:
			known_player = mgr.player
			hold = 0
			Input.action_release("jump")
		var p := mgr.player as CharacterBody2D
		if p == null:
			continue
		if hold > 0:
			hold -= 1
			if hold == 0:
				Input.action_release("jump")
		elif p.is_on_floor():
			var pos := (p as Node2D).global_position
			if wants_jump(idx, pos.x, pos.y):
				Input.action_press("jump")
				hold = 20
	Input.action_release("move_right")
	Input.action_release("jump")
	await cleanup_manager(mgr)
	return completed


func test_completion_all_paths() -> bool:
	var ok := true
	for idx: int in range(5, 10):
		var done := await try_complete_level(idx)
		ok = expect(done, "completion: level %d completes within 1800 frames" % idx) and ok
	return ok
