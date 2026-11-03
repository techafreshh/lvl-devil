class_name UIStrip extends CanvasLayer
## Persistent top strip: `LEVEL n` (1-based) on the left, all-time
## `DEATHS n` on the right. Children are code-built so the scene file
## can never drift out of sync; GameManager refreshes both labels
## synchronously on every death and level load. Test hooks (`set_level`,
## `set_deaths`, `refresh`) mirror the trap-script hooks.


const BAR_HEIGHT := 24.0

var _level_label: Label = null
var _deaths_label: Label = null


func _ready() -> void:
	layer = 10
	_build()


## Builds the bar plus the two direct-child labels; idempotent so a
## refresh before tree entry still lands on the exact texts.
func _build() -> void:
	if _level_label != null and is_instance_valid(_level_label):
		return
	var bar := ColorRect.new()
	bar.name = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = BAR_HEIGHT
	bar.color = Color(0.02, 0.02, 0.03, 0.85)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.position = Vector2(8, 3)
	_level_label.size = Vector2(200, 20)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.text = "LEVEL 1"
	add_child(_level_label)
	_deaths_label = Label.new()
	_deaths_label.name = "DeathsLabel"
	_deaths_label.anchor_left = 1.0
	_deaths_label.anchor_right = 1.0
	_deaths_label.offset_left = -208.0
	_deaths_label.offset_right = -8.0
	_deaths_label.offset_top = 3.0
	_deaths_label.offset_bottom = 23.0
	_deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_deaths_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deaths_label.text = "DEATHS 0"
	add_child(_deaths_label)


## Shows the 1-based level number on the left label.
func set_level(one_based: int) -> void:
	_build()
	_level_label.text = "LEVEL %d" % one_based


## Shows the all-time death total on the right label.
func set_deaths(n: int) -> void:
	_build()
	_deaths_label.text = "DEATHS %d" % n


## Pushes both counters at once; the only call GameManager makes.
func refresh(one_based: int, n: int) -> void:
	set_level(one_based)
	set_deaths(n)
