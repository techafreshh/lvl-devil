class_name FallingTile extends StaticBody2D
## Falling floor tile: renders exactly like solid ground until the player
## stands on it, then shakes briefly, detaches, and falls while going
## non-solid so the player falls through. State machine IDLE -> SHAKING ->
## FALLING runs on per-tile physics polling, so chained adjacent tiles drop
## on independent timers. Level rebuild (GameManager respawn) restores every
## tile solid; `reset_tile` mirrors PopupSpike.reset_spike for headless tests.


const TILE_SIZE := 32
const SHAKE_TIME := 0.12
const SHAKE_AMP := 3.0
const SHAKE_FREQ := 220.0
const GRAVITY := 1500.0
const TRIGGER_ABOVE := 6.0
const TRIGGER_BELOW := 6.0
const TRIGGER_DX := 29.0
const PLAYER_HALF_Y := 13.0

const SOLID_COLOR := Color(0.85, 0.82, 0.75)

enum State { IDLE, SHAKING, FALLING }

var _state: int = State.IDLE
var _elapsed := 0.0
var _fall_v := 0.0
var _home := Vector2.ZERO


func _ready() -> void:
	add_to_group("solid_tiles")
	add_to_group("falling_tiles")
	if get_node_or_null("CollisionShape2D") == null:
		var shape_node := CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape_node.shape = rect
		add_child(shape_node)
	if get_node_or_null("ColorRect") == null:
		var visual := ColorRect.new()
		visual.name = "ColorRect"
		visual.size = Vector2(TILE_SIZE, TILE_SIZE)
		visual.position = Vector2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0)
		visual.color = SOLID_COLOR
		add_child(visual)
	_home = position


func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			var tree := get_tree()
			if tree == null:
				return
			var p := tree.get_first_node_in_group("player") as Node2D
			if p != null:
				try_trigger((p as Node2D).global_position)
		State.SHAKING:
			_elapsed += delta
			position.x = _home.x + sin(_elapsed * SHAKE_FREQ) * SHAKE_AMP
			if _elapsed >= SHAKE_TIME:
				_drop()
		State.FALLING:
			_fall_v += GRAVITY * delta
			position.y += _fall_v * delta


## Latch check against a player center position: bottom edge within 6px of
## the tile top with horizontal overlap. Side, below, and near-idle contact
## never latch. Returns the latched state so headless tests need no polling.
func try_trigger(player_pos: Vector2) -> bool:
	if _state != State.IDLE:
		return true
	if absf(player_pos.x - global_position.x) > TRIGGER_DX:
		return false
	var bottom := player_pos.y + PLAYER_HALF_Y
	var top := global_position.y - TILE_SIZE / 2.0
	if bottom < top - TRIGGER_ABOVE or bottom > top + TRIGGER_BELOW:
		return false
	_state = State.SHAKING
	_elapsed = 0.0
	_play_sting()
	return true


func _drop() -> void:
	_state = State.FALLING
	position.x = _home.x
	_fall_v = 0.0
	_play_whoomph()
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.set_deferred("disabled", true)


## SFX helpers via the persistent game bus; silent no-ops with no game.
func _play_sting() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var game := tree.get_first_node_in_group("game")
	if game != null and game.has_method("play_sting"):
		game.play_sting()


func _play_whoomph() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var game := tree.get_first_node_in_group("game")
	if game != null and game.has_method("play_whoomph"):
		game.play_whoomph()


func is_shaking() -> bool:
	return _state == State.SHAKING


func has_dropped() -> bool:
	return _state == State.FALLING


func home_pos() -> Vector2:
	return _home


## Restore the grid-cell solid state (used by tests; respawn rebuilds).
func reset_tile() -> void:
	_state = State.IDLE
	_elapsed = 0.0
	_fall_v = 0.0
	position = _home
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.set_deferred("disabled", false)
