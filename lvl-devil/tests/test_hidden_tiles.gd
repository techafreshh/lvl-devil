extends SceneTree
## Headless hidden-tile ambush tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_hidden_tiles.gd
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
		"test_fake_floor_draws_identical",
		"test_fake_floor_not_solid",
		"test_fake_floor_falls_through",
		"test_hidden_wall_blocks_invisibly",
		"test_solid_counts",
		"test_rebuild_repeats_ambush",
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


## Ambush grid: one fake floor (H) among solids, one hidden wall (V).
func ambush_rows() -> PackedStringArray:
	return PackedStringArray(["........", "..P.....", "##H##V##"])


## Corridor grid: hidden wall (V) standing on the floor in the walk path.
func corridor_rows() -> PackedStringArray:
	return PackedStringArray(["........", "..P..V..", "########"])


func count_char(rows: PackedStringArray, target: String) -> int:
	var n := 0
	for row: String in rows:
		for c: int in row.length():
			if row.substr(c, 1) == target:
				n += 1
	return n


func solid_bodies(level: Node2D) -> Array:
	var out := []
	for child: Node in level.get_children():
		if child is StaticBody2D:
			out.append(child)
	return out


func first_visual(node: Node) -> ColorRect:
	for child: Node in node.get_children():
		if child is ColorRect:
			return child as ColorRect
	return null


func free_level(level: Node) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await process_frame
	await physics_frame


func test_fake_floor_draws_identical() -> bool:
	var ok := true
	var rows := ambush_rows()
	ok = expect(LevelBuilder.validate_grid(rows, 21) == "", "fake-draw: H/V grid validates") and ok
	var level := LevelBuilder.build_from_rows(rows, 21)
	ok = expect(level != null, "fake-draw: ambush grid builds") and ok
	if level == null:
		return ok
	var fake := level.get_node_or_null("FakeFloor_2_2")
	ok = expect(fake != null, "fake-draw: FakeFloor_2_2 exists") and ok
	var solid := level.get_node_or_null("Solid_0_2")
	ok = expect(solid != null, "fake-draw: Solid_0_2 exists") and ok
	if fake != null and solid != null:
		var fake_rect := first_visual(fake)
		var solid_rect := first_visual(solid)
		ok = expect(fake_rect != null, "fake-draw: H has a ColorRect visual") and ok
		ok = expect(solid_rect != null, "fake-draw: # has a ColorRect visual") and ok
		if fake_rect != null and solid_rect != null:
			ok = expect(fake_rect.color == solid_rect.color, "fake-draw: H color identical to # (got %s vs %s)" % [fake_rect.color, solid_rect.color]) and ok
			ok = expect(fake_rect.size == solid_rect.size, "fake-draw: H size identical to # (got %s vs %s)" % [fake_rect.size, solid_rect.size]) and ok
			ok = expect(fake_rect.position == solid_rect.position, "fake-draw: H offset identical to # (got %s vs %s)" % [fake_rect.position, solid_rect.position]) and ok
	await free_level(level)
	return ok


func test_fake_floor_not_solid() -> bool:
	var ok := true
	var level := LevelBuilder.build_from_rows(ambush_rows(), 21)
	ok = expect(level != null, "fake-solid: ambush grid builds") and ok
	if level == null:
		return ok
	var fake := level.get_node_or_null("FakeFloor_2_2")
	ok = expect(fake != null, "fake-solid: FakeFloor_2_2 exists") and ok
	if fake != null:
		ok = expect(not (fake is StaticBody2D), "fake-solid: H is never a StaticBody2D") and ok
		ok = expect(not fake.is_in_group("solid_tiles"), "fake-solid: H never joins solid_tiles") and ok
	await free_level(level)
	return ok


func test_fake_floor_falls_through() -> bool:
	var ok := true
	var level := LevelBuilder.build_from_rows(ambush_rows(), 21)
	ok = expect(level != null, "fake-fall: ambush grid builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var player := level.get_node_or_null("Player") as CharacterBody2D
	ok = expect(player != null, "fake-fall: Player exists") and ok
	if player == null:
		await free_level(level)
		return ok
	# Spawn (80, 48) hangs directly over the H hole: no input, just gravity.
	var start_y: float = (player as Node2D).global_position.y
	for i: int in 6:
		await physics_frame
	var early_y: float = (player as Node2D).global_position.y
	ok = expect(early_y > start_y + 2.0, "fake-fall: player drops over H within 0.1s (got %s -> %s)" % [start_y, early_y]) and ok
	ok = expect(not player.is_on_floor(), "fake-fall: no floor under H") and ok
	for i: int in 54:
		await physics_frame
	var late_y: float = (player as Node2D).global_position.y
	ok = expect(late_y > 96.0, "fake-fall: player falls below the H tile row (got %s)" % late_y) and ok
	await free_level(level)
	return ok


func test_hidden_wall_blocks_invisibly() -> bool:
	var ok := true
	var level := LevelBuilder.build_from_rows(corridor_rows(), 22)
	ok = expect(level != null, "wall: corridor grid builds") and ok
	if level == null:
		return ok
	var wall := level.get_node_or_null("Solid_5_1")
	ok = expect(wall != null, "wall: Solid_5_1 exists") and ok
	if wall != null:
		ok = expect(wall is StaticBody2D, "wall: V is a StaticBody2D") and ok
		ok = expect(wall.is_in_group("solid_tiles"), "wall: V joins solid_tiles") and ok
		ok = expect(wall.find_children("*", "ColorRect", true, false).is_empty(), "wall: V draws no visible tile") and ok
	root.add_child(level)
	await process_frame
	await physics_frame
	var player := level.get_node_or_null("Player") as CharacterBody2D
	ok = expect(player != null, "wall: Player exists") and ok
	if player == null:
		await free_level(level)
		return ok
	# Settle onto the floor first so the walk is grounded and deterministic.
	for i: int in 30:
		await physics_frame
		if player.is_on_floor():
			break
	ok = expect(player.is_on_floor(), "wall: player settles on the floor") and ok
	Input.action_press("move_right")
	for i: int in 120:
		await physics_frame
	Input.action_release("move_right")
	var edge: float = (player as Node2D).global_position.x + 13.0
	ok = expect(absf(edge - 160.0) <= 4.0, "wall: body edge clamped at V cell edge (got %s, want 160+-4)" % edge) and ok
	ok = expect((player as Node2D).global_position.x < 170.0, "wall: player never passes the invisible wall") and ok
	await free_level(level)
	return ok


func test_solid_counts() -> bool:
	var ok := true
	var rows := ambush_rows()
	var level := LevelBuilder.build_from_rows(rows, 21)
	ok = expect(level != null, "counts: ambush grid builds") and ok
	if level == null:
		return ok
	var solids := solid_bodies(level)
	var want := count_char(rows, "#") + count_char(rows, "V")
	ok = expect(solids.size() == want, "counts: V in, H out (got %d solids, want %d)" % [solids.size(), want]) and ok
	for body: Node in solids:
		ok = expect(body.is_in_group("solid_tiles"), "counts: every solid in solid_tiles") and ok
	await free_level(level)
	return ok


func test_rebuild_repeats_ambush() -> bool:
	var ok := true
	var rows := ambush_rows()
	var first := LevelBuilder.build_from_rows(rows, 21)
	var second := LevelBuilder.build_from_rows(rows, 21)
	ok = expect(first != null and second != null, "rebuild: both builds succeed") and ok
	if first == null or second == null:
		await free_level(first)
		await free_level(second)
		return ok
	var fake_a := first_visual(first.get_node_or_null("FakeFloor_2_2"))
	var fake_b := first_visual(second.get_node_or_null("FakeFloor_2_2"))
	ok = expect(fake_a != null and fake_b != null, "rebuild: H visual survives rebuild") and ok
	if fake_a != null and fake_b != null:
		ok = expect(fake_a.color == fake_b.color and fake_a.size == fake_b.size and fake_a.position == fake_b.position, "rebuild: H still renders as #") and ok
	var wall_a := first.get_node_or_null("Solid_5_2")
	var wall_b := second.get_node_or_null("Solid_5_2")
	ok = expect(wall_a != null and wall_b != null, "rebuild: V survives rebuild") and ok
	if wall_a != null and wall_b != null:
		for w: Node in [wall_a, wall_b]:
			ok = expect(w is StaticBody2D and w.is_in_group("solid_tiles"), "rebuild: V still blocks") and ok
			ok = expect((w as Node).find_children("*", "ColorRect", true, false).is_empty(), "rebuild: V still invisible") and ok
	var n_a := solid_bodies(first).size()
	var n_b := solid_bodies(second).size()
	ok = expect(n_a == n_b and n_a == count_char(rows, "#") + count_char(rows, "V"), "rebuild: solid counts repeat (got %d vs %d)" % [n_a, n_b]) and ok
	await free_level(first)
	await free_level(second)
	return ok
