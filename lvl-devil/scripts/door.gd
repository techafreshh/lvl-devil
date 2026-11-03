class_name FleeingDoor extends Area2D
## Exit door: `d` static exits and `D` fleeing doors share this scene.
## A fleeing door dodges exactly once per attempt: when the player is
## within range, has left spawn, and is approaching, it tweens to its `T`
## landing cell and stays catchable. Touching any door emits `exited`
## once for the progression manager. Test hooks (`try_trigger`,
## `has_dodged`) decouple the dodge logic from the player node,
## mirroring the spike latch hooks.


signal dodged(door: FleeingDoor)
signal exited(door: FleeingDoor)

const TRIGGER_RANGE := 160.0
const SPAWN_GATE := 32.0
const DODGE_TIME := 0.3
const APPROACH_MIN := 10.0
const EXIT_HALF := Vector2(15, 20)
const PLAYER_HALF := Vector2(13, 13)

var _fleeing := false
var _dodged := false
var _exiting := false
var _target := Vector2.ZERO
var _spawn := Vector2.ZERO
var _prev_dist := -1.0


func _ready() -> void:
	monitoring = true
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(30, 40)
		shape_node.shape = rect
		add_child(shape_node)
	else:
		shape_node.set_deferred("disabled", false)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var p := tree.get_first_node_in_group("player") as Node2D
	if p == null or not is_instance_valid(p):
		return
	var vel := Vector2.ZERO
	if p is CharacterBody2D:
		vel = (p as CharacterBody2D).velocity
	if not _dodged and _fleeing:
		try_trigger(p.global_position, vel)
	if not _exiting:
		_check_exit(p)


func _check_exit(p: Node2D) -> void:
	if p == null or not is_instance_valid(p):
		return
	# Physics overlap is authoritative when the engine has registered it.
	var bodies := get_overlapping_bodies()
	for b: Node in bodies:
		if b == p or (b as Node).is_in_group("player"):
			_emit_exited()
			return
	# Manual AABB fallback keeps the exit deterministic the same frame the
	# bodies touch (headless timing) and matches the acceptance wording.
	var door_rect := Rect2(global_position - EXIT_HALF, EXIT_HALF * 2.0)
	var body_rect := Rect2(p.global_position - PLAYER_HALF, PLAYER_HALF * 2.0)
	if door_rect.intersects(body_rect):
		_emit_exited()


func _emit_exited() -> void:
	if _exiting:
		return
	_exiting = true
	exited.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if _exiting:
		return
	if body.is_in_group("player"):
		_emit_exited()


## Stores the door kind, landing cell, and attempt spawn. Static doors
## ignore the dodge logic entirely; fleeing doors tween to `target` once.
func setup(fleeing: bool, target: Vector2, spawn: Vector2) -> void:
	_fleeing = fleeing
	_target = target
	_spawn = spawn
	_dodged = false
	_exiting = false
	_prev_dist = -1.0


func has_dodged() -> bool:
	return _dodged


## Dodge latch against a world position plus the player velocity.
## Returns the latched state so headless tests need no player node.
## Approaching is velocity-toward-door OR frame-over-frame distance
## decrease (teleport-driven probes have zero velocity).
func try_trigger(player_pos: Vector2, player_velocity := Vector2.ZERO) -> bool:
	if _dodged:
		return true
	if not _fleeing:
		return false
	var dist := global_position.distance_to(player_pos)
	var approaching := false
	var to_door := global_position - player_pos
	if to_door.length() > 0.001:
		approaching = player_velocity.dot(to_door.normalized()) > APPROACH_MIN
	if not approaching and _prev_dist >= 0.0 and dist < _prev_dist - 0.5:
		approaching = true
	var in_range := dist <= TRIGGER_RANGE
	var left_spawn := player_pos.distance_to(_spawn) >= SPAWN_GATE
	_prev_dist = dist
	if in_range and left_spawn and approaching:
		_fire_dodge()
	return _dodged


func _fire_dodge() -> void:
	if _dodged:
		return
	_dodged = true
	var tw := create_tween()
	tw.tween_property(self, "position", _target, DODGE_TIME)
	tw.finished.connect(func() -> void: dodged.emit(self))


func _draw() -> void:
	var body := Color(0.16, 0.12, 0.22)
	var frame := Color(0.85, 0.82, 0.75)
	draw_rect(Rect2(Vector2(-15, -20), Vector2(30, 40)), body)
	draw_rect(Rect2(Vector2(-15, -20), Vector2(30, 40)), frame, false, 3.0)
	draw_circle(Vector2(8, 0), 2.5, frame)
