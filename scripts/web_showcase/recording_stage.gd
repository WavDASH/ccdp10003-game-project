## RecordingStage — minimal scene root used to author the showcase replay.
##
## Mirrors the relevant parts of main.gd: registers input actions, builds a
## TimelineManager + ActivePlayer + EchoContainer, loads the showcase room,
## and adds a ShowcaseRecorder. The exported web build does NOT include this
## scene — it's authoring-only.
extends Node2D

const SHOWCASE_ROOM := "res://scenes/web_showcase/showcase_room.tscn"

var player_scene := preload("res://scenes/player.tscn")
var echo_scene   := preload("res://scenes/echo_player.tscn")

@onready var timeline_manager: Node = $TimelineManager

var active_player: CharacterBody2D = null
var room_manager: Node2D = null
var echo_container: Node2D = null
var camera: Camera2D = null
var status_label: Label = null


func _ready() -> void:
	_setup_input()
	_build_room_manager()
	_build_player()
	_build_echo_container()
	_build_camera()
	_build_status_overlay()
	_build_recorder()
	_wire()
	room_manager.load_room("showcase")


# ─── Input (matches main.gd) ───
func _setup_input() -> void:
	_key("move_left",  KEY_A);     _key("move_left",  KEY_LEFT)
	_key("move_right", KEY_D);     _key("move_right", KEY_RIGHT)
	_key("jump",       KEY_SPACE); _key("jump",       KEY_I);     _key("jump",       KEY_UP)
	_key("dash",       KEY_SHIFT); _key("dash",       KEY_L)
	_key("move_up",    KEY_W);     _key("move_up",    KEY_UP)
	_key("move_down",  KEY_S);     _key("move_down",  KEY_DOWN)
	_key("reverse",    KEY_R);     _key("reverse",    KEY_J)
	_key("restart",    KEY_BACKSPACE)


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


# ─── Build subsystems ───
func _build_room_manager() -> void:
	room_manager = Node2D.new()
	room_manager.name = "RoomManager"
	room_manager.set_script(load("res://scripts/room_manager.gd"))
	room_manager.room_registry = {"showcase": SHOWCASE_ROOM}
	add_child(room_manager)


func _build_player() -> void:
	active_player = player_scene.instantiate()
	active_player.name = "ActivePlayer"
	active_player.add_to_group("active_player")
	add_child(active_player)


func _build_echo_container() -> void:
	echo_container = Node2D.new()
	echo_container.name = "EchoContainer"
	add_child(echo_container)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "RecordingCamera"
	camera.position = Vector2(640, 360)
	camera.zoom = Vector2(1, 1)
	add_child(camera)
	camera.make_current()


func _build_status_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RecordingHUD"
	add_child(layer)
	status_label = Label.new()
	status_label.position = Vector2(12, 8)
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	status_label.add_theme_constant_override("shadow_offset_x", 1)
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	status_label.text = "F9 start  •  F10 save  •  F11 discard  •  F8 marker  •  R reverse"
	layer.add_child(status_label)


func _build_recorder() -> void:
	var rec := Node.new()
	rec.name = "ShowcaseRecorder"
	rec.set_script(load("res://scripts/web_showcase/showcase_recorder.gd"))
	add_child(rec)


func _wire() -> void:
	timeline_manager.active_player    = active_player
	timeline_manager.echo_container   = echo_container
	timeline_manager.echo_player_scene = echo_scene
	active_player.timeline_manager    = timeline_manager
	room_manager.active_player        = active_player
	room_manager.timeline_manager     = timeline_manager
	room_manager.room_changed.connect(_on_room_changed)
	room_manager.player_spawn_found.connect(_on_spawn_found)


func _on_room_changed(room_id: String) -> void:
	timeline_manager.set_current_room(room_id)


func _on_spawn_found(spawn_pos: Vector2) -> void:
	timeline_manager.player_spawn_pos = spawn_pos


func _process(_delta: float) -> void:
	# Live status: recording state, frame count, marker count.
	var rec := get_node_or_null("ShowcaseRecorder")
	if rec == null or status_label == null:
		return
	var prefix := "F9 start  •  F10 save  •  F11 discard  •  F8 marker  •  R reverse"
	if rec.recording and rec.data:
		status_label.text = "● REC  %.2fs  %d frames  %d markers   (F10 save  F11 discard  F8 marker)" % [
			rec.data.duration, rec.data.frames.size(), rec.data.markers.size()]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 0.95))
	else:
		status_label.text = prefix
		status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
