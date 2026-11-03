extends SceneTree
## Headless player physics tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_player.gd
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
		"test_walk_right",
		"test_basic_jump",
		"test_coyote_open",
		"test_coyote_expired",
		"test_buffer",
		"test_jump_cut",
		"test_grounded_vertical_zero",
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


## Counting check helper: never use bare assert() in a SceneTree runner.
func expect(cond: bool, label: String) -> bool:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)
	return cond


func release_all() -> void:
	for a: String in ["move_left", "move_right", "jump"]:
		Input.action_release(a)


func make_floor(center: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = center
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	col.shape = rect
	body.add_child(col)
	root.add_child(body)
	return body


func spawn_player(at: Vector2) -> CharacterBody2D:
	var p := PlayerScene.instantiate()
	p.position = at
	root.add_child(p)
	return p


## Waits until the player is grounded (up to max_frames physics frames).
func settle_grounded(player: CharacterBody2D, max_frames: int) -> bool:
	for i: int in max_frames:
		await physics_frame
		if player.is_on_floor():
			return true
	return false


func cleanup(player: CharacterBody2D, floor_body: StaticBody2D) -> void:
	player.queue_free()
	floor_body.queue_free()
	await process_frame
	await physics_frame


func test_walk_right() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(1000, 20))
	var player := spawn_player(Vector2(-200, 40))
	ok = expect(await settle_grounded(player, 60), "walk: player lands on floor") and ok
	var start_x: float = player.position.x
	Input.action_press("move_right")
	for i: int in 60:
		await physics_frame
	var vx: float = player.velocity.x
	var dx: float = player.position.x - start_x
	ok = expect(vx >= 155.0 and vx <= 185.0, "walk: velocity.x ~170 (got %s)" % vx) and ok
	ok = expect(dx > 150.0, "walk: displacement > 150 (got %s)" % dx) and ok
	await cleanup(player, floor_body)
	return ok


func test_basic_jump() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(1000, 20))
	var player := spawn_player(Vector2(0, 40))
	ok = expect(await settle_grounded(player, 60), "jump: player lands on floor") and ok
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	var vy: float = player.velocity.y
	ok = expect(vy < -300.0, "jump: velocity.y < -300 after press (got %s)" % vy) and ok
	await cleanup(player, floor_body)
	return ok


## Walks the player off a short ledge and reports once airborne.
func walk_off_ledge(player: CharacterBody2D) -> bool:
	Input.action_press("move_right")
	for i: int in 180:
		await physics_frame
		if not player.is_on_floor():
			return true
	return false


func test_coyote_open() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(200, 20))
	var player := spawn_player(Vector2(50, 40))
	ok = expect(await settle_grounded(player, 60), "coyote-open: player lands on ledge") and ok
	ok = expect(await walk_off_ledge(player), "coyote-open: walked off ledge") and ok
	# About 0.05 s off the ledge: still inside the 0.08 s coyote window.
	for i: int in 3:
		await physics_frame
	player.queue_jump()
	await physics_frame
	await physics_frame
	var vy: float = player.velocity.y
	ok = expect(vy < -300.0, "coyote-open: jump fires inside window (got %s)" % vy) and ok
	await cleanup(player, floor_body)
	return ok


func test_coyote_expired() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(200, 20))
	var player := spawn_player(Vector2(50, 40))
	ok = expect(await settle_grounded(player, 60), "coyote-expired: player lands on ledge") and ok
	ok = expect(await walk_off_ledge(player), "coyote-expired: walked off ledge") and ok
	# 10 frames (~0.17 s) off the ledge: past the 0.08 s coyote window.
	for i: int in 10:
		await physics_frame
	player.queue_jump()
	await physics_frame
	await physics_frame
	var vy: float = player.velocity.y
	ok = expect(vy > -300.0, "coyote-expired: no jump past window (got %s)" % vy) and ok
	await cleanup(player, floor_body)
	return ok


func test_buffer() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(1000, 20))
	# 20 px above the resting spot with downward speed: lands ~0.08 s out.
	var player := spawn_player(Vector2(0, 57))
	player.velocity.y = 200.0
	player.queue_jump()
	var land_i := -1
	var jumped := false
	for i: int in 40:
		await physics_frame
		if player.is_on_floor() and land_i < 0:
			land_i = i
		if land_i >= 0 and player.velocity.y < -200.0:
			jumped = true
			ok = expect((i - land_i) <= 3, "buffer: jump within 3 frames of landing") and ok
			break
	ok = expect(land_i >= 0, "buffer: player landed") and ok
	ok = expect(jumped, "buffer: buffered jump executed on landing") and ok
	await cleanup(player, floor_body)
	return ok


func test_grounded_vertical_zero() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(1000, 20))
	var player := spawn_player(Vector2(-200, 40))
	ok = expect(await settle_grounded(player, 60), "grounded-vy: player lands on floor") and ok
	for i: int in 3:
		await physics_frame
	ok = expect(player.is_on_floor(), "grounded-vy: settled on floor") and ok
	ok = expect(player.velocity.y == 0.0, "grounded-vy: residual cleared on landing (got %s)" % player.velocity.y) and ok
	Input.action_press("move_right")
	for i: int in 60:
		await physics_frame
	ok = expect(player.is_on_floor(), "grounded-vy: still grounded while walking") and ok
	ok = expect(player.velocity.y == 0.0, "grounded-vy: velocity.y == 0.0 while walking (got %s)" % player.velocity.y) and ok
	await cleanup(player, floor_body)
	# Landing-residual case: falling speed must read 0.0 once grounded.
	var floor_body2 := make_floor(Vector2(0, 100), Vector2(1000, 20))
	var player2 := spawn_player(Vector2(0, 57))
	player2.velocity.y = 200.0
	ok = expect(await settle_grounded(player2, 60), "grounded-vy: falling player lands") and ok
	for i: int in 5:
		await physics_frame
	ok = expect(player2.is_on_floor(), "grounded-vy: falling player stays grounded") and ok
	ok = expect(player2.velocity.y == 0.0, "grounded-vy: landing residual cleared (got %s)" % player2.velocity.y) and ok
	await cleanup(player2, floor_body2)
	return ok


func test_jump_cut() -> bool:
	var ok := true
	var floor_body := make_floor(Vector2(0, 100), Vector2(1000, 20))
	var player := spawn_player(Vector2(0, 40))
	ok = expect(await settle_grounded(player, 60), "cut: player lands on floor") and ok
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	await physics_frame
	ok = expect(player.velocity.y < -300.0, "cut: ascending before release (got %s)" % player.velocity.y) and ok
	var prev: float = player.velocity.y
	Input.action_release("jump")
	# The release reaches the controller a step later than the test observes it,
	# so scan frames until the cut multiplies the upward velocity.
	var cut := false
	for i: int in 6:
		await physics_frame
		var cur: float = player.velocity.y
		var ratio := cur / prev
		if ratio >= 0.35 and ratio <= 0.55:
			cut = true
			break
		prev = cur
	ok = expect(cut, "cut: velocity cut to ~0.45 once after release") and ok
	await physics_frame
	ok = expect(player.velocity.y < -70.0, "cut: still ascending, no second cut (got %s)" % player.velocity.y) and ok
	await cleanup(player, floor_body)
	return ok
