extends SceneTree
## Headless UI-strip tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_ui_strip.gd
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
		"test_boot_strip",
		"test_fall_death_same_frame",
		"test_advance_shows_level_2",
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


func player_at_spawn(mgr: GameManager) -> bool:
	if mgr.player == null or not is_instance_valid(mgr.player):
		return false
	return (mgr.player as Node2D).global_position.distance_to(mgr.spawn_pos) <= 2.0


func strip_of(mgr: GameManager) -> UIStrip:
	if mgr.strip != null and is_instance_valid(mgr.strip):
		return mgr.strip
	return mgr.get_node_or_null("UIStrip") as UIStrip


func label_text(strip: UIStrip, label_name: String) -> String:
	if strip == null or not is_instance_valid(strip):
		return ""
	var label := strip.get_node_or_null(label_name) as Label
	if label == null:
		return ""
	return label.text


func test_boot_strip() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "boot-strip: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var strip := strip_of(mgr)
	ok = expect(strip != null, "boot-strip: Game/UIStrip exists") and ok
	ok = expect(strip is CanvasLayer, "boot-strip: strip is a CanvasLayer") and ok
	ok = expect(label_text(strip, "LevelLabel") == "LEVEL 1", "boot-strip: left label reads LEVEL 1") and ok
	ok = expect(label_text(strip, "DeathsLabel") == "DEATHS 0", "boot-strip: right label reads DEATHS 0") and ok
	ok = expect(mgr.total_deaths == 0, "boot-strip: total_deaths starts at 0") and ok
	ok = expect(mgr.current_level == 0, "boot-strip: current_level starts at 0") and ok
	await cleanup_manager(mgr)
	return ok


func test_fall_death_same_frame() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "fall-strip: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var old_player := mgr.player
	(mgr.player as Node2D).global_position = Vector2(mgr.spawn_pos.x, 400.0)
	var t0 := Time.get_ticks_msec()
	# Same-frame accounting: the physics step right after the teleport flips
	# the counter. Two signal resumes bracket exactly that step because
	# `physics_frame` fires before node `_physics_process` runs.
	await physics_frame
	await physics_frame
	var strip := strip_of(mgr)
	ok = expect(mgr.total_deaths == 1, "fall-strip: total_deaths is 1 after one frame") and ok
	ok = expect(label_text(strip, "DeathsLabel") == "DEATHS 1", "fall-strip: label reads DEATHS 1 within 1 frame") and ok
	ok = expect(label_text(strip, "LevelLabel") == "LEVEL 1", "fall-strip: level label still LEVEL 1") and ok
	# Respawn must land back on P quickly.
	var back := false
	var elapsed := 0
	for i: int in 60:
		await physics_frame
		await process_frame
		if is_instance_valid(mgr.player) and mgr.player != old_player and player_at_spawn(mgr):
			elapsed = Time.get_ticks_msec() - t0
			back = true
			break
	ok = expect(back, "fall-strip: kill-plane death respawns to P") and ok
	if back:
		ok = expect(elapsed < 500, "fall-strip: death-to-playing < 0.5s (got %dms)" % elapsed) and ok
		ok = expect(label_text(strip_of(mgr), "DeathsLabel") == "DEATHS 1", "fall-strip: DEATHS 1 survives respawn") and ok
	await cleanup_manager(mgr)
	return ok


func test_advance_shows_level_2() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "advance-strip: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var strip_before := strip_of(mgr)
	# One funnel death first so the deaths label has something to keep.
	(mgr.player as Node2D).global_position = Vector2(mgr.spawn_pos.x, 400.0)
	await physics_frame
	await physics_frame
	ok = expect(label_text(strip_of(mgr), "DeathsLabel") == "DEATHS 1", "advance-strip: death registers DEATHS 1") and ok
	# Wait for the respawn, then advance a level.
	var back := false
	for i: int in 60:
		await physics_frame
		await process_frame
		if player_at_spawn(mgr):
			back = true
			break
	ok = expect(back, "advance-strip: respawn returns to P") and ok
	ok = expect(mgr.next_level(), "advance-strip: next_level() advances") and ok
	await process_frame
	var strip_after := strip_of(mgr)
	ok = expect(strip_after == strip_before, "advance-strip: strip persists across respawn and advance") and ok
	ok = expect(label_text(strip_after, "LevelLabel") == "LEVEL 2", "advance-strip: left label reads LEVEL 2") and ok
	ok = expect(label_text(strip_after, "DeathsLabel") == "DEATHS 1", "advance-strip: DEATHS 1 survives level advance") and ok
	ok = expect(mgr.current_level == 1, "advance-strip: current_level is 1") and ok
	await cleanup_manager(mgr)
	return ok
