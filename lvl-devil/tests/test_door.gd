extends SceneTree
## Headless door tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_door.gd
## Exits 1 when any check fails so CI can gate on the exit code.


var passed := 0
var failed := 0


func _initialize() -> void:
	await run_all()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func run_all() -> void:
	# Nodes need a frame before they can enter the tree cleanly.
	await process_frame
	var tests := [
		"test_static_exit",
		"test_no_dodge_at_spawn",
		"test_dodge_once",
		"test_catch_after_dodge",
		"test_bad_t_counts",
	]
	for t: String in tests:
		var ok = await call(t)
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


func make_manager() -> GameManager:
	var mgr := GameManager.new()
	mgr.name = "Game"
	root.add_child(mgr)
	return mgr


func cleanup_manager(mgr: GameManager) -> void:
	if is_instance_valid(mgr):
		mgr.queue_free()
	await process_frame
	await physics_frame


func find_door(mgr: GameManager) -> FleeingDoor:
	if mgr.level == null or not is_instance_valid(mgr.level):
		return null
	for child: Node in mgr.level.get_children():
		if child is FleeingDoor:
			return child as FleeingDoor
	var nodes := get_nodes_in_group("doors")
	if nodes.is_empty():
		return null
	return nodes[0] as FleeingDoor


func t_center_of(idx: int) -> Vector2:
	var rows := Levels.get_level(idx)
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			if row.substr(c, 1) == "T":
				return Vector2(c * 32 + 16, r * 32 + 16)
	return Vector2(-1, -1)


## Steps the player from `from_pos` toward `goal` in 10px hops without
## entering the exit overlap (stops 30px short). Returns when `door`
## has dodged or the step budget runs out.
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


func test_static_exit() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "static-exit: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var door := find_door(mgr)
	ok = expect(door != null, "static-exit: level 0 has a door") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	(mgr.player as Node2D).global_position = (door as Node2D).global_position
	var t0 := Time.get_ticks_msec()
	var advanced := false
	var elapsed := 0
	for i: int in 90:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			break
		if mgr.current_level == 1 and mgr.level_idx == 1:
			elapsed = Time.get_ticks_msec() - t0
			advanced = true
			break
		if Time.get_ticks_msec() - t0 > 600:
			break
	ok = expect(advanced, "static-exit: touch advances to next level") and ok
	if advanced:
		ok = expect(elapsed <= 450, "static-exit: advance within 0.45s (got %dms)" % elapsed) and ok
	await cleanup_manager(mgr)
	return ok


func test_no_dodge_at_spawn() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(1), "no-trigger: start_level(1) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var door := find_door(mgr)
	ok = expect(door != null, "no-trigger: level 1 has a fleeing door") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	var start_pos: Vector2 = (door as Node2D).global_position
	# Player untouched at spawn for ~2s: the spawn gate must hold the dodge.
	for i: int in 120:
		await physics_frame
	if not is_instance_valid(door):
		ok = expect(false, "no-trigger: door freed while waiting") and ok
		await cleanup_manager(mgr)
		return ok
	ok = expect((door as Node2D).global_position.distance_to(start_pos) < 2.0, "no-trigger: door never tweens at spawn") and ok
	ok = expect(not (door as FleeingDoor).has_dodged(), "no-trigger: has_dodged stays false") and ok
	await cleanup_manager(mgr)
	return ok


func test_dodge_once() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(1), "dodge: start_level(1) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var door := find_door(mgr)
	ok = expect(door != null, "dodge: level 1 has a fleeing door") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	var target := t_center_of(1)
	ok = expect(target.x >= 0.0, "dodge: level 1 has a T cell") and ok
	var marks: Array = []
	(door as FleeingDoor).dodged.connect(func(_d: Node) -> void: marks.append(Time.get_ticks_msec()))
	var dir := ((door as Node2D).global_position - spawn).normalized()
	await step_toward(mgr, door, spawn + dir * 40.0, (door as Node2D).global_position, 30)
	ok = expect((door as FleeingDoor).has_dodged(), "dodge: trigger fires after leaving spawn") and ok
	# Tween to the T center within 0.4s while the player holds clear.
	var t0 := Time.get_ticks_msec()
	var landed := false
	var elapsed := 0
	for i: int in 60:
		await process_frame
		await physics_frame
		if not is_instance_valid(door):
			break
		if (door as Node2D).global_position.distance_to(target) < 4.0:
			elapsed = Time.get_ticks_msec() - t0
			landed = true
			break
		if Time.get_ticks_msec() - t0 > 600:
			break
	ok = expect(landed, "dodge: door tweens to T center") and ok
	if landed:
		ok = expect(elapsed <= 400, "dodge: tween within 0.4s (got %dms)" % elapsed) and ok
	for i: int in 5:
		await process_frame
	ok = expect(marks.size() == 1, "dodge: exactly one dodged signal (got %d)" % marks.size()) and ok
	# A second approach in the same attempt fires no second dodge.
	var after: Vector2 = (door as Node2D).global_position
	await step_toward(mgr, door, after + Vector2(-100, 0), after, 20)
	ok = expect(marks.size() == 1, "dodge-once: no second dodged on re-approach (got %d)" % marks.size()) and ok
	ok = expect((door as Node2D).global_position.distance_to(after) < 2.0, "dodge-once: position stable on re-approach") and ok
	await cleanup_manager(mgr)
	return ok


func test_catch_after_dodge() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(1), "catch: start_level(1) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	await physics_frame
	var door := find_door(mgr)
	ok = expect(door != null, "catch: level 1 has a fleeing door") and ok
	if door == null:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	var target := t_center_of(1)
	var dir := ((door as Node2D).global_position - spawn).normalized()
	await step_toward(mgr, door, spawn + dir * 40.0, (door as Node2D).global_position, 30)
	ok = expect((door as FleeingDoor).has_dodged(), "catch: door dodges first") and ok
	var t0 := Time.get_ticks_msec()
	for i: int in 60:
		await process_frame
		await physics_frame
		if not is_instance_valid(door):
			break
		if (door as Node2D).global_position.distance_to(target) < 4.0:
			break
		if Time.get_ticks_msec() - t0 > 600:
			break
	ok = expect((door as Node2D).global_position.distance_to(target) < 4.0, "catch: door reaches T before the catch") and ok
	# Rewind the counter so the last level has a next level to load;
	# the exit wiring must still advance exactly like the static door.
	mgr.current_level = 1
	mgr.level_idx = 1
	var exited_marks: Array = []
	(door as FleeingDoor).exited.connect(func(_d: Node) -> void: exited_marks.append(1))
	(mgr.player as Node2D).global_position = (door as Node2D).global_position
	t0 = Time.get_ticks_msec()
	var advanced := false
	var elapsed := 0
	for i: int in 90:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			break
		if mgr.current_level == 2 and mgr.level_idx == 2:
			elapsed = Time.get_ticks_msec() - t0
			advanced = true
			break
		if Time.get_ticks_msec() - t0 > 600:
			break
	ok = expect(not exited_marks.is_empty(), "catch: touch after dodge emits exited") and ok
	ok = expect(advanced, "catch: touch after dodge advances to next level") and ok
	if advanced:
		ok = expect(elapsed <= 450, "catch: advance within 0.45s (got %dms)" % elapsed) and ok
	await cleanup_manager(mgr)
	return ok


func test_bad_t_counts() -> bool:
	var ok := true
	var no_t := PackedStringArray([".....", "..P..", "..D.."])
	var reason_zero := LevelBuilder.validate_grid(no_t, 7)
	ok = expect(reason_zero.contains("T"), "bad-t: zero-T reason names T (got '%s')" % reason_zero) and ok
	ok = expect(reason_zero.contains("7"), "bad-t: zero-T reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(no_t, 7) == null, "bad-t: D with zero T fails to build") and ok
	var two_t := PackedStringArray(["..T..", "..PD.", "..T.."])
	var reason_two := LevelBuilder.validate_grid(two_t, 9)
	ok = expect(reason_two.contains("T"), "bad-t: two-T reason names T (got '%s')" % reason_two) and ok
	ok = expect(reason_two.contains("9"), "bad-t: two-T reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(two_t, 9) == null, "bad-t: D with two T fails to build") and ok
	return ok
