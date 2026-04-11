## BaseMechanismTrigger — base class for activatable trigger zones.
##
## Extends BasePlaceable with trigger-specific logic: activation state,
## actor overlap detection, and the set_pressed() API used by TimelineManager.
## Subclass this for switches, timed triggers, toggle triggers, etc.
@tool
class_name BaseMechanismTrigger
extends BasePlaceable

@export_group("Trigger Zone")
## Size of the rectangular trigger zone (world units).
## This is the invisible detection area — often larger than the visual.
## Does NOT drive entity_size (subclasses control their own visual size).
## Shown as a dashed outline in the editor when it differs from entity_size.
@export var trigger_size: Vector2 = Vector2(80, 24):
	set(value):
		trigger_size = value
		queue_redraw()

## Current activation state.
var activated: bool = false

signal state_changed(is_activated: bool)


## Returns true if an actor rect overlaps this trigger zone.
func is_actor_in_zone(actor_pos: Vector2, actor_size: Vector2) -> bool:
	var my_rect := Rect2(global_position - trigger_size / 2.0, trigger_size)
	var actor_rect := Rect2(actor_pos - actor_size / 2.0, actor_size)
	return my_rect.intersects(actor_rect)


## Called by TimelineManager each frame with the computed activation state.
func set_pressed(value: bool) -> void:
	if activated != value:
		activated = value
		_on_state_change()
		state_changed.emit(activated)


## Override in subclass for visual / audio feedback.
func _on_state_change() -> void:
	pass


## Editor-only: draw trigger zone outline when it differs from the visual.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if trigger_size == entity_size:
		return
	var hw := trigger_size.x / 2.0
	var hh := trigger_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), trigger_size)
	# Dashed outline — cyan, semi-transparent
	var color := Color(0.0, 0.9, 0.9, 0.45)
	# Draw rect edges as individual lines for dash effect
	var p_tl := rect.position
	var p_tr := Vector2(rect.end.x, rect.position.y)
	var p_br := rect.end
	var p_bl := Vector2(rect.position.x, rect.end.y)
	_draw_dashed_line(p_tl, p_tr, color)
	_draw_dashed_line(p_tr, p_br, color)
	_draw_dashed_line(p_br, p_bl, color)
	_draw_dashed_line(p_bl, p_tl, color)
	# Label
	draw_string(ThemeDB.fallback_font, p_tl + Vector2(2, -2), "trigger zone",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.0, 0.9, 0.9, 0.5))


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color,
		dash_length: float = 4.0, gap_length: float = 3.0) -> void:
	var dir := (to - from)
	var length := dir.length()
	if length < 0.01:
		return
	dir = dir / length
	var pos := 0.0
	while pos < length:
		var seg_end := minf(pos + dash_length, length)
		draw_line(from + dir * pos, from + dir * seg_end, color, 1.0)
		pos = seg_end + gap_length
