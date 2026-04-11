## MovingPlatformReceiver — a platform that moves between two points when triggered.
##
## Uses AnimatableBody2D so Godot's CharacterBody2D.move_and_slide() correctly
## carries passengers (the player) along with the platform.
##
## When open (triggered): moves toward point_b.
## When closed (untriggered): moves toward point_a (start position).
## Movement is relative to the node's placed position (point_a = Vector2.ZERO).
##
## Time-reversal: movement is deterministic from trigger state, so echoes on
## the platform naturally ride it if their recorded position matches. The
## platform's position is not recorded — it's re-derived from trigger state.
@tool
class_name MovingPlatformReceiver
extends AnimatableBody2D

## Size of the platform collision + visual.
@export var platform_size: Vector2 = Vector2(96, 16):
	set(value):
		platform_size = value
		_sync_visuals()

## End position, relative to the node's placed position.
## Example: Vector2(0, -200) means the platform moves 200px upward.
@export var point_b: Vector2 = Vector2(0, -200):
	set(value):
		point_b = value
		queue_redraw()

## Movement speed in pixels per second.
@export var move_speed: float = 120.0

@export_group("Visuals")
@export var platform_color: Color = Color(0.3, 0.55, 0.3, 1.0):
	set(value):
		platform_color = value
		_sync_visuals()

@export var platform_texture: Texture2D = null:
	set(value):
		platform_texture = value
		_sync_visuals()

@export var platform_material: Material = null:
	set(value):
		platform_material = value
		_sync_visuals()

@export_group("Triggers")
## NodePaths to trigger nodes. If empty, the platform is schedule/manual only.
@export var triggers: Array[NodePath] = []
## If true, ALL triggers must be active. If false, ANY suffices.
@export var require_all: bool = false

## Resolved trigger references.
var trigger_nodes: Array = []

## Current open/closed state (true = moving toward point_b).
var is_open: bool = false

## Interpolation progress: 0.0 = at start (point_a), 1.0 = at point_b.
var _progress: float = 0.0

## The node's initial position (set in _runtime_ready, serves as point_a).
var _origin: Vector2 = Vector2.ZERO

var _shape: CollisionShape2D = null


func _ready() -> void:
	collision_layer = 1   # World layer — player stands on it
	collision_mask = 0
	sync_to_physics = false

	_shape = get_node_or_null("CollisionShape2D")
	_sync_visuals()

	if not Engine.is_editor_hint():
		_origin = position
		call_deferred("_resolve_triggers")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_evaluate_triggers()

	# Move toward target based on open/closed state.
	var target := 1.0 if is_open else 0.0
	if _progress != target:
		var dist := point_b.length()
		if dist > 0.0:
			var step := (move_speed * delta) / dist
			_progress = move_toward(_progress, target, step)
			position = _origin + point_b * _progress


func _evaluate_triggers() -> void:
	if trigger_nodes.is_empty():
		return

	var new_state: bool
	if require_all:
		new_state = true
		for t in trigger_nodes:
			if not t.activated:
				new_state = false
				break
	else:
		new_state = false
		for t in trigger_nodes:
			if t.activated:
				new_state = true
				break

	is_open = new_state


func _resolve_triggers() -> void:
	if trigger_nodes.size() > 0:
		return
	for path in triggers:
		var node = get_node_or_null(path)
		if node:
			trigger_nodes.append(node)


func _sync_visuals() -> void:
	if _shape == null:
		_shape = get_node_or_null("CollisionShape2D")
	if _shape and _shape.shape is RectangleShape2D:
		_shape.shape.size = platform_size

	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		var hw := platform_size.x / 2.0
		var hh := platform_size.y / 2.0
		visual.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh),
		])
		visual.uv = PackedVector2Array([
			Vector2(0, 0), Vector2(platform_size.x, 0),
			Vector2(platform_size.x, platform_size.y), Vector2(0, platform_size.y),
		])
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		visual.color = platform_color
		visual.texture = platform_texture
		visual.material = platform_material


## Editor validation: warn about common misconfigurations.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if point_b == Vector2.ZERO:
		warnings.append("point_b is (0, 0). The platform will not move.")
	if triggers.is_empty():
		warnings.append("No triggers assigned. The platform will not move.")
	for i in triggers.size():
		var path: NodePath = triggers[i]
		if path.is_empty():
			warnings.append("Trigger #%d is an empty path." % i)
		elif get_node_or_null(path) == null:
			warnings.append("Trigger #%d path '%s' does not resolve to a node." % [i, str(path)])
	if not get_node_or_null("CollisionShape2D"):
		warnings.append("Missing CollisionShape2D child. Add one for the platform to have collision.")
	if not get_node_or_null("Visual"):
		warnings.append("Missing Visual (Polygon2D) child. The platform will be invisible.")
	return warnings


## Editor: draw trigger wiring + travel path.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Draw trigger wiring lines (yellow)
	for path in triggers:
		var node = get_node_or_null(path)
		if node and node is Node2D:
			var target_pos := to_local(node.global_position)
			draw_line(Vector2.ZERO, target_pos, Color(1.0, 0.8, 0.2, 0.3), 1.5)
			var d := 4.0
			draw_polygon(
				PackedVector2Array([
					target_pos + Vector2(0, -d), target_pos + Vector2(d, 0),
					target_pos + Vector2(0, d), target_pos + Vector2(-d, 0),
				]),
				PackedColorArray([Color(1.0, 0.8, 0.2, 0.4), Color(1.0, 0.8, 0.2, 0.4),
					Color(1.0, 0.8, 0.2, 0.4), Color(1.0, 0.8, 0.2, 0.4)])
			)
	# Draw travel path line
	draw_line(Vector2.ZERO, point_b, Color(0.3, 0.8, 0.3, 0.4), 2.0)
	# Draw point_b marker
	draw_rect(Rect2(point_b - platform_size / 2.0, platform_size),
		Color(0.3, 0.55, 0.3, 0.2), true)
	draw_string(ThemeDB.fallback_font, point_b + Vector2(0, -platform_size.y / 2.0 - 4),
		"point_b", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.8, 0.3, 0.6))
