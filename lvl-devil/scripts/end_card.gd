class_name EndCard extends CanvasLayer
## One-screen end card: congratulations, the all-time death total, and a
## play-again prompt. Children are code-built so the scene file can never
## drift out of sync; GameManager shows this after the L10 door and hides
## it on replay. The deaths label is `EndDeaths` (not `DeathsLabel`) so
## manager label lookups never collide with the HUD strip.

var _done_label: Label = null
var _deaths_label: Label = null
var _prompt_label: Label = null


func _ready() -> void:
	layer = 20
	_build()


## Builds the background plus the three direct-child labels; idempotent so
## a show before tree entry still lands on the exact texts.
func _build() -> void:
	if _done_label != null and is_instance_valid(_done_label):
		return
	var bg := ColorRect.new()
	bg.name = "EndBG"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.05, 0.05, 0.07)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_done_label = _make_label("DoneLabel", "CONGRATULATIONS", 100.0)
	_deaths_label = _make_label("EndDeaths", "DEATHS 0", 150.0)
	_prompt_label = _make_label("PromptLabel", "press R to play again", 210.0)


## Full-width centered label at height `y`; keeps one screen with no scroll.
func _make_label(label_name: String, text: String, y: float) -> Label:
	var label := Label.new()
	label.name = label_name
	label.anchor_right = 1.0
	label.offset_top = y
	label.offset_bottom = y + 24.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	add_child(label)
	return label


## Shows the card with the all-time total; rebuilds first so early calls
## still land on the exact texts.
func show_card(deaths: int) -> void:
	_build()
	_deaths_label.text = "DEATHS %d" % deaths
	visible = true


## Hides the card when replay starts.
func hide_card() -> void:
	visible = false
