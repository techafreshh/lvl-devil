extends SceneTree
## Headless SFX tests. Run with:
##   godot --headless --path lvl-devil --script res://tests/test_sfx.gd
## Exits 1 when any check fails so CI can gate on the exit code.


const SpikeScene := preload("res://scenes/spike.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

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
		"test_sfx_listing",
		"test_five_players_wired",
		"test_trigger_paths_no_crash",
		"test_death_respawn_fast",
		"test_no_music",
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
	var mgr := GameManager.new()
	mgr.name = "Game"
	root.add_child(mgr)
	return mgr


func cleanup_manager(mgr: GameManager) -> void:
	if is_instance_valid(mgr):
		mgr.queue_free()
	await process_frame
	await physics_frame


func cleanup_extra(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	for n: Node in root.get_children():
		if n.is_in_group("player") or n.is_in_group("spikes"):
			if is_instance_valid(n) and n.name != "Game":
				n.queue_free()
	await process_frame
	await physics_frame


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


func bus_players(mgr: GameManager) -> Array:
	if mgr == null or not is_instance_valid(mgr):
		return []
	return mgr.find_children("*", "AudioStreamPlayer", true, false)


func player_at_spawn(mgr: GameManager) -> bool:
	if mgr.player == null or not is_instance_valid(mgr.player):
		return false
	return (mgr.player as Node2D).global_position.distance_to(mgr.spawn_pos) <= 2.0


func test_sfx_listing() -> bool:
	var ok := true
	var dir := DirAccess.open("res://assets/sfx")
	ok = expect(dir != null, "listing: res://assets/sfx exists") and ok
	if dir == null:
		return ok
	var audio_files: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and (entry.ends_with(".wav") or entry.ends_with(".ogg")):
			audio_files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	audio_files.sort()
	ok = expect(audio_files.size() == 5, "listing: exactly 5 wav/ogg files (got %d: %s)" % [audio_files.size(), audio_files]) and ok
	for want: String in ["chime", "jump", "squelch", "sting", "whoomph"]:
		var found := false
		for f: String in audio_files:
			if f.get_basename() == want:
				found = true
		ok = expect(found, "listing: %s.* ships" % want) and ok
	ok = expect(FileAccess.file_exists("res://assets/sfx/README.md"), "listing: README.md ships") and ok
	var readme := _read_text("res://assets/sfx/README.md")
	ok = expect(readme.contains("CC0"), "listing: README names CC0") and ok
	ok = expect(readme.contains("Kenney"), "listing: README names Kenney") and ok
	return ok


func test_five_players_wired() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "wired: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	var players := bus_players(mgr)
	ok = expect(players.size() == 5, "wired: exactly 5 AudioStreamPlayers under the manager (got %d)" % players.size()) and ok
	for voice: Node in players:
		var player := voice as AudioStreamPlayer
		ok = expect(player != null and player.stream != null, "wired: %s has stream != null" % voice.name) and ok
		if player != null:
			ok = expect(player.volume_db <= -6.0, "wired: %s volume_db <= -6.0 (got %s)" % [voice.name, player.volume_db]) and ok
	# Respawn rebuild must keep the same five voices (persistent bus).
	var before := players.size()
	mgr.respawn()
	await process_frame
	await process_frame
	var after := bus_players(mgr)
	ok = expect(after.size() == 5 and after.size() == before, "wired: 5 voices survive respawn (got %d)" % after.size()) and ok
	for voice: Node in after:
		var player := voice as AudioStreamPlayer
		ok = expect(player != null and player.stream != null, "wired: %s still wired after respawn" % voice.name) and ok
	await cleanup_manager(mgr)
	return ok


func test_trigger_paths_no_crash() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(1), "paths: start_level(1) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	# Every bus entry point fires without error on the dummy audio driver.
	mgr.play_jump()
	mgr.play_sting()
	mgr.play_squelch()
	mgr.play_chime()
	mgr.play_whoomph()
	if mgr.get("_sfx") != null:
		var bus: Node = mgr.get("_sfx")
		for m: String in ["play_jump", "play_sting", "play_squelch", "play_chime", "play_whoomph"]:
			if bus.has_method(m):
				bus.call(m)
	await process_frame
	ok = expect(true, "paths: bus play_* calls do not crash") and ok
	# Spike sting at the extend latch.
	var spike := SpikeScene.instantiate() as PopupSpike
	root.add_child(spike)
	await process_frame
	(spike as Node2D).global_position = Vector2(400, 0)
	ok = expect((spike as PopupSpike).try_trigger(Vector2(400, 0)), "paths: spike try_trigger latches") and ok
	await physics_frame
	await cleanup_extra([spike])
	# Falling-tile sting at the shake latch plus whoomph at the drop.
	var rows := PackedStringArray([".....", "..P..", "..X..", "#####"])
	var level := LevelBuilder.build_from_rows(rows, 91)
	ok = expect(level != null, "paths: X grid builds") and ok
	if level != null:
		root.add_child(level)
		await process_frame
		var tile := level.get_node_or_null("FallingTile_2_2") as FallingTile
		ok = expect(tile != null, "paths: falling tile exists") and ok
		if tile != null:
			var top: Vector2 = (tile as Node2D).global_position - Vector2(0, 16)
			ok = expect(tile.try_trigger(top - Vector2(0, 13)), "paths: tile try_trigger latches (sting)") and ok
			tile._drop()
			await process_frame
			ok = expect(tile.has_dropped(), "paths: tile _drop lands (whoomph)") and ok
		await cleanup_extra([level])
	# Door sting at the dodge start.
	var door := FleeingDoor.new()
	root.add_child(door)
	await process_frame
	(door as Node2D).global_position = Vector2(200, 200)
	door.setup(true, Vector2(300, 200), Vector2(0, 200))
	door.try_trigger(Vector2(120, 200), Vector2(100, 0))
	await process_frame
	# Door chime plus death squelch through the manager.
	mgr._on_door_exited(mgr.level.get_children()[0] if mgr.level.get_child_count() > 0 else null)
	await process_frame
	mgr.play_squelch()
	mgr.request_death("test")
	for i: int in 30:
		await process_frame
		if player_at_spawn(mgr):
			break
	ok = expect(player_at_spawn(mgr), "paths: request_death still respawns to spawn") and ok
	await cleanup_extra([door])
	await cleanup_manager(mgr)
	return ok


func test_death_respawn_fast() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "fast: start_level(0) builds") and ok
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
	ok = expect(back, "fast: kill-plane death returns to spawn") and ok
	if back:
		ok = expect(elapsed < 500, "fast: death-to-playing < 0.5s (got %dms)" % elapsed) and ok
	await cleanup_manager(mgr)
	return ok


func test_no_music() -> bool:
	var ok := true
	var mgr := make_manager()
	await process_frame
	ok = expect(mgr.start_level(0), "music: start_level(0) builds") and ok
	if not ok:
		await cleanup_manager(mgr)
		return ok
	await process_frame
	var players := bus_players(mgr)
	for voice: Node in players:
		var player := voice as AudioStreamPlayer
		if player != null and player.stream != null:
			var length := 0.0
			if player.stream.has_method("get_length"):
				length = float(player.stream.call("get_length"))
			ok = expect(length < 1.0, "music: %s one-shot < 1s (got %s)" % [voice.name, length]) and ok
	var names := ["res://assets/sfx", "res://assets", "res://"]
	var stray := ""
	for dir_path: String in names:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.to_lower().begins_with("music"):
				stray = dir_path + "/" + entry
			entry = dir.get_next()
		dir.list_dir_end()
	ok = expect(stray == "", "music: no music.* asset ships (found '%s')" % stray) and ok
	await cleanup_manager(mgr)
	return ok
