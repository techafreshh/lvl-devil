class_name PopupSpike extends Area2D
## Pop-up spike trap: lies flat until the player is on the same row within
## trigger range, then extends near-instantly and stays out until respawn.
## Touching an active spike emits `killed` once for the death manager.
## Test hooks (`is_active`, `try_trigger`, `reset_spike`) decouple the
## trigger/kill logic from the player node, mirroring the player mover hooks.


signal killed(spike: PopupSpike)

const TRIGGER_DX := 38.0
const TRIGGER_SAME_ROW := 16.0

const LETHAL_SIZE := Vector2(32, 24)
const LETHAL_OFFSET := Vector2(0, 4)
const PLAYER_HALF := Vector2(13, 13)

var _active := false
var _emitted := false


func _ready() -> void:
	monitoring = true
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = LETHAL_SIZE
		shape_node.shape = rect
		shape_node.position = LETHAL_OFFSET
		add_child(shape_node)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	# Retracted spikes never collide until the proximity latch fires.
	if not _active and shape_node != null:
		shape_node.set_deferred("disabled", true)


func _physics_process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var p := tree.get_first_node_in_group("player") as Node2D
	if p != null and not _active:
		try_trigger((p as Node2D).global_position)
	if _active and not _emitted:
		_check_lethal(p)


func _check_lethal(p: Node2D) -> void:
	if p == null or not is_instance_valid(p):
		return
	# Physics overlap is authoritative when the engine has registered it.
	var bodies := get_overlapping_bodies()
	for b: Node in bodies:
		if b == p or (b as Node).is_in_group("player"):
			_emit_killed()
			return
	# Manual AABB fallback keeps the kill deterministic the same frame the
	# shape enables (headless timing) and matches the acceptance wording.
	var spike_center: Vector2 = global_position + LETHAL_OFFSET
	var lethal := Rect2(spike_center - LETHAL_SIZE / 2.0, LETHAL_SIZE)
	var body_rect := Rect2(p.global_position - PLAYER_HALF, PLAYER_HALF * 2.0)
	if lethal.intersects(body_rect):
		_emit_killed()


func _emit_killed() -> void:
	if _emitted:
		return
	_emitted = true
	killed.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if not _active or _emitted:
		return
	if body.is_in_group("player"):
		_emit_killed()


func _activate() -> void:
	if _active:
		return
	_active = true
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.set_deferred("disabled", false)
	queue_redraw()


## Latch check against a world position; same-row + horizontal range.
## Returns the latched state so headless tests need no player node.
func try_trigger(player_pos: Vector2) -> bool:
	if _active:
		return true
	var d: Vector2 = player_pos - global_position
	if absf(d.x) <= TRIGGER_DX and absf(d.y) <= TRIGGER_SAME_ROW:
		_activate()
	return _active


func is_active() -> bool:
	return _active


## Retract back to the flat state (used by level rebuild / tests).
func reset_spike() -> void:
	_active = false
	_emitted = false
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.set_deferred("disabled", true)
	queue_redraw()


func _draw() -> void:
	var plate := Color(0.85, 0.82, 0.75)
	if not _active:
		# Flat 32x6 base plate resting on the cell bottom.
		draw_rect(Rect2(Vector2(-16, 10), Vector2(32, 6)), plate)
		return
	# Extended: plate plus four light teeth rising from it.
	draw_rect(Rect2(Vector2(-16, 10), Vector2(32, 6)), plate)
	var teeth := Color(0.96, 0.95, 0.92)
	for i: int in 4:
		var x0 := -16.0 + float(i) * 8.0
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 10), Vector2(x0 + 8.0, 10), Vector2(x0 + 4.0, -8.0)]), teeth)
