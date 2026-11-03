class_name TitleScreen extends CanvasLayer
## One-screen title: game name, key legend, and a press-any-key prompt.
## Children are code-built so the scene file can never drift out of sync;
## GameManager shows this on every cold boot and hides it on any key.
## Flat palette, no scrolling: a full-screen near-black ColorRect plus
## five centered labels.

var _title_label: Label = null
var _legend_move: Label = null
var _legend_jump: Label = null
var _legend_restart: Label = null
var _prompt_label: Label = null


func _ready() -> void:
	layer = 20
	_build()


## Builds the background plus the five direct-child labels; idempotent so
## a show before tree entry still lands on the exact texts.
func _build() -> void:
	if _title_label != null and is_instance_valid(_title_label):
		return
	var bg := ColorRect.new()
	bg.name = "TitleBG"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.05, 0.05, 0.07)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_title_label = _make_label("TitleLabel", "LVL-DEVIL", 72.0)
	_legend_move = _make_label("LegendMove", "Arrows/WASD move", 132.0)
	_legend_jump = _make_label("LegendJump", "Space/Z jump", 158.0)
	_legend_restart = _make_label("LegendRestart", "R restart", 184.0)
	_prompt_label = _make_label("PromptLabel", "press any key to start", 244.0)


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


## Shows the title card; rebuilds first so early calls still land.
func show_screen() -> void:
	_build()
	visible = true


## Hides the title card when play starts.
func hide_screen() -> void:
	visible = false
