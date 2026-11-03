extends SceneTree
## Headless falling-tile tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_falling_tile.gd
## Exits 1 when any check fails so CI can gate on the exit code.


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
		"test_drop_timing",
		"test_independent_timers",
		"test_respawn_restores",
		"test_untouched_still",
		"test_builder_builds_falling",
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


func make_tile(at: Vector2) -> FallingTile:
	var tile := FallingTile.new()
	tile.position = at
	root.add_child(tile)
	return tile


func make_player(at: Vector2) -> CharacterBody2D:
	var p := PlayerScene.instantiate() as CharacterBody2D
	p.position = at
	p.add_to_group("player")
	root.add_child(p)
	return p


func shape_disabled(tile: FallingTile) -> bool:
	var col := tile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		return false
	return col.disabled


## Geometric standing check mirroring FallingTile.try_trigger, so tests can
## name the exact frame first contact happens on.
func is_standing(player: Node2D, tile: FallingTile) -> bool:
	var d: Vector2 = player.global_position - tile.global_position
	if absf(d.x) > 29.0:
		return false
	var bottom: float = player.global_position.y + 13.0
	var top: float = tile.global_position.y - 16.0
	return bottom >= top - 6.0 and bottom <= top + 6.0


func cleanup(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n: Node in root.get_children():
		if n.is_in_group("player") or n.is_in_group("falling_tiles"):
			n.queue_free()
	await process_frame
	await physics_frame


func test_drop_timing() -> bool:
	var ok := true
	var rows := PackedStringArray([".....", "..P..", "..X..", "#####"])
	var level := LevelBuilder.build_from_rows(rows, 21)
	ok = expect(level != null, "drop: grid with X builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var tile := level.get_node_or_null("FallingTile_2_2") as FallingTile
	var player := level.get_node_or_null("Player") as CharacterBody2D
	ok = expect(tile != null and player != null, "drop: tile and player exist") and ok
	if tile == null or player == null:
		await cleanup([level])
		return ok
	# Wait for first standing contact, then the latch must fire next frame.
	var stood := false
	for i: int in 90:
		await physics_frame
		if is_standing(player, tile):
			stood = true
			break
	ok = expect(stood, "drop: player lands standing on the X tile") and ok
	var t_stand := Time.get_ticks_msec()
	await physics_frame
	if not tile.is_shaking():
		await physics_frame
	ok = expect(tile.is_shaking(), "drop: shaking latches within 1 physics frame of contact") and ok
	var t_shake := Time.get_ticks_msec()
	# Visible shake: horizontal offset must exceed 1px while shaking.
	var peak := 0.0
	var dropped := false
	var t_drop := 0
	for i: int in 30:
		await physics_frame
		peak = maxf(peak, absf(tile.position.x - tile.home_pos().x))
		if tile.has_dropped():
			dropped = true
			t_drop = Time.get_ticks_msec()
			break
	ok = expect(dropped, "drop: tile detaches after the shake") and ok
	if dropped:
		var held := t_drop - t_shake
		ok = expect(held >= 70 and held <= 170, "drop: shake lasts ~0.12s (+-0.05s, got %dms)" % held) and ok
	ok = expect(peak >= 2.0, "drop: shake offsets visibly (peak %s px)" % peak) and ok
	# After the drop the tile must fall >16px within 0.2s and go non-solid.
	var y0: float = tile.position.y
	var fell := false
	for i: int in 12:
		await physics_frame
		if tile.position.y - y0 > 16.0:
			fell = true
			break
	ok = expect(fell, "drop: tile falls >16px within 0.2s (got %s)" % (tile.position.y - y0)) and ok
	await process_frame
	ok = expect(shape_disabled(tile), "drop: CollisionShape2D disabled once falling") and ok
	await cleanup([level])
	return ok


func test_independent_timers() -> bool:
	var ok := true
	var tile_a := make_tile(Vector2(80, 100))
	var tile_b := make_tile(Vector2(112, 100))
	var player := make_player(Vector2(80, 71))
	await process_frame
	# Step A, then step B a full 0.2s later.
	(player as Node2D).global_position = Vector2(80, 71)
	(player as CharacterBody2D).velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	ok = expect(tile_a.is_shaking(), "stagger: first tile latches when stepped") and ok
	ok = expect(not tile_b.is_shaking(), "stagger: neighbor stays idle until stepped") and ok
	# Poll from the first step so neither drop timestamp is missed; step the
	# neighbor 12 physics frames (0.2s) later and let each timer run alone.
	var t_drop_a := 0
	var t_drop_b := 0
	var stepped_b := false
	var latched_b := false
	for i: int in 60:
		await physics_frame
		var now := Time.get_ticks_msec()
		if tile_a.has_dropped() and t_drop_a == 0:
			t_drop_a = now
		if tile_b.has_dropped() and t_drop_b == 0:
			t_drop_b = now
		if i == 12:
			(player as Node2D).global_position = Vector2(112, 71)
			(player as CharacterBody2D).velocity = Vector2.ZERO
			stepped_b = true
		if stepped_b and i >= 14:
			latched_b = latched_b or tile_b.is_shaking() or tile_b.has_dropped()
		if t_drop_a != 0 and t_drop_b != 0:
			break
	ok = expect(stepped_b, "stagger: second tile stepped 0.2s later") and ok
	ok = expect(latched_b, "stagger: second tile latches on its own step") and ok
	ok = expect(t_drop_a != 0 and t_drop_b != 0, "stagger: both tiles drop") and ok
	if t_drop_a != 0 and t_drop_b != 0:
		var gap := t_drop_b - t_drop_a
		ok = expect(gap >= 120 and gap <= 280, "stagger: drops ~0.2s apart (+-0.08s, got %dms)" % gap) and ok
	await cleanup([tile_a, tile_b, player])
	return ok


func test_respawn_restores() -> bool:
	var ok := true
	var rows := PackedStringArray(["......", "..P...", "..X...", "######"])
	var level := LevelBuilder.build_from_rows(rows, 22)
	ok = expect(level != null, "respawn: grid with X builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var tile := level.get_node_or_null("FallingTile_2_2") as FallingTile
	var player := level.get_node_or_null("Player") as CharacterBody2D
	ok = expect(tile != null and player != null, "respawn: tile and player exist") and ok
	if tile == null or player == null:
		await cleanup([level])
		return ok
	var home: Vector2 = tile.home_pos()
	for i: int in 90:
		await physics_frame
		if tile.has_dropped():
			break
	ok = expect(tile.has_dropped(), "respawn: tile drops before the reset") and ok
	# In-place hook restores the grid-cell solid state. Park the player back
	# at spawn first: it rides the falling tile down (same gravity), so a
	# live standing player would correctly re-latch the restored tile.
	(player as Node2D).global_position = Vector2(160, 48)
	(player as CharacterBody2D).velocity = Vector2.ZERO
	tile.reset_tile()
	await process_frame
	for i: int in 4:
		await physics_frame
	ok = expect(not tile.is_shaking() and not tile.has_dropped(), "respawn: reset_tile clears shake/drop") and ok
	ok = expect(tile.position.distance_to(home) <= 1.0, "respawn: reset_tile restores grid cell") and ok
	ok = expect(not shape_disabled(tile), "respawn: reset_tile re-enables collision") and ok
	# Full rebuild, the exact GameManager.respawn mechanism, restores solid
	# tiles from the grid within 0.5s. Assert before any physics frame so
	# the fresh spawn has not started falling back onto the tile yet.
	var t0 := Time.get_ticks_msec()
	level.queue_free()
	await process_frame
	var fresh := LevelBuilder.build_from_rows(rows, 22)
	ok = expect(fresh != null, "respawn: rebuild succeeds") and ok
	if fresh == null:
		return ok
	root.add_child(fresh)
	await process_frame
	var tile2 := fresh.get_node_or_null("FallingTile_2_2") as FallingTile
	ok = expect(tile2 != null, "respawn: rebuilt level has the X tile") and ok
	if tile2 != null:
		ok = expect(tile2.position.distance_to(home) <= 1.0, "respawn: rebuilt tile back at grid cell") and ok
		ok = expect(not shape_disabled(tile2), "respawn: rebuilt tile collision re-enabled") and ok
		ok = expect(not tile2.is_shaking() and not tile2.has_dropped(), "respawn: rebuilt tile solid and idle") and ok
	var elapsed := Time.get_ticks_msec() - t0
	ok = expect(elapsed < 500, "respawn: restore lands < 0.5s (got %dms)" % elapsed) and ok
	await cleanup([fresh])
	return ok


func test_untouched_still() -> bool:
	var ok := true
	var rows := PackedStringArray([".....", ".P...", "..X..", "#####"])
	var level := LevelBuilder.build_from_rows(rows, 23)
	ok = expect(level != null, "still: grid with X builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var tile := level.get_node_or_null("FallingTile_2_2") as FallingTile
	ok = expect(tile != null, "still: tile exists") and ok
	if tile == null:
		await cleanup([level])
		return ok
	var home: Vector2 = tile.home_pos()
	# Player rests on the floor a cell away; idle a full 2s without standing.
	var drift := 0.0
	for i: int in 120:
		await physics_frame
		drift = maxf(drift, tile.position.distance_to(home))
	ok = expect(drift <= 1.0, "still: untouched tile never moves >1px (got %s)" % drift) and ok
	ok = expect(not tile.is_shaking() and not tile.has_dropped(), "still: untouched tile never triggers") and ok
	ok = expect(not shape_disabled(tile), "still: untouched tile stays solid") and ok
	await cleanup([level])
	return ok


func test_builder_builds_falling() -> bool:
	var ok := true
	ok = expect(LevelBuilder.validate_grid(PackedStringArray([".....", "..P..", "..X..", "#####"]), 24) == "", "builder: grid with X validates") and ok
	var rows := PackedStringArray(["......", "...P..", "...X..", "######"])
	var level := LevelBuilder.build_from_rows(rows, 24)
	ok = expect(level != null, "builder: grid with X builds") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var tile := level.get_node_or_null("FallingTile_3_2") as FallingTile
	ok = expect(tile != null, "builder: FallingTile_3_2 node exists") and ok
	if tile != null:
		ok = expect(tile.is_in_group("solid_tiles"), "builder: tile joins solid_tiles") and ok
		ok = expect(tile.is_in_group("falling_tiles"), "builder: tile joins falling_tiles") and ok
		var want := Vector2(3 * 32 + 16, 2 * 32 + 16)
		ok = expect(tile.position.distance_to(want) <= 1.0, "builder: tile at cell center (got %s)" % tile.position) and ok
		var col := tile.get_node_or_null("CollisionShape2D") as CollisionShape2D
		ok = expect(col != null and not col.disabled, "builder: tile spawns solid") and ok
		if col != null and col.shape is RectangleShape2D:
			ok = expect((col.shape as RectangleShape2D).size == Vector2(32, 32), "builder: tile shape is 32x32") and ok
		var visual := tile.get_node_or_null("ColorRect") as ColorRect
		ok = expect(visual != null, "builder: tile renders a ColorRect like solid") and ok
		if visual != null:
			ok = expect(visual.size == Vector2(32, 32), "builder: tile visual is solid-sized") and ok
			ok = expect(visual.color == Color(0.85, 0.82, 0.75), "builder: tile visual matches solid color") and ok
	# Dev content check: level 1 (fakeout doors, no X) builds with no falling tiles.
	var shipped := LevelBuilder.build(1)
	ok = expect(shipped != null, "builder: DEV_1 still builds") and ok
	if shipped != null:
		root.add_child(shipped)
		await process_frame
		var strays := 0
		for child: Node in shipped.get_children():
			if child is FallingTile:
				strays += 1
		ok = expect(strays == 0, "builder: DEV_1 has no falling tiles") and ok
		shipped.queue_free()
		await process_frame
	await cleanup([level])
	return ok
