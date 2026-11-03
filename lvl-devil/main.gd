extends Node2D
## Bootstrap: hosts a GameManager, which boots to the title screen (game
## name plus key legend; any key starts at the saved highest level). The
## L10 door shows the end card, and `R` there replays from level 1.


func _ready() -> void:
	print("lvl-devil ready")
	var manager := GameManager.new()
	manager.name = "Game"
	add_child(manager)
