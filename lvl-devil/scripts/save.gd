class_name Save extends RefCounted
## Crash-proof JSON persistence for highest level and all-time deaths.
## Single slot at `user://save.json` with exact keys `highest_level`
## (0-based) and `total_deaths`. Static tree-free functions so headless
## `--script` suites can exercise them without a scene tree.
## Corrupt or missing files fall back to `{0,0}` and rewrite the file
## with only a `push_warning` (never `push_error`, never a crash).


const SAVE_PATH := "user://save.json"


## Loads and normalizes the save dict. Always returns a valid dict with
## int `highest_level` and `total_deaths`; never null. Repairs the file
## (rewrite + warning) when anything was missing, corrupt, mistyped,
## or out of range.
static func load_data(path := SAVE_PATH) -> Dictionary:
	var highest := 0
	var deaths := 0
	var needs_repair := false
	if not FileAccess.file_exists(path):
		needs_repair = true
	else:
		var parsed: Variant = null
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			needs_repair = true
		else:
			var text := file.get_as_text()
			file.close()
			parsed = JSON.parse_string(text)
			if parsed == null or not (parsed is Dictionary):
				needs_repair = true
				parsed = null
			else:
				var d := parsed as Dictionary
				var coerced_highest := _coerce_int(d.get("highest_level", null))
				var coerced_deaths := _coerce_int(d.get("total_deaths", null))
				if not d.has("highest_level") or not d.has("total_deaths"):
					needs_repair = true
				elif coerced_highest < 0 or coerced_deaths < 0:
					# Negative raw values normalize to 0 below; the file
					# no longer matches, so rewrite it.
					needs_repair = true
				highest = maxi(coerced_highest, 0)
				deaths = maxi(coerced_deaths, 0)
				var max_idx := maxi(Levels.count() - 1, 0)
				var clamped := clampi(highest, 0, max_idx)
				if clamped != highest:
					needs_repair = true
				highest = clamped
				# A mistyped value that coerced to 0 (e.g. a string) must
				# rewrite the file when the raw text disagrees.
				if _coerced_differs(d.get("highest_level", null), highest):
					needs_repair = true
				if _coerced_differs(d.get("total_deaths", null), deaths):
					needs_repair = true
	if needs_repair:
		push_warning("[Save] save missing or invalid at %s; repairing with defaults" % path)
		save_data(highest, deaths, path)
	return {"highest_level": highest, "total_deaths": deaths}


## Writes the save dict as compact JSON. Returns true on success.
static func save_data(highest: int, deaths: int, path := SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[Save] could not write save at %s" % path)
		return false
	file.store_string(JSON.stringify({"highest_level": highest, "total_deaths": deaths}))
	file.close()
	return true


## Coerces a parsed JSON value to int: ints (non-bool) as-is, floats
## via `int()`, anything else (missing, bool, string, array, dict) to 0.
static func _coerce_int(v: Variant) -> int:
	if v is bool:
		return 0
	if v is int:
		return v
	if v is float:
		return int(v)
	return 0


## True when the raw value would not round-trip to the normalized int,
## i.e. the file text disagrees and needs a rewrite.
static func _coerced_differs(raw: Variant, normalized: int) -> bool:
	if raw is bool:
		return true
	if raw is int:
		return int(raw) != normalized
	if raw is float:
		return int(raw) != normalized
	return true
