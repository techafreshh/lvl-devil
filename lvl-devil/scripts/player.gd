extends CharacterBody2D
## Tight, forgiving blob mover: instant walk, gravity, jump with coyote time,
## jump buffering, and early-release jump cut. All feel constants are exports
## so traps can be tuned against them later.


@export var speed := 170.0
@export var gravity := 1500.0
@export var jump_velocity := -420.0
@export var jump_cut := 0.45
@export var coyote_time := 0.08
@export var buffer_time := 0.10

const BODY_RECT := Rect2(-13, -13, 26, 26)
const BODY_RADIUS := 6

var _coyote := 0.0
var _buffer := 0.0
var _cut_applied := false
## Cached body style, created once and reused by _draw() so frequent
## redraws do not allocate a new StyleBoxFlat per draw.
var _body_style: StyleBoxFlat = null


func _physics_process(delta: float) -> void:
	# Gravity pulls the blob down while airborne.
	if not is_on_floor():
		velocity.y += gravity * delta
		_coyote -= delta
	else:
		_coyote = coyote_time
		if velocity.y > 0.0:
			velocity.y = 0.0

	# A fresh jump press is buffered so landing shortly after still jumps.
	if Input.is_action_just_pressed("jump"):
		queue_jump()
	else:
		_buffer = max(_buffer - delta, 0.0)

	# Buffered jump fires on the floor or inside the coyote window.
	if _buffer > 0.0 and (is_on_floor() or _coyote > 0.0):
		velocity.y = jump_velocity
		_buffer = 0.0
		_coyote = 0.0
		_cut_applied = false

	# Letting go early shortens an upward jump exactly once per jump.
	if Input.is_action_just_released("jump"):
		cut_jump()

	# Instant horizontal velocity keeps the walk test deterministic.
	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * speed

	move_and_slide()


## Test hook mirroring the real jump-press input path.
func queue_jump() -> void:
	_buffer = buffer_time


## Test hook mirroring the real jump-release input path (once per jump).
func cut_jump() -> void:
	if velocity.y < 0.0 and not _cut_applied:
		velocity.y *= jump_cut
		_cut_applied = true


## Lazily creates (once) and returns the cached body StyleBoxFlat.
## The null-guard keeps the first _draw() safe even if it precedes _ready().
func _get_body_style() -> StyleBoxFlat:
	if _body_style == null:
		_body_style = StyleBoxFlat.new()
		_body_style.bg_color = Color(0, 0, 0, 1)
		_body_style.set_corner_radius_all(BODY_RADIUS)
	return _body_style


func _draw() -> void:
	# Rounded-square black body, 26x26 px centered on the origin.
	draw_style_box(_get_body_style(), BODY_RECT)
	# Two plain white eyes.
	draw_circle(Vector2(-6, -2), 4.0, Color.WHITE)
	draw_circle(Vector2(6, -2), 4.0, Color.WHITE)
