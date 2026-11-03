class_name GameManager extends Node
## Death/respawn manager: hosts the built level, freezes on death with a
## shape-burst, then rebuilds the level so every trap resets to grid state.
## Freeze is a wall-clock SceneTreeTimer with the player halted (never
## get_tree().paused or Engine.time_scale, which break headless timing).
## A generation counter keeps `R` during an in-flight death to one respawn.


const FREEZE_TIME := 0.1
const EXIT_DELAY := 0.2
const KILL_Y := 376.0
const DEATH_SFX_PATH := "res://sfx/death.wav"
const STRIP_SCENE_PATH := "res://scenes/ui_strip.tscn"
const TITLE_SCENE_PATH := "res://scenes/title.tscn"
const END_SCENE_PATH := "res://scenes/end_card.tscn"

enum State { TITLE, PLAYING, END }

var level_idx := 0
var current_level := 0
var total_deaths: int = 0
var highest_level: int = 0
var state: State = State.TITLE
var strip: UIStrip = null
var title: TitleScreen = null
var end_card: EndCard = null
var level: Node2D = null
var player: CharacterBody2D = null
var spawn_pos := Vector2.ZERO

var _dying := false
var _exiting := false
var _generation := 0


func _ready() -> void:
	add_to_group("game")
	var loaded := Save.load_data()
	highest_level = int(loaded.get("highest_level", 0))
	total_deaths = int(loaded.get("total_deaths", 0))
	ensure_strip()
	ensure_title()
	ensure_end_card()
	show_title()


## Creates the persistent HUD strip once (sibling of the rebuilt level so
## death respawns never destroy it). Loud return on a null load.
func ensure_strip() -> void:
	if strip != null and is_instance_valid(strip):
		return
	var packed := load(STRIP_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[Game] could not load strip scene %s" % STRIP_SCENE_PATH)
		return
	strip = packed.instantiate() as UIStrip
	if strip == null:
		push_error("[Game] could not instantiate strip scene %s" % STRIP_SCENE_PATH)
		return
	strip.name = "UIStrip"
	add_child(strip)


## Pushes both counters to the strip; safe when the strip failed to load.
func refresh_strip() -> void:
	if strip == null or not is_instance_valid(strip):
		return
	strip.refresh(current_level + 1, total_deaths)


## Creates the title overlay once; loud return on a null load.
func ensure_title() -> void:
	if title != null and is_instance_valid(title):
		return
	var packed := load(TITLE_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[Game] could not load title scene %s" % TITLE_SCENE_PATH)
		return
	title = packed.instantiate() as TitleScreen
	if title == null:
		push_error("[Game] could not instantiate title scene %s" % TITLE_SCENE_PATH)
		return
	title.name = "TitleScreen"
	add_child(title)


## Creates the end-card overlay once; loud return on a null load.
func ensure_end_card() -> void:
	if end_card != null and is_instance_valid(end_card):
		return
	var packed := load(END_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("[Game] could not load end-card scene %s" % END_SCENE_PATH)
		return
	end_card = packed.instantiate() as EndCard
	if end_card == null:
		push_error("[Game] could not instantiate end-card scene %s" % END_SCENE_PATH)
		return
	end_card.name = "EndCard"
	add_child(end_card)


## Parks on the title: hides the strip and end card, frees any level so
## boot builds nothing, and waits for any key to start at the saved best.
func show_title() -> void:
	_generation += 1
	_dying = false
	_exiting = false
	if is_instance_valid(level):
		remove_child(level)
		level.free()
	level = null
	player = null
	ensure_strip()
	ensure_title()
	ensure_end_card()
	if strip != null and is_instance_valid(strip):
		strip.visible = false
	if end_card != null and is_instance_valid(end_card):
		end_card.hide_card()
	if title != null and is_instance_valid(title):
		title.show_screen()
	state = State.TITLE
	refresh_strip()


## Parks on the end card after the L10 door: freezes the player, hides
## the strip, and shows the all-time total. Indices park at 0 (the wrap
## landing) while `highest_level` stays at max until `R` replays.
func show_end_card() -> void:
	current_level = 0
	level_idx = 0
	_exiting = false
	if player != null and is_instance_valid(player):
		(player as CharacterBody2D).set_physics_process(false)
		(player as CharacterBody2D).velocity = Vector2.ZERO
	ensure_end_card()
	if strip != null and is_instance_valid(strip):
		strip.visible = false
	if title != null and is_instance_valid(title):
		title.hide_screen()
	if end_card != null and is_instance_valid(end_card):
		end_card.show_card(total_deaths)
	state = State.END


## Replays from level 1, resetting progress but keeping all-time deaths.
func _play_again() -> bool:
	highest_level = 0
	Save.save_data(0, total_deaths)
	return start_level(0)


## Starts play at the saved best (fresh boots enter `LEVEL 1`).
func _start_from_title() -> bool:
	return start_level(maxi(highest_level, 0))


## Frees any old level, builds `idx` via LevelBuilder, records the spawn
## and wires every spike `killed` and door `exited` signal.
## Loud false on a null build.
func start_level(idx: int) -> bool:
	ensure_strip()
	ensure_title()
	ensure_end_card()
	if title != null and is_instance_valid(title):
		title.hide_screen()
	if end_card != null and is_instance_valid(end_card):
		end_card.hide_card()
	if strip != null and is_instance_valid(strip):
		strip.visible = true
	state = State.PLAYING
	current_level = idx
	level_idx = idx
	if is_instance_valid(level):
		remove_child(level)
		level.free()
	level = null
	player = null
	var built := LevelBuilder.build(idx)
	if built == null:
		push_error("[Game] level %d failed to build; aborting load" % idx)
		return false
	level = built
	add_child(level)
	player = level.get_node_or_null("Player") as CharacterBody2D
	if player == null:
		push_error("[Game] level %d: missing Player after build" % idx)
		return false
	spawn_pos = (player as Node2D).global_position
	var spikes := get_tree().get_nodes_in_group("spikes")
	for spike: Node in spikes:
		if spike.has_signal("killed"):
			(spike as PopupSpike).killed.connect(_on_spike_killed)
	var doors := get_tree().get_nodes_in_group("doors")
	for door: Node in doors:
		if door.has_signal("exited"):
			(door as FleeingDoor).exited.connect(_on_door_exited)
	_dying = false
	_exiting = false
	highest_level = maxi(highest_level, idx)
	Save.save_data(highest_level, total_deaths)
	refresh_strip()
	return true


func _on_spike_killed(_spike: Node) -> void:
	request_death("spike")


## Advances to the next dev level, wrapping around the gauntlet forever so
## a door on the last level loops back to dev level 0 and never loud-fails.
func next_level() -> bool:
	if Levels.count() <= 0:
		push_error("[Game] no levels to advance to")
		return false
	return start_level((current_level + 1) % Levels.count())


func _on_door_exited(_door: Node) -> void:
	if _exiting:
		return
	if level == null or not is_instance_valid(level):
		return
	_exiting = true
	var gen := _generation
	var from := current_level
	await get_tree().create_timer(EXIT_DELAY).timeout
	if gen != _generation:
		return
	# The last level exits to the end card; `next_level` keeps its wrap
	# so existing completion tests still observe the 0 landing.
	if from == Levels.count() - 1:
		show_end_card()
	else:
		next_level()


## Starts the death presentation unless one is already in flight.
## Halts the player, bursts particles, plays the squelch when shipped,
## waits FREEZE_TIME wall-clock, then rebuilds. Re-entrancy is guarded.
## Death accounting is same-frame: the counter and strip update before
## the freeze await so the label reads the new total within 1 frame.
func request_death(_cause: String) -> void:
	if _dying:
		return
	if level == null or not is_instance_valid(level):
		return
	if player == null or not is_instance_valid(player):
		return
	total_deaths += 1
	refresh_strip()
	Save.save_data(highest_level, total_deaths)
	_dying = true
	var gen := _generation
	var corpse: Vector2 = (player as Node2D).global_position
	(player as CharacterBody2D).set_physics_process(false)
	(player as CharacterBody2D).velocity = Vector2.ZERO
	_burst_particles(corpse)
	_play_death_sfx()
	await get_tree().create_timer(FREEZE_TIME).timeout
	if gen != _generation:
		return
	respawn()


## Fast-path instant restart: no freeze, safe mid-death via the counter.
func respawn() -> void:
	_generation += 1
	_dying = false
	start_level(level_idx)


func _physics_process(_delta: float) -> void:
	if state != State.PLAYING:
		return
	if _dying:
		return
	if player == null or not is_instance_valid(player):
		return
	if (player as Node2D).global_position.y > KILL_Y:
		request_death("fall")


func _unhandled_input(event: InputEvent) -> void:
	if state == State.TITLE:
		var go := false
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo:
				go = true
		elif event is InputEventAction:
			if (event as InputEventAction).pressed:
				go = true
		if go:
			_start_from_title()
			get_viewport().set_input_as_handled()
		return
	if state == State.END:
		if event.is_action_pressed("restart"):
			_play_again()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("restart"):
		respawn()
		get_viewport().set_input_as_handled()


func _burst_particles(at: Vector2) -> void:
	var burst := CPUParticles2D.new()
	burst.amount = 16
	burst.lifetime = 0.4
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 6.0
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.gravity = Vector2(0, 800)
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 260.0
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.color = Color(0.1, 0.1, 0.1)
	burst.position = at - get_global_offset()
	add_child(burst)
	burst.emitting = true
	# Child timer dies with the burst (and the manager), so freeing the
	# level mid-burst never leaves a dangling SceneTreeTimer lambda behind.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.one_shot = true
	burst.add_child(timer)
	timer.timeout.connect(burst.queue_free)
	timer.start()


## Global offset of this manager in world space (Main sits at the origin,
## so this is normally zero, but keeps the burst on the corpse regardless).
func get_global_offset() -> Vector2:
	var p := get_parent() as Node2D
	if p != null:
		return p.global_position
	return Vector2.ZERO


## Silent-safe death squelch: plays only when the wav has landed.
func _play_death_sfx() -> void:
	if not ResourceLoader.exists(DEATH_SFX_PATH):
		return
	var stream := load(DEATH_SFX_PATH) as AudioStream
	if stream == null:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
