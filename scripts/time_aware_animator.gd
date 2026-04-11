## TimeAwareAnimator — component node for direction-aware animation playback.
##
## Add as a child of any entity that has an AnimatedSprite2D or AnimationPlayer
## sibling. Each physics frame it reads time_direction from TimelineManager and
## adjusts playback accordingly:
##   - Forward: normal playback (speed_scale = 1)
##   - Reverse: AnimatedSprite2D → manual frame decrement;
##              AnimationPlayer → speed_scale = -1
##
## Also provides get_animation_state() / apply_animation_state() for echo
## frame recording and replay.
class_name TimeAwareAnimator
extends Node

## Which sibling to auto-detect. Leave empty to auto-detect the first
## AnimatedSprite2D or AnimationPlayer found among siblings.
@export var target_node_path: NodePath = NodePath("")

var _target: Node = null
var _timeline: Node = null  # TimelineManager reference
var _last_direction: int = 1
var _frame_accumulator: float = 0.0

# For AnimatedSprite2D manual reverse: track elapsed time per frame.
var _manual_frame_time: float = 0.0
var _last_anim_name: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_find_target()
	_find_timeline()


func _find_target() -> void:
	_target = null
	if target_node_path != NodePath(""):
		var t = get_node_or_null(target_node_path)
		if t is AnimatedSprite2D or t is AnimationPlayer:
			_target = t
			return

	# Auto-detect among siblings.
	var parent_node = get_parent()
	if parent_node == null:
		return
	for child in parent_node.get_children():
		if child == self:
			continue
		if child is AnimatedSprite2D:
			_target = child
			return
		if child is AnimationPlayer:
			_target = child
			return


func _ensure_target() -> void:
	if _target == null or not is_instance_valid(_target):
		_find_target()


## Public: parents call this after swapping placeholder Visual for a real
## AnimatedSprite2D/AnimationPlayer at runtime.
func refresh_target() -> void:
	_find_target()


func _find_timeline() -> void:
	# Walk up to find TimelineManager in the tree (set by main.gd as autoload-like).
	_timeline = get_node_or_null("/root/Main/TimelineManager")
	if _timeline == null:
		# Fallback: search tree for any TimelineManager.
		var nodes = get_tree().get_nodes_in_group("timeline_manager")
		if nodes.size() > 0:
			_timeline = nodes[0]


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_target()
	if _target == null:
		return

	var direction := _get_time_direction()
	_apply_direction(direction, _delta)
	_last_direction = direction


func _get_time_direction() -> int:
	if _timeline and _timeline.has_method("get_debug_info"):
		return _timeline.time_direction
	return 1


func _apply_direction(direction: int, delta: float) -> void:
	if _target is AnimatedSprite2D:
		_apply_direction_animated_sprite(direction, delta)
	elif _target is AnimationPlayer:
		_apply_direction_animation_player(direction)


func _apply_direction_animated_sprite(direction: int, delta: float) -> void:
	var sprite: AnimatedSprite2D = _target as AnimatedSprite2D
	if sprite.sprite_frames == null:
		return

	var anim_name: String = sprite.animation
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 1:
		return

	# Reset frame-time accumulator when animation changes to prevent glitches.
	if anim_name != _last_anim_name:
		_manual_frame_time = 0.0
		_last_anim_name = anim_name

	if direction >= 0:
		# Forward: let Godot handle normal playback.
		if sprite.speed_scale < 0:
			sprite.speed_scale = abs(sprite.speed_scale)
		if not sprite.is_playing():
			sprite.play()
	else:
		# Reverse: manual frame decrement.
		# Pause auto-play and step frames backwards based on FPS.
		sprite.stop()
		var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
		if fps <= 0:
			fps = 10.0
		_manual_frame_time += delta
		var frame_duration: float = 1.0 / fps
		while _manual_frame_time >= frame_duration:
			_manual_frame_time -= frame_duration
			var new_frame: int = sprite.frame - 1
			if new_frame < 0:
				if sprite.sprite_frames.get_animation_loop(anim_name):
					new_frame = frame_count - 1
				else:
					new_frame = 0
			sprite.frame = new_frame


func _apply_direction_animation_player(direction: int) -> void:
	var player: AnimationPlayer = _target as AnimationPlayer
	if direction >= 0:
		if player.speed_scale < 0:
			player.speed_scale = abs(player.speed_scale)
	else:
		if player.speed_scale > 0:
			player.speed_scale = -abs(player.speed_scale)


# ─── State recording / replay (for echo system) ─────────────────────

## Returns current animation state as a Dictionary for frame recording.
func get_animation_state() -> Dictionary:
	_ensure_target()
	if _target == null:
		return {}

	if _target is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = _target as AnimatedSprite2D
		return {
			"anim_name": sprite.animation,
			"anim_frame": sprite.frame,
			"anim_flip_h": sprite.flip_h,
		}
	elif _target is AnimationPlayer:
		var player: AnimationPlayer = _target as AnimationPlayer
		return {
			"anim_name": player.current_animation,
			"anim_progress": player.current_animation_position,
		}

	return {}


## Restores animation state from a recorded frame Dictionary.
func apply_animation_state(state: Dictionary) -> void:
	_ensure_target()
	if _target == null:
		return

	if _target is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = _target as AnimatedSprite2D
		var anim_name: String = state.get("anim_name", "")
		if anim_name != "" and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
			if sprite.animation != anim_name:
				sprite.animation = anim_name
			sprite.frame = state.get("anim_frame", 0)
			sprite.flip_h = state.get("anim_flip_h", false)
	elif _target is AnimationPlayer:
		var player: AnimationPlayer = _target as AnimationPlayer
		var anim_name: String = state.get("anim_name", "")
		if anim_name != "" and player.has_animation(anim_name):
			if player.current_animation != anim_name:
				player.play(anim_name)
			var progress: float = state.get("anim_progress", 0.0)
			player.seek(progress, true)
