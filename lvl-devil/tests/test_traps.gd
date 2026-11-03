extends SceneTree
## Headless trap-gauntlet behavior suite: proves every trap family together
## across the ten shipped chapters (indices 0-9) plus the end card. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_traps.gd
## (Godot has no `--test` flag; `--script` is the documented entry.)
## Exits 1 when any check fails so CI can gate on the exit code.


const SpikeScene := preload("res://scenes/spike.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

var passed := 0
var failed := 0
var _backup_exists := false
var _backup_text := ""


func _initialize() -> void:
	await run_all()
	print("Results: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS trigger-radius spikes ~1.2 tiles")
		print("PASS trigger-radius doors ~5 tiles")
		print("PASS drop-timing falling tiles ~0.12s")
		print("PASS flee-once runaway door")
		print("PASS reset-on-respawn ^XDHV")
		print("PASS death-to-playing <0.5s with freeze-frame ~0.1s")
		print("PASS shipped flow exactly 10 levels + end card")
	quit(1 if failed > 0 else 0)


func run_all() -> void:
	# Nodes need a frame before they can enter the tree cleanly.
	await process_frame
	_backup_save()
	var tests := [
		"test_documented_constants_exact",
		"test_dev_levels_valid",
		"test_trigger_radius_spikes",
		"test_trigger_radius_doors",
		"test_drop_timing_X",
		"test_flee_once_D",
		"test_spike_stays_extended_until_respawn",
		"test_hidden_solidity_HV",
		"test_shipped_flow_ten_plus_end",
		"test_reset_on_respawn",
		"test_dev_levels_stable_300_frames",
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


func has_row_with(rows: PackedStringArray, sub: String) -> bool:
	for row: String in rows:
		if row.contains(sub):
			return true
	return false


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


func player_at_spawn(mgr: GameManager) -> bool:
	if mgr.player == null or not is_instance_valid(mgr.player):
		return false
	return (mgr.player as Node2D).global_position.distance_to(mgr.spawn_pos) <= 2.0


func make_spike(at: Vector2) -> Area2D:
	var s := SpikeScene.instantiate() as Area2D
	s.position = at
	root.add_child(s)
	return s


func make_player(at: Vector2) -> CharacterBody2D:
	var p := PlayerScene.instantiate() as CharacterBody2D
	p.position = at
	p.add_to_group("player")
	root.add_child(p)
	return p


func spike_shape_disabled(spike: Area2D) -> bool:
	var col := spike.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		return false
	return col.disabled


func tile_shape_disabled(tile: FallingTile) -> bool:
	var col := tile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		return false
	return col.disabled


## Geometric standing check mirroring FallingTile.try_trigger.
func is_standing(player: Node2D, tile: FallingTile) -> bool:
	var d: Vector2 = player.global_position - tile.global_position
	if absf(d.x) > 29.0:
		return false
	var bottom: float = player.global_position.y + 13.0
	var top: float = tile.global_position.y - 16.0
	return bottom >= top - 6.0 and bottom <= top + 6.0


## Steps the player from `from_pos` toward `goal` in 10px hops without
## entering the exit overlap (stops 30px short).
func step_toward(mgr: GameManager, door: FleeingDoor, from_pos: Vector2, goal: Vector2, max_steps: int) -> void:
	var dir := (goal - from_pos).normalized()
	if dir.length() < 0.5:
		return
	var pos := from_pos
	for i: int in max_steps:
		if not is_instance_valid(mgr.player) or not is_instance_valid(door):
			return
		if door.has_dodged():
			return
		if pos.distance_to(goal) < 30.0:
			return
		(mgr.player as Node2D).global_position = pos
		(mgr.player as CharacterBody2D).velocity = Vector2.ZERO
		await physics_frame
		await process_frame
		pos += dir * 10.0


func first_visual(node: Node) -> ColorRect:
	for child: Node in node.get_children():
		if child is ColorRect:
			return child as ColorRect
	return null


func test_documented_constants_exact() -> bool:
	var ok := true
	ok = expect(FleeingDoor.TRIGGER_RANGE >= 150.0 and FleeingDoor.TRIGGER_RANGE <= 170.0, "constants: D TRIGGER_RANGE ~5 tiles (got %s)" % FleeingDoor.TRIGGER_RANGE) and ok
	ok = expect(FleeingDoor.SPAWN_GATE >= 28.0 and FleeingDoor.SPAWN_GATE <= 36.0, "constants: D SPAWN_GATE ~1 tile (got %s)" % FleeingDoor.SPAWN_GATE) and ok
	ok = expect(PopupSpike.TRIGGER_DX >= 34.0 and PopupSpike.TRIGGER_DX <= 42.0, "constants: ^ TRIGGER_DX ~1.2 tiles (got %s)" % PopupSpike.TRIGGER_DX) and ok
	ok = expect(PopupSpike.TRIGGER_SAME_ROW <= 16.0, "constants: ^ TRIGGER_SAME_ROW <= 16 (got %s)" % PopupSpike.TRIGGER_SAME_ROW) and ok
	ok = expect(FallingTile.SHAKE_TIME >= 0.10 and FallingTile.SHAKE_TIME <= 0.15, "constants: X SHAKE_TIME 0.10-0.15s (got %s)" % FallingTile.SHAKE_TIME) and ok
	ok = expect(GameManager.FREEZE_TIME >= 0.08 and GameManager.FREEZE_TIME <= 0.12, "constants: freeze FREEZE_TIME 0.08-0.12s (got %s)" % GameManager.FREEZE_TIME) and ok
	return ok


func test_dev_levels_valid() -> bool:
	var ok := true
	ok = expect(Levels.count() == 10, "dev-levels: exactly 10 chapters (got %d)" % Levels.count()) and ok
	ok = expect(Levels.ALL.size() == 10, "dev-levels: ALL holds 10 grids") and ok
	for i: int in 10:
		var rows: PackedStringArray = Levels.get_level(i)
		ok = expect(rows.size() == 11, "dev-levels: level %d has 11 rows (got %d)" % [i, rows.size()]) and ok
		for r: int in rows.size():
			ok = expect(rows[r].length() == 20, "dev-levels: level %d row %d is 20 wide (got %d)" % [i, r, rows[r].length()]) and ok
		ok = expect(count_char(rows, "P") == 1, "dev-levels: level %d has exactly one P" % i) and ok
		var reason := LevelBuilder.validate_grid(rows, i)
		ok = expect(reason == "", "dev-levels: level %d validates (got '%s')" % [i, reason]) and ok
		var level := LevelBuilder.build(i)
		ok = expect(level != null, "dev-levels: level %d builds" % i) and ok
		if level == null:
			continue
		root.add_child(level)
		await process_frame
		var spawn: Vector2 = (level.get_node_or_null("Player") as Node2D).global_position
		ok = expect(spawn.distance_to(Vector2(80, 272)) <= 1.0, "dev-levels: level %d spawns at (80, 272) (got %s)" % [i, spawn]) and ok
		await free_level(level)
	# Per-level teach beats: L1 falling X, L2 spike singles, L3 fleeing
	# door, L4 hidden pit, L5 static-door bait.
	var lvl1: PackedStringArray = Levels.get_level(0)
	ok = expect(has_row_with(lvl1, "XX"), "dev-levels: L1 chains X") and ok
	ok = expect(count_char(lvl1, "d") == 1 and count_char(lvl1, "D") == 0, "dev-levels: L1 has a lone static d") and ok
	var lvl2: PackedStringArray = Levels.get_level(1)
	ok = expect(count_char(lvl2, "^") == 2, "dev-levels: L2 keeps two ^ singles (got %d)" % count_char(lvl2, "^")) and ok
	ok = expect(count_char(lvl2, "d") == 1, "dev-levels: L2 has a static d") and ok
	ok = expect(count_char(lvl2, "D") == 0 and count_char(lvl2, "X") == 0, "dev-levels: L2 has no D/X") and ok
	var lvl3: PackedStringArray = Levels.get_level(2)
	ok = expect(count_char(lvl3, "D") == 1 and count_char(lvl3, "T") == 1, "dev-levels: L3 pairs one D with one T") and ok
	ok = expect(count_char(lvl3, "d") == 0, "dev-levels: L3 has no static d") and ok
	var lvl4: PackedStringArray = Levels.get_level(3)
	ok = expect(count_char(lvl4, "H") == 1, "dev-levels: L4 hides one H pit") and ok
	ok = expect(count_char(lvl4, "d") == 1, "dev-levels: L4 has a static d") and ok
	var lvl5: PackedStringArray = Levels.get_level(4)
	ok = expect(count_char(lvl5, "d") == 1, "dev-levels: L5 has a static d") and ok
	ok = expect(count_char(lvl5, "^") == 1, "dev-levels: L5 baits with one ^") and ok
	ok = expect(has_row_with(lvl5, "^.d"), "dev-levels: L5 parks ^ beside d") and ok
	# Escalation chapters: L6 chained X, L7 ^+X, L8 sparing V, L9 full
	# stack with a fleeing pair, L10 spike-guarded bait plus true exit.
	var lvl6: PackedStringArray = Levels.get_level(5)
	ok = expect(has_row_with(lvl6, "XX"), "dev-levels: L6 chains X") and ok
	ok = expect(count_char(lvl6, "d") == 1 and count_char(lvl6, "D") == 0, "dev-levels: L6 has a lone static d") and ok
	var lvl7: PackedStringArray = Levels.get_level(6)
	ok = expect(count_char(lvl7, "^") == 2, "dev-levels: L7 keeps two ^ singles (got %d)" % count_char(lvl7, "^")) and ok
	ok = expect(count_char(lvl7, "X") >= 1, "dev-levels: L7 keeps its X run-up") and ok
	var lvl8: PackedStringArray = Levels.get_level(7)
	ok = expect(count_char(lvl8, "V") == 1, "dev-levels: L8 hides one V (got %d)" % count_char(lvl8, "V")) and ok
	ok = expect(count_char(lvl8, "d") == 1, "dev-levels: L8 has a static d") and ok
	var lvl9: PackedStringArray = Levels.get_level(8)
	ok = expect(count_char(lvl9, "H") >= 1 and count_char(lvl9, "V") >= 1 and count_char(lvl9, "X") >= 1, "dev-levels: L9 stacks H+V+X") and ok
	ok = expect(count_char(lvl9, "D") == 1 and count_char(lvl9, "T") == 1, "dev-levels: L9 pairs one D with one T") and ok
	var lvl10: PackedStringArray = Levels.get_level(9)
	ok = expect(count_char(lvl10, "d") + count_char(lvl10, "D") >= 2, "dev-levels: L10 holds two doors") and ok
	ok = expect(has_row_with(lvl10, "^d"), "dev-levels: L10 baits ^ beside d") and ok
	return ok


func test_trigger_radius_spikes() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	var player := make_player(Vector2(160, 0))
	await process_frame
	# 5 tiles away (~160px): retracted over 10 physics frames, shape disabled.
	for i: int in 10:
		await physics_frame
	ok = expect(not (spike as PopupSpike).is_active(), "spike-radius: retracted at ~5 tiles (160px)") and ok
	ok = expect(spike_shape_disabled(spike), "spike-radius: shape disabled while retracted") and ok
	# Same-row within ~1.2 tiles (38px): latched within 2 frames.
	(player as Node2D).global_position = Vector2(38, 0)
	for i: int in 2:
		await physics_frame
		if (spike as PopupSpike).is_active():
			break
	ok = expect((spike as PopupSpike).is_active(), "spike-radius: active within 2 frames at ~1.2 tiles") and ok
	if is_instance_valid(spike):
		spike.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await sweep_strays()
	return ok


func test_trigger_radius_doors() -> bool:
	var ok := true
	# D (~128px, inside the ~5-tile / 160px range) with its T landing cell.
	var rows := PackedStringArray(["..........", "..P...D.T.", "##########"])
	ok = expect(LevelBuilder.validate_grid(rows, 41) == "", "door-radius: D+T grid validates") and ok
	var level := LevelBuilder.build_from_rows(rows, 41)
	ok = expect(level != null, "door-radius: D+T grid builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	await physics_frame
	var door: FleeingDoor = null
	for child: Node in level.get_children():
		if child is FleeingDoor:
			door = child as FleeingDoor
			break
	ok = expect(door != null, "door-radius: door node exists") and ok
	if door == null:
		await free_level(level)
		return ok
	var player := level.get_node_or_null("Player") as CharacterBody2D
	var door_home: Vector2 = (door as Node2D).global_position
	# Settle onto the floor, then the unmoved player must never trip the dodge.
	for i: int in 10:
		await physics_frame
	var base: Vector2 = (player as Node2D).global_position
	for i: int in 120:
		await physics_frame
	ok = expect(not door.has_dodged(), "door-radius: no dodge over 120 unmoved frames inside ~5 tiles") and ok
	ok = expect((door as Node2D).global_position.distance_to(door_home) < 2.0, "door-radius: door drift <2px while player idle") and ok
	# Walk toward the door: leaving spawn and approaching must trip the dodge.
	var goal: Vector2 = (door as Node2D).global_position
	var pos := base
	var dir := (goal - base).normalized()
	var dodged_frame := -1
	for i: int in 40:
		if door.has_dodged():
			dodged_frame = i
			break
		(player as Node2D).global_position = pos
		(player as CharacterBody2D).velocity = Vector2(170, 0)
		await physics_frame
		await process_frame
		if pos.distance_to(goal) > 30.0:
			pos += dir * 10.0
	ok = expect(door.has_dodged(), "door-radius: dodge fires after leaving spawn and approaching") and ok
	ok = expect((player as Node2D).global_position.distance_to(base) > 32.0, "door-radius: player left the spawn gate (>32px)") and ok
	# The dodge lands the door on its T cell within ~0.3s (>=24 physics frames).
	var target := cell_center(8, 1)
	var landed_frame := -1
	for i: int in 40:
		await physics_frame
		await process_frame
		if (door as Node2D).global_position.distance_to(target) < 4.0:
			landed_frame = i
			break
	ok = expect(landed_frame >= 0 and landed_frame <= 24, "door-radius: door lands on T within 24 frames (got %d)" % landed_frame) and ok
	await free_level(level)
	return ok


func test_drop_timing_X() -> bool:
	var ok := true
	var tile_a := FallingTile.new()
	tile_a.position = Vector2(80, 100)
	root.add_child(tile_a)
	var tile_b := FallingTile.new()
	tile_b.position = Vector2(400, 100)
	root.add_child(tile_b)
	# Player stands exactly on tile A (bottom 84 = tile top 84).
	var player := make_player(Vector2(80, 71))
	await process_frame
	var latch_a := -1
	var drop_a := -1
	var latch_b := -1
	var drop_b := -1
	var moved_b := false
	for f: int in 70:
		await physics_frame
		if tile_a.is_shaking() or tile_a.has_dropped():
			if latch_a < 0:
				latch_a = f
		if tile_a.has_dropped() and drop_a < 0:
			drop_a = f
		# Second tile steps on 12 frames after the first latched.
		if latch_a >= 0 and not moved_b and f >= latch_a + 12:
			(player as Node2D).global_position = Vector2(400, 71)
			(player as CharacterBody2D).velocity = Vector2.ZERO
			moved_b = true
		if moved_b and (tile_b.is_shaking() or tile_b.has_dropped()):
			if latch_b < 0:
				latch_b = f
		if tile_b.has_dropped() and drop_b < 0:
			drop_b = f
		if drop_a >= 0 and drop_b >= 0:
			break
	ok = expect(latch_a >= 0 and latch_a <= 2, "drop-timing: first tile latches on standing (frame %d)" % latch_a) and ok
	if latch_a >= 0:
		ok = expect(drop_a < 0 or drop_a > latch_a + 5, "drop-timing: no drop in the first 5 physics frames") and ok
	ok = expect(drop_a >= 0 and drop_a >= latch_a + 6 and drop_a <= latch_a + 9, "drop-timing: first tile drops 6-9 frames after latch (~0.10-0.15s, latch %d drop %d)" % [latch_a, drop_a]) and ok
	if drop_a >= 0 and latch_a >= 0:
		var shake_ms := int(round(float(drop_a - latch_a) * 1000.0 / 60.0))
		print("drop-timing: shake %d frames (~%dms, spec 0.10-0.15s)" % [drop_a - latch_a, shake_ms])
	if drop_a >= 0:
		ok = expect(tile_a.position.y - tile_a.home_pos().y > 16.0, "drop-timing: tile falls >16px (got %s)" % (tile_a.position.y - tile_a.home_pos().y)) and ok
		await process_frame
		ok = expect(tile_shape_disabled(tile_a), "drop-timing: shape disabled once falling") and ok
	ok = expect(moved_b and latch_b >= 0, "drop-timing: second tile latches on its own step") and ok
	ok = expect(drop_a >= 0 and drop_b >= 0, "drop-timing: both tiles drop") and ok
	if drop_a >= 0 and drop_b >= 0:
		var gap := drop_b - drop_a
		ok = expect(gap >= 6 and gap <= 19, "drop-timing: chained drops 6-19 frames apart (got %d)" % gap) and ok
	if is_instance_valid(tile_a):
		tile_a.queue_free()
	if is_instance_valid(tile_b):
		tile_b.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await sweep_strays()
	return ok


func test_flee_once_D() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(2), "flee-once: start_level(2) builds L3") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	# Pin the fleeing D cell (not the static d fakeout) from the grid.
	var rows: PackedStringArray = Levels.get_level(2)
	var d_pos := Vector2(-1, -1)
	for r: int in rows.size():
		for c: int in rows[r].length():
			if rows[r].substr(c, 1) == "D":
				d_pos = cell_center(c, r)
	ok = expect(d_pos.x >= 0.0, "flee-once: L3 grid has a D cell") and ok
	var door: FleeingDoor = null
	for child: Node in mgr.level.get_children():
		if child is FleeingDoor and (child as Node2D).global_position.distance_to(d_pos) <= 1.0:
			door = child as FleeingDoor
			break
	ok = expect(door != null, "flee-once: fleeing door node exists at the D cell") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	var marks: Array = []
	door.dodged.connect(func(_d: Node) -> void: marks.append(Time.get_ticks_msec()))
	var dir := ((door as Node2D).global_position - spawn).normalized()
	await step_toward(mgr, door, spawn + dir * 40.0, (door as Node2D).global_position, 30)
	ok = expect(door.has_dodged(), "flee-once: dodge fires after leaving spawn") and ok
	for i: int in 40:
		await process_frame
		await physics_frame
	# Re-approach in the same attempt: exactly one dodge, position holds.
	var after: Vector2 = (door as Node2D).global_position
	await step_toward(mgr, door, after + Vector2(-100, 0), after, 20)
	ok = expect(marks.size() == 1, "flee-once: no second dodge on re-approach (got %d)" % marks.size()) and ok
	ok = expect((door as Node2D).global_position.distance_to(after) < 2.0, "flee-once: door holds position on re-approach") and ok
	# Still catchable: touching the dodged door exits into the next dev level.
	var exited_marks: Array = []
	door.exited.connect(func(_d: Node) -> void: exited_marks.append(1))
	(mgr.player as Node2D).global_position = (door as Node2D).global_position
	var t0 := Time.get_ticks_msec()
	var advanced := false
	for i: int in 90:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			break
		if mgr.current_level == 3 and mgr.level_idx == 3:
			advanced = true
			break
		if Time.get_ticks_msec() - t0 > 800:
			break
	ok = expect(not exited_marks.is_empty(), "flee-once: touch after dodge emits exited") and ok
	ok = expect(advanced, "flee-once: dodged door still advances the gauntlet") and ok
	await cleanup_manager(mgr)
	return ok


func test_spike_stays_extended_until_respawn() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(1), "spike-dwell: start_level(1) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var spike: PopupSpike = null
	for child: Node in mgr.level.get_children():
		if child is PopupSpike:
			spike = child as PopupSpike
			break
	ok = expect(spike != null, "spike-dwell: level has a spike") and ok
	if spike == null:
		await cleanup_manager(mgr)
		return ok
	# Latch headless-decoupled, then prove it stays out for a full second.
	ok = expect(spike.try_trigger((spike as Node2D).global_position), "spike-dwell: try_trigger latches") and ok
	for i: int in 60:
		await physics_frame
		ok = expect(spike.is_active(), "spike-dwell: spike holds frame %d without respawn" % i) and ok
		ok = expect(not spike_shape_disabled(spike), "spike-dwell: shape stays enabled frame %d" % i) and ok
		if not ok:
			break
	if not ok:
		await cleanup_manager(mgr)
		return ok
	# Teleport onto the spike: the kill owns the death-to-playing clock.
	var kill_marks: Array = []
	spike.killed.connect(func(_s: Node) -> void: kill_marks.append(Time.get_ticks_msec()))
	var t0 := Time.get_ticks_msec()
	(mgr.player as Node2D).global_position = (spike as Node2D).global_position
	var old_player := mgr.player
	await physics_frame
	await physics_frame
	var back := false
	var t_spawn := 0
	for i: int in 60:
		await process_frame
		if player_at_spawn(mgr) and mgr.player != old_player:
			t_spawn = Time.get_ticks_msec()
			back = true
			break
	ok = expect(back, "spike-dwell: death returns to P") and ok
	if not back:
		await cleanup_manager(mgr)
		return ok
	var total := t_spawn - t0
	ok = expect(total < 500, "spike-dwell: death-to-playing <0.5s (got %dms)" % total) and ok
	ok = expect(not kill_marks.is_empty(), "spike-dwell: killed fired") and ok
	if not kill_marks.is_empty():
		var held := t_spawn - int(kill_marks[0])
		print("spike-dwell: freeze-frame %dms (spec ~0.1s)" % held)
		ok = expect(held >= 50 and held <= 300, "spike-dwell: freeze-frame 50-300ms (got %dms)" % held) and ok
	await process_frame
	await physics_frame
	await process_frame
	var fresh: PopupSpike = null
	for child: Node in mgr.level.get_children():
		if child is PopupSpike:
			fresh = child as PopupSpike
			break
	ok = expect(fresh != null and not fresh.is_active(), "spike-dwell: rebuilt spike retracted") and ok
	if fresh != null:
		ok = expect(spike_shape_disabled(fresh), "spike-dwell: rebuilt spike shape disabled") and ok
	await cleanup_manager(mgr)
	return ok


func test_hidden_solidity_HV() -> bool:
	var ok := true
	var pit := LevelBuilder.build(3)
	ok = expect(pit != null, "hv: build(3) builds L4") and ok
	if pit == null:
		return ok
	root.add_child(pit)
	await process_frame
	var fake: Node = null
	for child: Node in pit.get_children():
		if (child as Node).name.begins_with("FakeFloor_"):
			fake = child
			break
	ok = expect(fake != null, "hv: L4 has a FakeFloor_* node") and ok
	if fake != null:
		ok = expect(not (fake is StaticBody2D), "hv: H is never a StaticBody2D") and ok
		ok = expect(not fake.is_in_group("solid_tiles"), "hv: H never joins solid_tiles") and ok
		var solid: Node = null
		for child: Node in pit.get_children():
			if child is StaticBody2D and (child as Node).name.begins_with("Solid_") and first_visual(child) != null:
				solid = child
				break
		var fv := first_visual(fake)
		var sv := first_visual(solid)
		ok = expect(fv != null and sv != null, "hv: H and # both keep visuals") and ok
		if fv != null and sv != null:
			ok = expect(fv.color == sv.color, "hv: H color identical to #") and ok
			ok = expect(fv.size == sv.size, "hv: H size identical to #") and ok
			ok = expect(fv.position == sv.position, "hv: H offset identical to #") and ok
	await free_level(pit)
	var rows8: PackedStringArray = Levels.get_level(7)
	var vname := ""
	for r: int in rows8.size():
		for c: int in rows8[r].length():
			if rows8[r].substr(c, 1) == "V":
				vname = "Solid_%d_%d" % [c, r]
	ok = expect(vname != "", "hv: L8 grid hides one V") and ok
	var corridor := LevelBuilder.build(7)
	ok = expect(corridor != null, "hv: build(7) builds L8") and ok
	if corridor == null:
		return ok
	var wall := corridor.get_node_or_null(vname)
	ok = expect(wall != null, "hv: L8 V cell %s exists" % vname) and ok
	if wall != null:
		ok = expect(wall is StaticBody2D, "hv: V is a StaticBody2D") and ok
		ok = expect(wall.is_in_group("solid_tiles"), "hv: V joins solid_tiles") and ok
		ok = expect((wall as Node).find_children("*", "ColorRect", true, false).is_empty(), "hv: V draws no visible tile") and ok
	await free_level(corridor)
	return ok


func test_shipped_flow_ten_plus_end() -> bool:
	var ok := true
	ok = expect(Levels.count() == 10, "flow: shipped count is exactly 10 (got %d)" % Levels.count()) and ok
	ok = expect(Levels.ALL.size() == 10, "flow: ALL holds 10 grids") and ok
	ok = expect(Levels.get_level(-1).is_empty(), "flow: index -1 gated outside 0-9") and ok
	ok = expect(Levels.get_level(10).is_empty(), "flow: index 10 gated outside 0-9") and ok
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "flow: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	var voices := mgr.find_children("*", "AudioStreamPlayer", true, false)
	ok = expect(voices.size() == 5, "flow: Sfx bus holds 5 voices (got %d)" % voices.size()) and ok
	ok = expect(mgr.title != null and not (mgr.title as CanvasLayer).visible, "flow: title hidden during play") and ok
	ok = expect(mgr.end_card != null and not (mgr.end_card as CanvasLayer).visible, "flow: end card hidden during play") and ok
	ok = expect(mgr.state == GameManager.State.PLAYING, "flow: state PLAYING after start_level(0)") and ok
	await cleanup_manager(mgr)
	return ok


func test_reset_on_respawn() -> bool:
	var ok := true
	var respawn_times: Array = []
	for idx: int in 10:
		var mgr := make_manager()
		await process_frame
		ok = expect(mgr.start_level(idx), "reset: start_level(%d) builds" % idx) and ok
		if not ok:
			await cleanup_manager(mgr)
			return ok
		await process_frame
		await physics_frame
		var rows: PackedStringArray = Levels.get_level(idx)
		# Trip every trap on the level without overlapping a kill zone.
		for child: Node in mgr.level.get_children():
			if child is PopupSpike:
				(mgr.player as Node2D).global_position = (child as Node2D).global_position + Vector2(-30, 0)
				(mgr.player as CharacterBody2D).velocity = Vector2.ZERO
				for i: int in 5:
					await physics_frame
				ok = expect((child as PopupSpike).is_active(), "reset: level %d spike latches before death" % idx) and ok
		for child: Node in mgr.level.get_children():
			if child is FallingTile:
				var tile := child as FallingTile
				(mgr.player as Node2D).global_position = tile.global_position + Vector2(0, -29)
				(mgr.player as CharacterBody2D).velocity = Vector2.ZERO
				var latched := false
				for i: int in 30:
					await physics_frame
					if tile.is_shaking() or tile.has_dropped():
						latched = true
						break
				ok = expect(latched, "reset: level %d X tile trips before death" % idx) and ok
				break
		for child: Node in mgr.level.get_children():
			if child is FleeingDoor:
				var dc := child as FleeingDoor
				var dcell := Vector2(-1, -1)
				for r: int in rows.size():
					for c: int in rows[r].length():
						if rows[r].substr(c, 1) == "D":
							dcell = cell_center(c, r)
				if dcell.x >= 0.0 and (dc as Node2D).global_position.distance_to(dcell) <= 1.0:
					var spawn: Vector2 = mgr.spawn_pos
					var ddir := ((dc as Node2D).global_position - spawn).normalized()
					await step_toward(mgr, dc, spawn + ddir * 40.0, (dc as Node2D).global_position, 30)
					ok = expect(dc.has_dodged(), "reset: level %d D door dodges before death" % idx) and ok
		# Force death; the trip above never overlaps, so this call owns the clock.
		var old_player := mgr.player
		var t0 := Time.get_ticks_msec()
		mgr.request_death("trap-proof")
		var back := false
		var elapsed := 0
		for i: int in 60:
			await process_frame
			if player_at_spawn(mgr) and mgr.player != old_player:
				elapsed = Time.get_ticks_msec() - t0
				back = true
				break
		ok = expect(back, "reset: level %d death returns to P" % idx) and ok
		if back:
			ok = expect(elapsed < 500, "reset: level %d respawn <0.5s (got %dms)" % [idx, elapsed]) and ok
			respawn_times.append(elapsed)
		else:
			await cleanup_manager(mgr)
			return ok
		await process_frame
		await physics_frame
		await process_frame
		# Fresh rebuild: every trap family back at grid state.
		for child: Node in mgr.level.get_children():
			if child is PopupSpike:
				ok = expect(not (child as PopupSpike).is_active(), "reset: level %d ^ retracted after respawn" % idx) and ok
			if child is FallingTile:
				var tile := child as FallingTile
				ok = expect(tile.position.distance_to(tile.home_pos()) <= 1.0, "reset: level %d X home after respawn" % idx) and ok
				ok = expect(not tile.is_shaking() and not tile.has_dropped(), "reset: level %d X idle+solid after respawn" % idx) and ok
				ok = expect(not tile_shape_disabled(tile), "reset: level %d X collision back after respawn" % idx) and ok
		var want_doors := []
		for r: int in rows.size():
			for c: int in rows[r].length():
				var ch: String = rows[r].substr(c, 1)
				if ch == "d" or ch == "D":
					want_doors.append(cell_center(c, r))
		var n_doors := 0
		for child: Node in mgr.level.get_children():
			if child is FleeingDoor:
				n_doors += 1
				var at_home := false
				for w: Vector2 in want_doors:
					if (child as Node2D).global_position.distance_to(w) <= 1.0:
						at_home = true
				ok = expect(at_home, "reset: level %d door home after respawn" % idx) and ok
				ok = expect(not (child as FleeingDoor).has_dodged(), "reset: level %d door undodged after respawn" % idx) and ok
		ok = expect(n_doors == want_doors.size(), "reset: level %d keeps %d doors" % [idx, want_doors.size()]) and ok
		var solid_visual := first_visual(mgr.level.get_node_or_null("Solid_0_9"))
		for child: Node in mgr.level.get_children():
			if child is Node2D and (child as Node).name.begins_with("FakeFloor_"):
				var fv := first_visual(child)
				ok = expect(fv != null, "reset: level %d H keeps its visual" % idx) and ok
				if fv != null and solid_visual != null:
					ok = expect(fv.color == solid_visual.color and fv.size == solid_visual.size and fv.position == solid_visual.position, "reset: level %d H color-identical after respawn" % idx) and ok
			if child is StaticBody2D and not (child is FallingTile) and (child as Node).name.begins_with("Solid_"):
				var parts := (child as Node).name.split("_")
				if parts.size() == 3 and rows[parts[2].to_int()].substr(parts[1].to_int(), 1) == "V":
					ok = expect((child as Node).is_in_group("solid_tiles"), "reset: level %d V still blocking after respawn" % idx) and ok
					ok = expect((child as Node).find_children("*", "ColorRect", true, false).is_empty(), "reset: level %d V still invisible after respawn" % idx) and ok
		await cleanup_manager(mgr)
	if not respawn_times.is_empty():
		var mn := int(respawn_times[0])
		var mx := int(respawn_times[0])
		var total_ms := 0
		for ms in respawn_times:
			mn = mini(mn, int(ms))
			mx = maxi(mx, int(ms))
			total_ms += int(ms)
		var avg := int(round(float(total_ms) / float(respawn_times.size())))
		print("reset: respawn-to-playing min/max/avg %d/%d/%dms (spec <500ms)" % [mn, mx, avg])
	return ok


func test_dev_levels_stable_300_frames() -> bool:
	var ok := true
	for idx: int in 10:
		var mgr := make_manager()
		await process_frame
		ok = expect(mgr.start_level(idx), "stable: start_level(%d) builds" % idx) and ok
		if not ok:
			await cleanup_manager(mgr)
			return ok
		await process_frame
		# Hold right for 300 headless physics frames; completing is the probe:
		# doors may advance (and wrap), falls may kill and respawn, but the
		# tree must never hang or lose the player.
		Input.action_press("move_right")
		for i: int in 300:
			await physics_frame
		Input.action_release("move_right")
		ok = expect(is_instance_valid(mgr) and is_instance_valid(mgr.level), "stable: level %d tree intact after 300 frames" % idx) and ok
		ok = expect(is_instance_valid(mgr.player), "stable: level %d player intact after 300 frames" % idx) and ok
		if is_instance_valid(mgr.player):
			var p: Vector2 = (mgr.player as Node2D).global_position
			ok = expect(p.x > -200.0 and p.x < 900.0 and p.y < 600.0, "stable: level %d player sane after 300 frames (got %s)" % [idx, p]) and ok
		ok = expect(mgr.current_level >= 0 and mgr.current_level < 10, "stable: level %d gauntlet index sane" % idx) and ok
		await cleanup_manager(mgr)
	return ok
