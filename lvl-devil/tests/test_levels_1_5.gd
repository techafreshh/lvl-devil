extends SceneTree
## Headless teach-beat proof: levels 1-5 are single-screen 20x11 grids using
## only legend chars, L3 dodges exactly once and stays catchable, the L4
## fake floor drops while its neighbor holds, and every chapter completes
## through scripted inputs. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_levels_1_5.gd
## Exits 1 when any check fails so CI can gate on the exit code.


var passed := 0
var failed := 0


func _initialize() -> void:
	await run_all()
	print("Results: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS teach chapters 1-5 shape and charset")
		print("PASS door-dodge teach witnessed once")
		print("PASS hidden-pit teach falls through")
		print("PASS scripted completion 1-5")
	quit(1 if failed > 0 else 0)


func run_all() -> void:
	# Nodes need a frame before they can enter the tree cleanly.
	await process_frame
	var tests := [
		"test_shape_11x20_charset_spawn",
		"test_l3_dodge_once_and_catchable",
		"test_l4_pit_falls_through",
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


func find_fleeing_door(mgr: GameManager) -> FleeingDoor:
	if mgr.level == null or not is_instance_valid(mgr.level):
		return null
	for child: Node in mgr.level.get_children():
		if child is FleeingDoor:
			return child as FleeingDoor
	return null


func t_center_of(idx: int) -> Vector2:
	var rows := Levels.get_level(idx)
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			if row.substr(c, 1) == "T":
				return cell_center(c, r)
	return Vector2(-1, -1)


func test_shape_11x20_charset_spawn() -> bool:
	var ok := true
	ok = expect(Levels.count() == 5, "shape: exactly 5 teach chapters (got %d)" % Levels.count()) and ok
	ok = expect(Levels.ALL.size() == 5, "shape: ALL holds 5 grids") and ok
	var allowed := "#P.^XdDTHV."
	for i: int in 5:
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
	# L3 holds the single fleeing pair and no static look-alike.
	var l3: PackedStringArray = Levels.get_level(2)
	ok = expect(count_char(l3, "D") == 1, "shape: L3 has exactly one D") and ok
	ok = expect(count_char(l3, "T") == 1, "shape: L3 has exactly one T") and ok
	ok = expect(count_char(l3, "d") == 0, "shape: L3 has no static d") and ok
	return ok


func test_l3_dodge_once_and_catchable() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(2), "l3-dodge: start_level(2) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var door := find_fleeing_door(mgr)
	ok = expect(door != null, "l3-dodge: fleeing door exists") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	var target := t_center_of(2)
	ok = expect(target.x >= 0.0, "l3-dodge: L3 has a T cell") and ok
	var marks: Array = []
	(door as FleeingDoor).dodged.connect(func(_d: Node) -> void: marks.append(Time.get_ticks_msec()))
	var exited_marks: Array = []
	(door as FleeingDoor).exited.connect(func(_d: Node) -> void: exited_marks.append(1))
	# Witness the dodge by walking: spawn->D is 352px, past the 160px
	# trigger range, so the dodge can only fire after leaving spawn.
	Input.action_press("move_right")
	var dodged := false
	for i: int in 600:
		await physics_frame
		await process_frame
		if not is_instance_valid(door) or not is_instance_valid(mgr.player):
			break
		if (door as FleeingDoor).has_dodged():
			dodged = true
			break
	ok = expect(dodged, "l3-dodge: dodge fires while walking in") and ok
	# The dodge lands the door on its T cell within ~0.3s (24 frames).
	var landed_frame := -1
	for i: int in 40:
		await physics_frame
		await process_frame
		if not is_instance_valid(door):
			break
		if (door as Node2D).global_position.distance_to(target) < 4.0:
			landed_frame = i
			break
	ok = expect(landed_frame >= 0 and landed_frame <= 24, "l3-dodge: door lands on T within 24 frames (got %d)" % landed_frame) and ok
	# Keep walking into the dodged door: touch must exit into level 3.
	var advanced := false
	for i: int in 900:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			break
		if mgr.current_level == 3 and mgr.level_idx == 3:
			advanced = true
			break
	Input.action_release("move_right")
	ok = expect(marks.size() == 1, "l3-dodge: exactly one dodged signal (got %d)" % marks.size()) and ok
	ok = expect(not exited_marks.is_empty(), "l3-dodge: touch after dodge emits exited") and ok
	ok = expect(advanced, "l3-dodge: dodged door advances 2->3") and ok
	await cleanup_manager(mgr)
	return ok


func test_l4_pit_falls_through() -> bool:
	var ok := true
	var level := LevelBuilder.build(3)
	ok = expect(level != null, "l4-pit: level 3 builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	await physics_frame
	var player := level.get_node_or_null("Player") as CharacterBody2D
	ok = expect(player != null, "l4-pit: Player exists") and ok
	if player == null:
		await free_level(level)
		return ok
	# Drop straight over the H cell (col 10, row 9): no collision, the
	# row-10 dot below leaves the world open.
	(player as Node2D).global_position = cell_center(10, 9) + Vector2(0, -60)
	(player as CharacterBody2D).velocity = Vector2.ZERO
	var ever_grounded := false
	for i: int in 90:
		await physics_frame
		if player.is_on_floor():
			ever_grounded = true
	var deep_y: float = (player as Node2D).global_position.y
	ok = expect(not ever_grounded, "l4-pit: never grounded over H") and ok
	ok = expect(deep_y > 352.0, "l4-pit: falls below row 10 over H (got %s)" % deep_y) and ok
	# The neighboring # cell (col 9, row 9) stays solid under the same drop.
	(player as Node2D).global_position = cell_center(9, 9) + Vector2(0, -60)
	(player as CharacterBody2D).velocity = Vector2.ZERO
	var settled := false
	for i: int in 90:
		await physics_frame
		if player.is_on_floor():
			settled = true
			break
	ok = expect(settled, "l4-pit: neighbor # catches the player") and ok
	var rest: Vector2 = (player as Node2D).global_position
	ok = expect(absf(rest.y - 275.0) <= 5.0, "l4-pit: neighbor rest y ~275 (got %s)" % rest.y) and ok
	ok = expect(absf(rest.x - 304.0) <= 6.0, "l4-pit: neighbor rest x ~304 (got %s)" % rest.x) and ok
	await free_level(level)
	return ok


## Position-triggered full jumps: press `jump` one frame when grounded in
## the window, hold ~20 physics frames past the apex so `cut_jump` never
## shortens the arc. L1 adds a trench-escape jump when grounded deep.
func wants_jump(idx: int, px: float, py: float) -> bool:
	match idx:
		0:
			return (px >= 150.0 and px <= 205.0) or py > 295.0
		1:
			return (px >= 180.0 and px <= 205.0) or (px >= 348.0 and px <= 366.0)
		2:
			return false
		3:
			return px >= 270.0 and px <= 310.0
		4:
			return px >= 415.0 and px <= 430.0
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
	for idx: int in 5:
		var done := await try_complete_level(idx)
		ok = expect(done, "completion: level %d completes within 1800 frames" % idx) and ok
	return ok
