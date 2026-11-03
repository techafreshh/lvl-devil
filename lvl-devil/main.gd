extends Node2D
## Bootstrap: hosts a GameManager and auto-resumes at the saved highest
## level (clamped on load, no continue screen). A null build aborts the
## load loudly instead of booting a broken level.


func _ready() -> void:
	print("lvl-devil ready")
	var manager := GameManager.new()
	manager.name = "Game"
	add_child(manager)
	if not manager.start_level(manager.highest_level):
		push_error("[Main] level %d failed to build; aborting load" % manager.highest_level)
		return
