extends SceneTree
## Headless title/end-card tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_title_end.gd
## Exits 1 when any check fails so CI can gate on the exit code.


var passed := 0
var failed := 0
var _backup_exists := false
var _backup_text := ""


func _initialize() -> void:
	await run_all()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func run_all() -> void:
	# Nodes need a frame before they can enter the tree cleanly.
	await process_frame
	_backup_save()
	var tests := [
		"test_title_labels",
		"test_any_key_starts_level_1",
		"test_l10_completion_shows_end_card",
		"test_r_on_end_card_replays",
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
	_restore_save()


## Non-counting check helper: never use bare assert() in a SceneTree runner.
func expect(cond: bool, label: String) -> bool:
	if not cond:
		push_error("FAIL " + label)
	return cond


func make_manager() -> GameManager:
	# Absolute-label asserts need a deterministic start: drop any leftover
	# save from earlier suites so _ready boots {0,0} (restored in run_all).
	if FileAccess.file_exists(Save.SAVE_PATH):
		DirAccess.remove_absolute(Save.SAVE_PATH)
	var mgr := GameManager.new()
	mgr.name = "Game"
	root.add_child(mgr)
	return mgr


func cleanup_manager(mgr: GameManager) -> void:
	if is_instance_valid(mgr):
		mgr.queue_free()
	await process_frame
	await physics_frame


func overlay_of(mgr: GameManager, node_name: String) -> Node:
	if not is_instance_valid(mgr):
		return null
	return mgr.get_node_or_null(node_name)


func overlay_text(overlay: Node, label_name: String) -> String:
	if overlay == null or not is_instance_valid(overlay):
		return ""
	var label := (overlay as Node).get_node_or_null(label_name) as Label
	if label == null:
		return ""
	return label.text


func strip_text(mgr: GameManager, label_name: String) -> String:
	if mgr.strip == null or not is_instance_valid(mgr.strip):
		return ""
	return overlay_text(mgr.strip, label_name)


func strip_visible(mgr: GameManager) -> bool:
	if mgr.strip == null or not is_instance_valid(mgr.strip):
		return false
	return (mgr.strip as CanvasLayer).visible


func _backup_save() -> void:
	_backup_exists = FileAccess.file_exists(Save.SAVE_PATH)
	if _backup_exists:
		var file := FileAccess.open(Save.SAVE_PATH, FileAccess.READ)
		if file != null:
			_backup_text = file.get_as_text()
			file.close()


func _restore_save() -> void:
	if _backup_exists:
		var file := FileAccess.open(Save.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup_text)
			file.close()
	else:
		if FileAccess.file_exists(Save.SAVE_PATH):
			DirAccess.remove_absolute(Save.SAVE_PATH)


## Rightmost exit door on the built level (L10's true exit, clear of the
## spike-guarded bait door).
func far_exit_door(mgr: GameManager) -> FleeingDoor:
	var best: FleeingDoor = null
	if mgr.level == null or not is_instance_valid(mgr.level):
		return null
	for child: Node in mgr.level.get_children():
		if child is FleeingDoor:
			if best == null or (child as Node2D).global_position.x > (best as Node2D).global_position.x:
				best = child as FleeingDoor
	return best


## Drives the manager onto the end card through the L10 true exit.
## Returns true once `CONGRATULATIONS` is up with the matching total.
func drive_to_end_card(mgr: GameManager) -> bool:
	if not mgr.start_level(Levels.count() - 1):
		return false
	await process_frame
	await physics_frame
	var door := far_exit_door(mgr)
	if door == null:
		return false
	(mgr.player as Node2D).global_position = (door as Node2D).global_position
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await physics_frame
		await process_frame
		if not is_instance_valid(mgr):
			return false
		if mgr.state == GameManager.State.END:
			return true
	return false


func test_title_labels() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.state == GameManager.State.TITLE, "title: fresh boot parks in TITLE") and ok
	var title := overlay_of(mgr, "TitleScreen")
	ok = expect(title != null, "title: TitleScreen exists") and ok
	ok = expect(title is CanvasLayer, "title: title is a CanvasLayer") and ok
	ok = expect((title as CanvasLayer).visible, "title: title is visible on boot") and ok
	ok = expect(overlay_text(title, "TitleLabel").contains("LVL-DEVIL"), "title: game name reads LVL-DEVIL") and ok
	ok = expect(overlay_text(title, "PromptLabel").to_lower().contains("press any key"), "title: prompt invites any key") and ok
	ok = expect(overlay_text(title, "LegendMove").contains("WASD"), "title: move legend names WASD") and ok
	ok = expect(overlay_text(title, "LegendJump").contains("Space/Z"), "title: jump legend names Space/Z") and ok
	ok = expect(overlay_text(title, "LegendRestart").contains("R restart"), "title: restart legend names R restart") and ok
	ok = expect(not strip_visible(mgr), "title: strip hides under the title") and ok
	ok = expect(mgr.level == null, "title: boot builds no level") and ok
	await cleanup_manager(mgr)
	return ok


func test_any_key_starts_level_1() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.state == GameManager.State.TITLE, "any-key: boot parks in TITLE") and ok
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.physical_keycode = KEY_SPACE
	var t0 := Time.get_ticks_msec()
	mgr._unhandled_input(ev)
	await process_frame
	var landed := false
	var elapsed := 0
	for i: int in 60:
		if mgr.state == GameManager.State.PLAYING and strip_text(mgr, "LevelLabel") == "LEVEL 1":
			elapsed = Time.get_ticks_msec() - t0
			landed = true
			break
		await process_frame
		if Time.get_ticks_msec() - t0 > 1000:
			break
	ok = expect(landed, "any-key: any key enters LEVEL 1") and ok
	if landed:
		ok = expect(elapsed < 1000, "any-key: title-to-level < 1s (got %dms)" % elapsed) and ok
	ok = expect(strip_visible(mgr), "any-key: strip shows once play starts") and ok
	ok = expect(mgr.current_level == 0 and mgr.level_idx == 0, "any-key: fresh boot starts at index 0") and ok
	await cleanup_manager(mgr)
	return ok


func test_l10_completion_shows_end_card() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(await drive_to_end_card(mgr), "end-card: L10 exit raises the end card") and ok
	if not is_instance_valid(mgr) or mgr.state != GameManager.State.END:
		await cleanup_manager(mgr)
		return ok
	var card := overlay_of(mgr, "EndCard")
	ok = expect(card != null, "end-card: EndCard exists") and ok
	ok = expect((card as CanvasLayer).visible, "end-card: card is visible") and ok
	ok = expect(overlay_text(card, "DoneLabel").contains("CONGRATULATIONS"), "end-card: done label congratulates") and ok
	var want := "DEATHS %d" % mgr.total_deaths
	ok = expect(overlay_text(card, "EndDeaths") == want, "end-card: deaths read '%s'" % want) and ok
	ok = expect(overlay_text(card, "PromptLabel").contains("press R to play again"), "end-card: prompt names R replay") and ok
	ok = expect(not strip_visible(mgr), "end-card: strip hides under the card") and ok
	ok = expect(mgr.current_level == 0 and mgr.level_idx == 0, "end-card: indices park at 0") and ok
	await cleanup_manager(mgr)
	return ok


func test_r_on_end_card_replays() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(await drive_to_end_card(mgr), "replay: L10 exit raises the end card") and ok
	if not is_instance_valid(mgr) or mgr.state != GameManager.State.END:
		await cleanup_manager(mgr)
		return ok
	var deaths := mgr.total_deaths
	var ev := InputEventAction.new()
	ev.action = "restart"
	ev.pressed = true
	var t0 := Time.get_ticks_msec()
	mgr._unhandled_input(ev)
	await process_frame
	var back := false
	var elapsed := 0
	for i: int in 60:
		if mgr.state == GameManager.State.PLAYING and strip_text(mgr, "LevelLabel") == "LEVEL 1":
			elapsed = Time.get_ticks_msec() - t0
			back = true
			break
		await process_frame
		if Time.get_ticks_msec() - t0 > 1000:
			break
	ok = expect(back, "replay: R returns to LEVEL 1") and ok
	if back:
		ok = expect(elapsed < 1000, "replay: card-to-level < 1s (got %dms)" % elapsed) and ok
	ok = expect(mgr.total_deaths == deaths, "replay: all-time deaths survive (%d)" % deaths) and ok
	var file_data := Save.load_data(Save.SAVE_PATH)
	ok = expect(int(file_data.get("highest_level", -1)) == 0, "replay: save highest resets to 0") and ok
	ok = expect(int(file_data.get("total_deaths", -1)) == deaths, "replay: save keeps deaths %d" % deaths) and ok
	await cleanup_manager(mgr)
	return ok
