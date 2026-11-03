extends Node2D
## Bootstrap: builds level 0 through LevelBuilder and hosts it.
## A null build aborts the load loudly instead of booting a broken level.


func _ready() -> void:
	print("lvl-devil ready")
	var level := LevelBuilder.build(0)
	if level == null:
		push_error("[Main] level 0 failed to build; aborting load")
		return
	add_child(level)
