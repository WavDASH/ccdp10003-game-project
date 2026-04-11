## DoorReceiver — a door / gate that opens when its triggers are satisfied.
##
## Extends BaseMechanismReceiver. Uses a child StaticBody2D ("DoorBody") for
## blocking collision and a "Visual" Polygon2D for rendering. Both are synced
## to door_size via @tool setters.
##
## When open: collision disabled, visual fades to near-transparent.
## When closed: collision enabled, visual fully opaque.
@tool
class_name DoorReceiver
extends BaseMechanismReceiver

@export_group("Door")
@export var door_size: Vector2 = Vector2(48, 96):
	set(value):
		door_size = value
		entity_size = door_size
		_sync_door_body()

@export_group("Door Colors")
@export var closed_color: Color = Color(0.55, 0.3, 0.1, 1.0):
	set(value):
		closed_color = value
		if not is_open:
			base_color = closed_color

@export var open_color: Color = Color(0.55, 0.3, 0.1, 0.1):
	set(value):
		open_color = value
		if is_open:
			base_color = open_color

var _door_body: StaticBody2D = null
var _door_shape: CollisionShape2D = null   # direct ref — no name lookup


func _init() -> void:
	entity_size = Vector2(48, 96)
	base_color = Color(0.55, 0.3, 0.1, 1.0)


func _runtime_ready() -> void:
	super._runtime_ready()
	add_to_group("doors")
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
	if _door_body == null:
		_door_body = get_node_or_null("DoorBody")
	if _door_body and _door_shape == null:
		_find_door_shape()
	if _door_shape and _door_shape.shape is RectangleShape2D:
		_door_shape.shape.size = door_size


func _on_open_close(now_open: bool) -> void:
	if _door_body:
		_door_body.set_deferred("collision_layer", 0 if now_open else 2)
		if _door_shape:
			_door_shape.set_deferred("disabled", now_open)
	base_color = open_color if now_open else closed_color


func force_close() -> void:
	is_open = false
	if _door_body:
		_door_body.collision_layer = 2
		if _door_shape:
			_door_shape.disabled = false
	base_color = closed_color


## Editor: draw trigger wiring lines + door boundary + label.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	_draw_trigger_wiring()
	var hw := door_size.x / 2.0
	var hh := door_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), door_size)
	draw_rect(rect, Color(0.55, 0.3, 0.1, 0.5), false, 1.5)
	# Show trigger count
	var label := "DOOR"
	if triggers.size() > 0:
		label += " (%d trigger%s)" % [triggers.size(), "s" if triggers.size() > 1 else ""]
	draw_string(ThemeDB.fallback_font, Vector2(-hw + 2, -hh - 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.4, 0.15, 0.7))
