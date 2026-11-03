extends SceneTree
## Headless death-loop tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_death_loop.gd
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
		"test_spike_death_respawn",
		"test_restart_resets",
		"test_fall_death_respawn",
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


func find_spike(mgr: GameManager) -> PopupSpike:
	if mgr.level == null or not is_instance_valid(mgr.level):
		return null
	var node := mgr.level.get_node_or_null("Spike_7_8") as PopupSpike
	if node != null:
		return node
	var spikes := get_nodes_in_group("spikes")
	if spikes.is_empty():
		return null
	return spikes[0] as PopupSpike


func test_spike_death_respawn() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "spike-death: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	var spike := find_spike(mgr)
	ok = expect(spike != null, "spike-death: level has a spike") and ok
	if spike == null:
		await cleanup_manager(mgr)
		return ok
	# Step into trigger range first so the latch fires before the overlap.
	(mgr.player as Node2D).global_position = (spike as Node2D).global_position + Vector2(-30, 0)
	for i: int in 5:
		await physics_frame
	ok = expect(spike.is_active(), "spike-death: spike latches near player") and ok
	var kill_marks: Array = []
	spike.killed.connect(func(_s: Node) -> void: kill_marks.append(Time.get_ticks_msec()))
	var t_overlap := Time.get_ticks_msec()
	(mgr.player as Node2D).global_position = (spike as Node2D).global_position
	var old_player := mgr.player
	# Freeze: the corpse halts while the wall-clock timer runs.
	await physics_frame
	await physics_frame
	ok = expect(not old_player.is_physics_processing(), "spike-death: player frozen during death") and ok
	# Respawn must land back on P quickly with spikes retracted.
	var respawned := false
	var t_spawn := 0
	for i: int in 60:
		await process_frame
		if player_at_spawn(mgr) and mgr.player != old_player:
			t_spawn = Time.get_ticks_msec()
			respawned = true
			break
	ok = expect(respawned, "spike-death: player returns to P") and ok
	if respawned:
		var total := t_spawn - t_overlap
		ok = expect(total < 500, "spike-death: death-and-respawn < 0.5s (got %dms)" % total) and ok
		if not kill_marks.is_empty():
			var held := t_spawn - int(kill_marks[0])
			ok = expect(held >= 50 and held <= 300, "spike-death: freeze ~0.1s (got %dms)" % held) and ok
		var bursts := mgr.find_children("*", "CPUParticles2D", true, false)
		ok = expect(not bursts.is_empty(), "spike-death: burst particles spawn") and ok
		var fresh := find_spike(mgr)
		ok = expect(fresh != null and not fresh.is_active(), "spike-death: spikes retracted after respawn") and ok
	await cleanup_manager(mgr)
	return ok


func test_restart_resets() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "restart: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	(mgr.player as Node2D).global_position = spawn + Vector2(100, 0)
	await physics_frame
	ok = expect(not player_at_spawn(mgr), "restart: player moved off spawn") and ok
	var ev := InputEventAction.new()
	ev.action = &"restart"
	ev.pressed = true
	var t0 := Time.get_ticks_msec()
	mgr._unhandled_input(ev)
	var back := false
	var elapsed := 0
	for i: int in 60:
		await process_frame
		if player_at_spawn(mgr):
			elapsed = Time.get_ticks_msec() - t0
			back = true
			break
	ok = expect(back, "restart: R returns player to spawn") and ok
	if back:
		ok = expect(elapsed < 500, "restart: R-to-spawn < 0.5s (got %dms)" % elapsed) and ok
	ok = expect(is_instance_valid(mgr.level) and is_instance_valid(mgr.player), "restart: no scene reload failure") and ok
	await cleanup_manager(mgr)
	return ok


func test_fall_death_respawn() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "fall: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var spawn: Vector2 = mgr.spawn_pos
	var old_player := mgr.player
	(mgr.player as Node2D).global_position = Vector2(spawn.x, 400.0)
	var t0 := Time.get_ticks_msec()
	var back := false
	var elapsed := 0
	for i: int in 60:
		await process_frame
		await physics_frame
		if is_instance_valid(mgr.player) and mgr.player != old_player and player_at_spawn(mgr):
			elapsed = Time.get_ticks_msec() - t0
			back = true
			break
		if is_instance_valid(mgr.player) and mgr.player == old_player and player_at_spawn(mgr) and elapsed == 0:
			pass
	ok = expect(back, "fall: y>376 death-and-respawn returns to spawn") and ok
	if back:
		ok = expect(elapsed < 500, "fall: fall-to-spawn < 0.5s (got %dms)" % elapsed) and ok
	await cleanup_manager(mgr)
	return ok
