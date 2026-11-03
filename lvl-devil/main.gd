extends Node2D
## Bootstrap: hosts a GameManager and starts level 0 through it.
## A null build aborts the load loudly instead of booting a broken level.


func _ready() -> void:
	print("lvl-devil ready")
	var manager := GameManager.new()
	manager.name = "Game"
	add_child(manager)
	if not manager.start_level(0):
		push_error("[Main] level 0 failed to build; aborting load")
		return
