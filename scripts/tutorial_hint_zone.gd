## TutorialHintZone — reusable contextual tutorial hint trigger.
##
## Place in a room scene wherever you want a hint to appear. When the active
## player overlaps the zone, a Label fades in. When the player leaves, it
## fades out. If `show_once` is true (default), each hint only appears the
## first time per game session (tracked by hint_id or node path).
##
## Usage:
##   1. Instance `scenes/tutorial_hint_zone.tscn` into a room.
##   2. Position it where the hint should trigger.
##   3. Set `hint_text` and optionally `zone_size`, `label_offset`, etc.
##
## No code changes needed per-room.
@tool
class_name TutorialHintZone
extends Node2D

@export_multiline var hint_text: String = "Tutorial hint":
	set(value):
		hint_text = value
		_update_label()
		queue_redraw()

## Size of the trigger rectangle (centered on this node).
@export var zone_size: Vector2 = Vector2(140, 140):
	set(value):
		zone_size = value
		queue_redraw()

## If true, the hint appears only once per session (tracked by hint_id).
@export var show_once: bool = true

## Stable id for the show_once registry. Falls back to node path if empty.
## Set this if you want the hint to survive room reloads deterministically.
@export var hint_id: String = ""

## Offset of the label relative to this node (world pixels).
@export var label_offset: Vector2 = Vector2(0, -80):
	set(value):
		label_offset = value
		_update_label()

@export var font_size: int = 16:
	set(value):
		font_size = value
		_update_label()

@export var fade_duration: float = 0.25

# Static registry of shown hint ids. Persists across room transitions within a
# single game session. Cleared by reset_shown() (e.g. from a "retry tutorial"
# option). NOT cleared on level restart so players aren't spammed after dying.
static var _shown_ids: Dictionary = {}

const _ACTOR_SIZE := Vector2(24, 48)

## Width of the label rect (used for word-wrapping and centering).
@export var label_width: float = 320.0:
	set(value):
		label_width = value
		_update_label()

var _label: Node = null  # Control-based Label; typed as Node for parser compat
var _is_active: bool = false
var _player_cache: Node2D = null
var _tween: Tween = null


func _ready() -> void:
	_ensure_label()
	if not Engine.is_editor_hint() and _label:
		_label.modulate.a = 0.0


func _ensure_label() -> void:
	_label = get_node_or_null("HintLabel")
	if _label == null:
		_label = ClassDB.instantiate("Label")
		if _label == null:
			push_error("TutorialHintZone: could not instantiate Label")
			return
		_label.name = "HintLabel"
		add_child(_label)
		if Engine.is_editor_hint():
			var root = get_tree().edited_scene_root if get_tree() else null
			if root:
				_label.owner = root
	_update_label()


func _update_label() -> void:
	if _label == null:
		return
	_label.text = hint_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(label_width, 0)
	_label.size = Vector2(label_width, 0)
	# Center the label horizontally around label_offset.
	_label.position = label_offset - Vector2(label_width / 2.0, 0)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_label.modulate = Color(1, 1, 1, _label.modulate.a)
	if Engine.is_editor_hint():
		_label.modulate.a = 0.7  # Preview in editor


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := _get_player()
	if player == null:
		return
	var id := _effective_id()
	var already_shown: bool = show_once and _shown_ids.get(id, false)
	if already_shown and not _is_active:
		return
	var overlap := _player_overlaps(player)
	if overlap and not _is_active:
		_is_active = true
		_fade(1.0)
		if show_once:
			_shown_ids[id] = true
	elif not overlap and _is_active:
		_is_active = false
		_fade(0.0)


func _player_overlaps(player: Node2D) -> bool:
	var my_rect := Rect2(global_position - zone_size / 2.0, zone_size)
	var pr := Rect2(player.global_position - _ACTOR_SIZE / 2.0, _ACTOR_SIZE)
	return my_rect.intersects(pr)


func _get_player() -> Node2D:
	if _player_cache and is_instance_valid(_player_cache):
		return _player_cache
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	_player_cache = tree.root.find_child("ActivePlayer", true, false)
	return _player_cache


func _fade(target_a: float) -> void:
	if _label == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", target_a, fade_duration)


func _effective_id() -> String:
	return hint_id if hint_id != "" else str(get_path())


## Clear the "shown" registry so all hints can appear again.
static func reset_shown() -> void:
	_shown_ids.clear()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := zone_size.x / 2.0
	var hh := zone_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), zone_size)
	draw_rect(rect, Color(0.95, 0.75, 0.2, 0.10), true)
	draw_rect(rect, Color(0.95, 0.75, 0.2, 0.55), false, 1.0)
	draw_string(ThemeDB.fallback_font,
		Vector2(-hw + 4, -hh + 11), "HINT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.75, 0.2, 0.75))
