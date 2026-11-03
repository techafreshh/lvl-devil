extends SceneTree
## Headless spike trap tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_spike.gd
## Exits 1 when any check fails so CI can gate on the exit code.


const SpikeScene := preload("res://scenes/spike.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

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
		"test_hidden_at_distance",
		"test_activates_within_2_frames",
		"test_ignores_player_above",
		"test_latch_after_retreat",
		"test_killed_only_when_active",
		"test_reset_retracts",
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


func cleanup(spike: Node, player: Node) -> void:
	if is_instance_valid(spike):
		spike.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	for n: Node in root.get_children():
		if n.is_in_group("player") or n.is_in_group("spikes"):
			n.queue_free()
	await process_frame
	await physics_frame


func shape_disabled(spike: Area2D) -> bool:
	var col := spike.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		return false
	return col.disabled


func test_hidden_at_distance() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	var player := make_player(Vector2(160, 0))
	await process_frame
	# 5 tiles away: no trigger over 10 physics frames, shape stays disabled.
	for i: int in 10:
		await physics_frame
	ok = expect(not (spike as PopupSpike).is_active(), "hidden: spike stays retracted at 160px") and ok
	ok = expect(shape_disabled(spike), "hidden: shape stays disabled while retracted") and ok
	await cleanup(spike, player)
	return ok


func test_activates_within_2_frames() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	var player := make_player(Vector2(38, 0))
	await process_frame
	for i: int in 2:
		await physics_frame
		if (spike as PopupSpike).is_active():
			break
	ok = expect((spike as PopupSpike).is_active(), "activate: spike active within 2 physics frames at 38px same-row") and ok
	await process_frame
	ok = expect(not shape_disabled(spike), "activate: shape enabled once active") and ok
	await cleanup(spike, player)
	return ok


func test_ignores_player_above() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	# Same x range but a full tile above: outside the same-row window.
	var player := make_player(Vector2(20, -32))
	await process_frame
	for i: int in 10:
		await physics_frame
	ok = expect(not (spike as PopupSpike).is_active(), "same-row: no trigger one tile above") and ok
	await cleanup(spike, player)
	return ok


func test_latch_after_retreat() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	var player := make_player(Vector2(30, 0))
	await process_frame
	for i: int in 5:
		await physics_frame
	ok = expect((spike as PopupSpike).is_active(), "latch: spike activates in range") and ok
	(player as Node2D).global_position = Vector2(200, 0)
	for i: int in 10:
		await physics_frame
	ok = expect((spike as PopupSpike).is_active(), "latch: spike stays out after player retreats") and ok
	await cleanup(spike, player)
	return ok


func test_killed_only_when_active() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	# 28px below: AABBs overlap but the same-row gate fails, so no latch.
	var player := make_player(Vector2(0, 28))
	var hits: Array = []
	(spike as PopupSpike).killed.connect(func(_s: Node) -> void: hits.append(1))
	await process_frame
	for i: int in 10:
		await physics_frame
	ok = expect(not (spike as PopupSpike).is_active(), "kill-gate: still retracted below row") and ok
	ok = expect(hits.is_empty(), "kill-gate: no killed while retracted despite AABB overlap") and ok
	# Same-row overlap: latches, then the lethal check fires killed.
	(player as Node2D).global_position = Vector2(0, 0)
	var fired := false
	for i: int in 30:
		await physics_frame
		if not hits.is_empty():
			fired = true
			break
	ok = expect((spike as PopupSpike).is_active(), "kill-gate: active on same-row overlap") and ok
	ok = expect(fired, "kill-gate: killed fires on overlap only when active") and ok
	await cleanup(spike, player)
	return ok


func test_reset_retracts() -> bool:
	var ok := true
	var spike := make_spike(Vector2(0, 0))
	var player := make_player(Vector2(30, 0))
	await process_frame
	for i: int in 5:
		await physics_frame
	ok = expect((spike as PopupSpike).is_active(), "reset: active before reset") and ok
	(player as Node2D).global_position = Vector2(200, 0)
	await physics_frame
	(spike as PopupSpike).reset_spike()
	await process_frame
	await physics_frame
	await physics_frame
	await physics_frame
	ok = expect(not (spike as PopupSpike).is_active(), "reset: retracted after reset_spike") and ok
	ok = expect(shape_disabled(spike), "reset: shape disabled after reset_spike") and ok
	await cleanup(spike, player)
	return ok
