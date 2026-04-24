## GoalZone — an editor-placeable goal area.
##
## The active player reaching this zone completes the level.
## Extends BasePlaceable with @tool for WYSIWYG editing.
@tool
class_name GoalZone
extends BasePlaceable

@export_group("Goal")
@export var zone_size: Vector2 = Vector2(100, 28):
	set(value):
		zone_size = value
		entity_size = zone_size


func _init() -> void:
	entity_size = Vector2(100, 28)
	base_color = Color(1.0, 0.92, 0.2, 0.2)


func _runtime_ready() -> void:
	add_to_group("goals")
	_setup_pulse_animation()


## Returns the world-space goal rect (alias for get_entity_rect).
func get_goal_rect() -> Rect2:
	return get_entity_rect()


## Creates an AnimationPlayer with a looping pulse + a TimeAwareAnimator
## to validate the AnimationPlayer code path of the animation system.
func _setup_pulse_animation() -> void:
	var visual = get_node_or_null("Visual")
	if visual == null:
		return

	# Create AnimationPlayer with a pulse animation.
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)

	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_LINEAR

	# Animate Visual's modulate alpha: 0.15 → 0.5 → 0.15
	var track_idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, "Visual:modulate:a")
	anim.track_insert_key(track_idx, 0.0, 0.15)
	anim.track_insert_key(track_idx, 0.5, 0.5)
	anim.track_insert_key(track_idx, 1.0, 0.15)

	var lib: AnimationLibrary
	if anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)
	lib.add_animation("pulse", anim)

	anim_player.play("pulse")

	# Add TimeAwareAnimator so the pulse reverses with time direction.
	var animator_script = load("res://scripts/time_aware_animator.gd")
	var animator := Node.new()
	animator.name = "TimeAwareAnimator"
	animator.set_script(animator_script)
	add_child(animator)


## Editor: draw a labeled outline so the goal zone is clearly marked.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := entity_size.x / 2.0
	var hh := entity_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), entity_size)
	# Gold dashed outline
	var color := Color(1.0, 0.92, 0.2, 0.6)
	draw_rect(rect, color, false, 1.5)
	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-hw + 2, -hh - 4), "GOAL",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.92, 0.2, 0.7))
