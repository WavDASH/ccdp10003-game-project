## TimeScheduledDoor — a door that opens/closes on a room_tick schedule.
##
## Combines TimeScheduledReceiver's schedule logic with DoorReceiver-style
## collision toggling and visual feedback.
@tool
class_name TimeScheduledDoor
extends TimeScheduledReceiver

@export_group("Door")
@export var door_size: Vector2 = Vector2(48, 96):
	set(value):
		door_size = value
		entity_size = door_size
		_sync_door_body()

@export_group("Door Colors")
@export var closed_color: Color = Color(0.45, 0.15, 0.5, 1.0):
	set(value):
		closed_color = value
		if not is_open:
			base_color = closed_color

@export var open_color: Color = Color(0.45, 0.15, 0.5, 0.1):
	set(value):
		open_color = value
		if is_open:
			base_color = open_color

var _door_body: StaticBody2D = null
var _door_shape: CollisionShape2D = null   # direct ref — no name lookup
var _shape_made_unique: bool = false


func _init() -> void:
	entity_size = Vector2(48, 96)
	base_color = Color(0.45, 0.15, 0.5, 1.0)


func _runtime_ready() -> void:
	super._runtime_ready()
	# NOTE: deliberately NOT in "doors" group — scheduled doors are driven
	# by evaluate_schedule() via "scheduled_receivers", not evaluate_triggers().
	_door_body = get_node_or_null("DoorBody")
	if _door_body == null:
		_create_door_body()
	else:
		_find_door_shape()
		_sync_door_body()


func _ready() -> void:
	super._ready()
	_door_body = get_node_or_null("DoorBody")
	if _door_body:
		_find_door_shape()
		_sync_door_body()


func _create_door_body() -> void:
	_door_body = StaticBody2D.new()
	_door_body.name = "DoorBody"
	_door_body.collision_layer = 2   # Door layer
	_door_body.collision_mask = 0
	_door_shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = door_size
	_door_shape.shape = rs
	_door_body.add_child(_door_shape)
	add_child(_door_body)


func _find_door_shape() -> void:
	if _door_body == null:
		return
	for child in _door_body.get_children():
		if child is CollisionShape2D:
			_door_shape = child
			return


func _sync_door_body() -> void:
	# Ensure refs are populated (setter may fire before _ready).
	if _door_body == null:
		_door_body = get_node_or_null("DoorBody")
	if _door_body and _door_shape == null:
		_find_door_shape()
	if _door_shape and _door_shape.shape is RectangleShape2D:
		if not _shape_made_unique:
			_door_shape.shape = _door_shape.shape.duplicate()
			_shape_made_unique = true
		_door_shape.shape.size = door_size


func _on_open_close(now_open: bool) -> void:
	if _door_body:
		# Primary: toggle collision_layer so nothing can collide with the body.
		_door_body.set_deferred("collision_layer", 0 if now_open else 2)
		# Backup: also disable the shape itself.
		if _door_shape:
			_door_shape.set_deferred("disabled", now_open)
	base_color = open_color if now_open else closed_color


## Editor: draw door boundary + schedule info label.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := door_size.x / 2.0
	var hh := door_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), door_size)
	draw_rect(rect, Color(0.45, 0.15, 0.5, 0.5), false, 1.5)
	# Show schedule summary
	var label := "SCHED DOOR"
	if schedule.size() > 0:
		var w: Vector2i = schedule[0]
		label += " [%d-%d]" % [w.x, w.y]
		if schedule.size() > 1:
			label += " +%d" % (schedule.size() - 1)
	if loop_period > 0:
		label += " loop=%d" % loop_period
	draw_string(ThemeDB.fallback_font, Vector2(-hw + 2, -hh - 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.6, 0.25, 0.7, 0.7))
