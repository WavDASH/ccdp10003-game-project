## Main — top-level orchestrator.
##
## Builds the game shell (player, echo container, screen FX, HUD), creates
## the RoomManager, and wires subsystem references.  Room content is loaded
## by RoomManager; mechanisms/hazards/goals are auto-discovered via groups.
extends Node2D

var player_scene := preload("res://scenes/player.tscn")
var echo_scene   := preload("res://scenes/echo_player.tscn")

# ── Screen tint colors (forward = warm red, reverse = cool blue) ──
const TINT_FORWARD := Color(0.55, 0.08, 0.04, 0.06)
const TINT_REVERSE := Color(0.04, 0.1, 0.55, 0.14)

# ── Room registry: room_id → scene path ──
const ROOM_REGISTRY := {
	"room_01": "res://scenes/rooms/room_01.tscn",
	"room_02": "res://scenes/rooms/room_02.tscn",
}

const START_ROOM := "room_01"

# ── Node refs ──
@onready var timeline_manager: Node = $TimelineManager

var active_player: CharacterBody2D = null
var room_manager: Node2D = null
var echo_container: Node2D = null
var screen_fx: CanvasLayer = null
var hud_node = null
var time_tint: ColorRect = null
var flash_rect: ColorRect = null

# ═════════════════════════════════════════════════════════════════════
#  Setup
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_setup_input()
	_build_room_manager()
	_build_player()
	_build_echo_container()
	_build_screen_fx()
	_build_hud()
	_wire()
	# Load the starting room.
	room_manager.load_room(START_ROOM)


func _setup_input() -> void:
	_key("move_left",    KEY_A)
	_key("move_left",    KEY_LEFT)
	_key("move_right",   KEY_D)
	_key("move_right",   KEY_RIGHT)
	_key("jump",         KEY_SPACE)
	_key("jump",         KEY_I)
	_key("jump",         KEY_UP)
	_key("dash",         KEY_SHIFT)
	_key("dash",         KEY_L)
	_key("move_up",      KEY_W)
	_key("move_up",      KEY_UP)
	_key("move_down",    KEY_S)
	_key("move_down",    KEY_DOWN)
	_key("reverse",      KEY_R)
	_key("reverse",      KEY_J)
	_key("debug_toggle", KEY_F3)
	_key("restart",      KEY_BACKSPACE)


func _key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

# ═════════════════════════════════════════════════════════════════════
#  Room Manager
# ═════════════════════════════════════════════════════════════════════

func _build_room_manager() -> void:
	room_manager = Node2D.new()
	room_manager.name = "RoomManager"
	room_manager.set_script(load("res://scripts/room_manager.gd"))
	room_manager.room_registry = ROOM_REGISTRY
	add_child(room_manager)

# ═════════════════════════════════════════════════════════════════════
#  Player
# ═════════════════════════════════════════════════════════════════════

func _build_player() -> void:
	active_player = player_scene.instantiate()
	active_player.name = "ActivePlayer"
	add_child(active_player)

# ═════════════════════════════════════════════════════════════════════
#  Echo container
# ═════════════════════════════════════════════════════════════════════

func _build_echo_container() -> void:
	echo_container = Node2D.new()
	echo_container.name = "EchoContainer"
	add_child(echo_container)

# ═════════════════════════════════════════════════════════════════════
#  Screen FX (direction tint overlay + reversal flash)
# ═════════════════════════════════════════════════════════════════════

func _build_screen_fx() -> void:
	screen_fx = CanvasLayer.new()
	screen_fx.name = "ScreenFX"
	screen_fx.layer = 100
	add_child(screen_fx)

	time_tint = ColorRect.new()
	time_tint.name = "TimeTint"
	time_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_tint.color = TINT_FORWARD
	time_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_fx.add_child(time_tint)

	flash_rect = ColorRect.new()
	flash_rect.name = "Flash"
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_fx.add_child(flash_rect)

# ═════════════════════════════════════════════════════════════════════
#  HUD
# ═════════════════════════════════════════════════════════════════════

func _build_hud() -> void:
	hud_node = Control.new()
	hud_node.name = "HUD"
	hud_node.set_script(load("res://scripts/hud.gd"))
	hud_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_fx.add_child(hud_node)

# ═════════════════════════════════════════════════════════════════════
#  Wiring
# ═════════════════════════════════════════════════════════════════════

func _wire() -> void:
	# Timeline ↔ player/echo
	timeline_manager.active_player     = active_player
	timeline_manager.echo_container    = echo_container
	timeline_manager.echo_player_scene = echo_scene
	active_player.timeline_manager     = timeline_manager
	hud_node.timeline_manager          = timeline_manager

	# Room manager ↔ player + timeline
	room_manager.active_player = active_player
	room_manager.timeline_manager = timeline_manager

	# Signals from timeline
	timeline_manager.time_reversed.connect(_on_time_reversed)
	timeline_manager.level_restart_requested.connect(_on_restart)
	timeline_manager.level_completed.connect(_on_level_complete)

	# Signals from room manager
	room_manager.room_changed.connect(_on_room_changed)
	room_manager.player_spawn_found.connect(_on_spawn_found)

# ═════════════════════════════════════════════════════════════════════
#  Signal handlers
# ═════════════════════════════════════════════════════════════════════

func _on_room_changed(room_id: String) -> void:
	# Tell timeline about the new room (triggers full timeline reset + re-discovery).
	timeline_manager.set_current_room(room_id)
	# Reset screen tint to forward (timeline resets direction to +1 on room change).
	time_tint.color = TINT_FORWARD
	flash_rect.color.a = 0.0
	if hud_node:
		hud_node.hide_level_complete()
	# Snap camera limits to room bounds.
	var cam: Camera2D = active_player.get_node_or_null("Camera2D")
	if cam:
		var bounds: Rect2 = room_manager.get_room_bounds()
		cam.limit_left = int(bounds.position.x)
		cam.limit_top = int(bounds.position.y)
		cam.limit_right = int(bounds.end.x)
		cam.limit_bottom = int(bounds.end.y)


func _on_spawn_found(spawn_pos: Vector2) -> void:
	timeline_manager.player_spawn_pos = spawn_pos


func _on_time_reversed(new_dir: int) -> void:
	# White flash on reversal
	flash_rect.color = Color(1, 1, 1, 0.45)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.15)

	# Transition tint: red (forward) ↔ blue (reverse)
	var target := TINT_FORWARD if new_dir == 1 else TINT_REVERSE
	var tw2 := create_tween()
	tw2.tween_property(time_tint, "color", target, 0.25)


func _on_restart() -> void:
	time_tint.color = TINT_FORWARD
	flash_rect.color.a = 0.0
	if hud_node:
		hud_node.hide_level_complete()
	# Reload the current room to reset mechanisms.
	room_manager.load_room(room_manager.current_room_id)


func _on_level_complete() -> void:
	if hud_node:
		hud_node.show_level_complete()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		timeline_manager.restart_level()
