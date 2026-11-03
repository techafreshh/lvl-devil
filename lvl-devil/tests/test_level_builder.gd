extends SceneTree
## Headless level-builder tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_level_builder.gd
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
		"test_valid_build",
		"test_invalid_char",
		"test_non_rectangular",
		"test_missing_p",
		"test_extra_p",
		"test_levels_charset",
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


## Counting check helper: never use bare assert() in a SceneTree runner.
func expect(cond: bool, label: String) -> bool:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)
	return cond


## Minimal valid grid: rectangular, legal chars, exactly one P.
func base_rows() -> PackedStringArray:
	return PackedStringArray([".....", "..P..", "#####"])


func count_char(rows: PackedStringArray, target: String) -> int:
	var n := 0
	for row: String in rows:
		for c: int in row.length():
			if row.substr(c, 1) == target:
				n += 1
	return n


func spawn_center(rows: PackedStringArray) -> Vector2:
	for r: int in rows.size():
		var row: String = rows[r]
		for c: int in row.length():
			if row.substr(c, 1) == "P":
				return Vector2(c * 32 + 16, r * 32 + 16)
	return Vector2(-1, -1)


func test_valid_build() -> bool:
	var ok := true
	var rows := Levels.get_level(0)
	var level := LevelBuilder.build(0)
	ok = expect(level != null, "valid: build(0) returns a level") and ok
	if level == null:
		return ok
	root.add_child(level)
	await process_frame
	var solids := 0
	for child: Node in level.get_children():
		if child is StaticBody2D:
			solids += 1
			ok = expect(child.is_in_group("solid_tiles"), "valid: solid in solid_tiles group") and ok
	ok = expect(solids == count_char(rows, "#"), "valid: solid count matches # count (got %d)" % solids) and ok
	var player := level.get_node_or_null("Player")
	ok = expect(player != null, "valid: Player node exists") and ok
	if player != null:
		var want := spawn_center(rows)
		var got := (player as Node2D).global_position
		ok = expect(want.x >= 0.0, "valid: grid has a spawn cell") and ok
		ok = expect(got.distance_to(want) <= 1.0, "valid: player at P center (got %s, want %s)" % [got, want]) and ok
		ok = expect(absf(got.x - 80.0) <= 1.0 and absf(got.y - 272.0) <= 1.0, "valid: spawn at (80, 272) (got %s)" % got) and ok
	level.queue_free()
	await process_frame
	return ok


func test_invalid_char() -> bool:
	var ok := true
	var rows := base_rows()
	rows[1] = "..Q.."
	var reason := LevelBuilder.validate_grid(rows, 3)
	ok = expect(reason.contains("invalid char"), "invalid-char: reason names it (got '%s')" % reason) and ok
	ok = expect(reason.contains("3"), "invalid-char: reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(rows, 3) == null, "invalid-char: build returns null") and ok
	return ok


func test_non_rectangular() -> bool:
	var ok := true
	var rows := PackedStringArray([".....", "..P", "#####"])
	var reason := LevelBuilder.validate_grid(rows, 5)
	ok = expect(reason.contains("rectangular"), "ragged: reason names it (got '%s')" % reason) and ok
	ok = expect(reason.contains("5"), "ragged: reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(rows, 5) == null, "ragged: build returns null") and ok
	var empty_reason := LevelBuilder.validate_grid(PackedStringArray(), 5)
	ok = expect(empty_reason.contains("rectangular"), "empty: covered by rectangular (got '%s')" % empty_reason) and ok
	return ok


func test_missing_p() -> bool:
	var ok := true
	var rows := PackedStringArray([".....", ".....", "#####"])
	var reason := LevelBuilder.validate_grid(rows, 7)
	ok = expect(reason.contains("missing P"), "missing-p: reason names it (got '%s')" % reason) and ok
	ok = expect(reason.contains("7"), "missing-p: reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(rows, 7) == null, "missing-p: build returns null") and ok
	return ok


func test_extra_p() -> bool:
	var ok := true
	var rows := PackedStringArray(["..P..", "..P..", "#####"])
	var reason := LevelBuilder.validate_grid(rows, 9)
	ok = expect(reason.contains("extra P"), "extra-p: reason names it (got '%s')" % reason) and ok
	ok = expect(reason.contains("9"), "extra-p: reason names level index") and ok
	ok = expect(LevelBuilder.build_from_rows(rows, 9) == null, "extra-p: build returns null") and ok
	return ok


func test_levels_charset() -> bool:
	var ok := true
	# Batch-1 content plus the trap glyphs later issues will allow.
	var allowed := "#P.^XdDTHV"
	ok = expect(Levels.count() > 0, "charset: at least one level ships") and ok
	for i: int in Levels.ALL.size():
		var rows: PackedStringArray = Levels.ALL[i]
		for r: int in rows.size():
			var row: String = rows[r]
			for c: int in row.length():
				var ch: String = row.substr(c, 1)
				ok = expect(allowed.contains(ch), "charset: level %d row %d col %d char '%s' allowed" % [i, r, c, ch]) and ok
	return ok
