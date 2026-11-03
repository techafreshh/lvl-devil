extends SceneTree
## Headless persistence tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_persistence.gd
## Exits 1 when any check fails so CI can gate on the exit code.


const TMP_PATH := "user://test_persistence_tmp.json"

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
		"test_missing_save_defaults",
		"test_round_trip_substrings",
		"test_corrupt_rewrites",
		"test_clamp_and_types",
		"test_death_persists_and_updates_strip",
		"test_unlock_advances_highest",
		"test_boot_resume_labels",
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
	_wipe(TMP_PATH)


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


func test_missing_save_defaults() -> bool:
	var ok := true
	_wipe(TMP_PATH)
	ok = expect(not FileAccess.file_exists(TMP_PATH), "missing: temp file removed") and ok
	var data := Save.load_data(TMP_PATH)
	ok = expect(int(data.get("highest_level", -1)) == 0, "missing: highest defaults to 0") and ok
	ok = expect(int(data.get("total_deaths", -1)) == 0, "missing: deaths defaults to 0") and ok
	ok = expect(FileAccess.file_exists(TMP_PATH), "missing: load recreates the file") and ok
	_wipe(TMP_PATH)
	return ok


func test_round_trip_substrings() -> bool:
	var ok := true
	_wipe(TMP_PATH)
	ok = expect(Save.save_data(2, 5, TMP_PATH), "round-trip: save returns true") and ok
	var raw := _read_text(TMP_PATH)
	ok = expect(raw.contains("\"highest_level\":2"), "round-trip: raw holds highest_level 2") and ok
	ok = expect(raw.contains("\"total_deaths\""), "round-trip: raw holds total_deaths") and ok
	var reloaded := Save.load_data(TMP_PATH)
	ok = expect(int(reloaded.get("highest_level", -1)) == 2, "round-trip: reload keeps highest 2") and ok
	ok = expect(int(reloaded.get("total_deaths", -1)) == 5, "round-trip: reload keeps deaths 5") and ok
	_wipe(TMP_PATH)
	return ok


func test_corrupt_rewrites() -> bool:
	var ok := true
	_wipe(TMP_PATH)
	ok = expect(_write_text(TMP_PATH, "{{{not-json"), "corrupt: seed text written") and ok
	var data := Save.load_data(TMP_PATH)
	ok = expect(int(data.get("highest_level", -1)) == 0, "corrupt: highest falls back to 0") and ok
	ok = expect(int(data.get("total_deaths", -1)) == 0, "corrupt: deaths falls back to 0") and ok
	var raw := _read_text(TMP_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	ok = expect(parsed is Dictionary, "corrupt: file is valid JSON after load") and ok
	if parsed is Dictionary:
		ok = expect(int((parsed as Dictionary).get("highest_level", -1)) == 0, "corrupt: repaired file holds 0") and ok
	_wipe(TMP_PATH)
	return ok


func test_clamp_and_types() -> bool:
	var ok := true
	var max_idx := Levels.count() - 1
	_wipe(TMP_PATH)
	ok = expect(Save.save_data(99, 4, TMP_PATH), "clamp: over-range save writes") and ok
	var over := Save.load_data(TMP_PATH)
	ok = expect(int(over.get("highest_level", -99)) == max_idx, "clamp: 99 clamps to %d" % max_idx) and ok
	ok = expect(_write_text(TMP_PATH, "{\"highest_level\":-2,\"total_deaths\":3}"), "clamp: negative seed written") and ok
	var neg := Save.load_data(TMP_PATH)
	ok = expect(int(neg.get("highest_level", -99)) == 0, "clamp: -2 clamps to 0") and ok
	ok = expect(int(neg.get("total_deaths", -99)) == 3, "clamp: deaths 3 survives") and ok
	ok = expect(_write_text(TMP_PATH, "{\"highest_level\":\"three\",\"total_deaths\":7}"), "clamp: string seed written") and ok
	var typed := Save.load_data(TMP_PATH)
	ok = expect(int(typed.get("highest_level", -99)) == 0, "clamp: string highest coerces to 0") and ok
	ok = expect(int(typed.get("total_deaths", -99)) == 7, "clamp: deaths 7 survives mistyped sibling") and ok
	_wipe(TMP_PATH)
	return ok


func test_death_persists_and_updates_strip() -> bool:
	var ok := true
	_wipe(Save.SAVE_PATH)
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "death-persist: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	var old_player := mgr.player
	(mgr.player as Node2D).global_position = Vector2(mgr.spawn_pos.x, 400.0)
	# Same-frame accounting: two signal resumes bracket the physics step
	# that trips the kill plane (mirrors the UI-strip fall test).
	await physics_frame
	await physics_frame
	ok = expect(mgr.total_deaths == 1, "death-persist: total_deaths is 1 after one frame") and ok
	ok = expect(label_text(strip_of(mgr), "DeathsLabel") == "DEATHS 1", "death-persist: label reads DEATHS 1 within 2 frames") and ok
	var file_data := Save.load_data(Save.SAVE_PATH)
	ok = expect(int(file_data.get("total_deaths", -1)) == 1, "death-persist: file holds deaths 1") and ok
	# Let the freeze finish so cleanup never frees a mid-death manager.
	var back := false
	for i: int in 60:
		await physics_frame
		await process_frame
		if is_instance_valid(mgr.player) and mgr.player != old_player and player_at_spawn(mgr):
			back = true
			break
	ok = expect(back, "death-persist: kill-plane death respawns to P") and ok
	await cleanup_manager(mgr)
	return ok


func test_unlock_advances_highest() -> bool:
	var ok := true
	var max_idx := Levels.count() - 1
	_wipe(Save.SAVE_PATH)
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "unlock: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	ok = expect(mgr.highest_level == 0, "unlock: highest starts at 0") and ok
	ok = expect(mgr.next_level(), "unlock: next_level() advances") and ok
	await process_frame
	ok = expect(mgr.current_level == 1, "unlock: current_level is 1") and ok
	ok = expect(mgr.highest_level == 1, "unlock: highest advances to 1") and ok
	var mid := Save.load_data(Save.SAVE_PATH)
	ok = expect(int(mid.get("highest_level", -1)) == 1, "unlock: file holds highest 1") and ok
	# The gauntlet wraps on the last level but progress never regresses.
	ok = expect(mgr.start_level(max_idx), "unlock: start_level(last) builds") and ok
	await process_frame
	ok = expect(mgr.highest_level == max_idx, "unlock: highest reaches last index") and ok
	ok = expect(mgr.next_level(), "unlock: next_level() wraps off the end") and ok
	await process_frame
	ok = expect(mgr.current_level == 0, "unlock: wrap lands on level 0") and ok
	ok = expect(mgr.highest_level == max_idx, "unlock: highest keeps max across wrap") and ok
	var wrapped := Save.load_data(Save.SAVE_PATH)
	ok = expect(int(wrapped.get("highest_level", -1)) == max_idx, "unlock: file keeps max across wrap") and ok
	await cleanup_manager(mgr)
	return ok


func test_boot_resume_labels() -> bool:
	var ok := true
	ok = expect(Save.save_data(3, 7), "resume: seed {3,7} writes") and ok
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.highest_level == 3, "resume: manager loads highest 3") and ok
	ok = expect(mgr.total_deaths == 7, "resume: manager loads deaths 7") and ok
	ok = expect(mgr.start_level(mgr.highest_level), "resume: boot at saved highest builds") and ok
	await process_frame
	ok = expect(mgr.current_level == 3, "resume: current_level is 3") and ok
	var strip := strip_of(mgr)
	ok = expect(label_text(strip, "LevelLabel") == "LEVEL 4", "resume: strip reads LEVEL 4") and ok
	ok = expect(label_text(strip, "DeathsLabel") == "DEATHS 7", "resume: strip reads DEATHS 7") and ok
	await cleanup_manager(mgr)
	return ok
