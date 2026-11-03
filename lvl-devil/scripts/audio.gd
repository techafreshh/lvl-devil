class_name SfxBus extends Node
## Persistent SFX bus: preloads the five CC0 one-shots and plays each
## through its own AudioStreamPlayer child with a modest capped volume.
## Fire-and-forget: every play_* is null-guarded and never gates timing.

const JUMP_PATH := "res://assets/sfx/jump.wav"
const STING_PATH := "res://assets/sfx/sting.wav"
const SQUELCH_PATH := "res://assets/sfx/squelch.wav"
const CHIME_PATH := "res://assets/sfx/chime.wav"
const WHOOMPH_PATH := "res://assets/sfx/whoomph.wav"

var jump: AudioStreamPlayer = null
var sting: AudioStreamPlayer = null
var squelch: AudioStreamPlayer = null
var chime: AudioStreamPlayer = null
var whoomph: AudioStreamPlayer = null


func _ready() -> void:
	jump = _make_player("Jump", JUMP_PATH, -10.0)
	sting = _make_player("Sting", STING_PATH, -8.0)
	squelch = _make_player("Squelch", SQUELCH_PATH, -8.0)
	chime = _make_player("Chime", CHIME_PATH, -10.0)
	whoomph = _make_player("Whoomph", WHOOMPH_PATH, -12.0)


## Builds one named voice; a missing file still yields a muted-but-present
## player so the headless "stream != null" check only passes when shipped.
func _make_player(player_name: String, stream_path: String, volume: float) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = player_name
	voice.volume_db = volume
	if ResourceLoader.exists(stream_path):
		voice.stream = load(stream_path) as AudioStream
	add_child(voice)
	return voice


func play_jump() -> void:
	_play(jump)


func play_sting() -> void:
	_play(sting)


func play_squelch() -> void:
	_play(squelch)


func play_chime() -> void:
	_play(chime)


func play_whoomph() -> void:
	_play(whoomph)


func _play(voice: AudioStreamPlayer) -> void:
	if voice == null or not is_instance_valid(voice):
		return
	if voice.stream == null:
		return
	voice.play()
