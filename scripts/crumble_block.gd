## CrumbleBlock — a platform that crumbles after the player stands on it.
##
## Extends TerrainBlock. When an actor (player or echo) stands on top,
## a crumble timer starts. After crumble_delay_ticks, the collision disables
## and the visual fades — the block is "broken." It respawns after
## respawn_delay_ticks, or on room restart (fresh scene instance).
##
## Detection uses a thin rect above the block surface (not full overlap).
@tool
class_name CrumbleBlock
extends TerrainBlock

@export_group("Crumble")
## Ticks after an actor steps on before the block breaks.
@export var crumble_delay_ticks: int = 30

## Ticks after breaking before the block reappears. -1 = never respawn.
@export var respawn_delay_ticks: int = 180

@export_group("Crumble Visuals")
@export var crumble_color: Color = Color(0.5, 0.35, 0.2, 1.0):
	set(value):
		crumble_color = value
		if not _is_broken:
			block_color = crumble_color

@export var warning_color: Color = Color(0.8, 0.4, 0.15, 1.0)

## Internal state.
var _crumble_counter: int = -1   # -1 = idle, >=0 = counting down
var _respawn_counter: int = -1   # -1 = idle, >=0 = counting to respawn
var _is_broken: bool = false
var _timeline: Node = null


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group("crumble_blocks")
		block_color = crumble_color
		_timeline = _find_timeline()


func _find_timeline() -> Node:
	var nodes = get_tree().get_nodes_in_group("timeline_manager")
	if nodes.size() > 0:
		return nodes[0]
	return null


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _is_broken:
		_process_respawn()
		return

	if _crumble_counter >= 0:
		_crumble_counter -= 1
		# Warning flash: alternate between crumble_color and warning_color.
		if _crumble_counter >= 0:
			if _crumble_counter % 6 < 3:
				_set_visual_color(warning_color)
			else:
				_set_visual_color(crumble_color)
		if _crumble_counter < 0:
			_break()
		return

	# Check if any actor is standing on top.
	if _is_actor_on_top():
		_crumble_counter = crumble_delay_ticks


func _process_respawn() -> void:
	if respawn_delay_ticks < 0:
		return  # never respawn
	_respawn_counter -= 1
	if _respawn_counter < 0:
		_repair()


func _is_actor_on_top() -> bool:
	if _timeline == null:
		return false

	# Thin detection rect sitting on top of the block surface.
	var detect_rect := Rect2(
		global_position.x - block_size.x / 2.0,
		global_position.y - block_size.y / 2.0 - 8,
		block_size.x,
		8
	)
	var actor_size: Vector2 = _timeline.actor_collision_size

	# Check player (only if interactable — reverse player doesn't trigger crumble).
	if _timeline.is_player_interactable():
		var player = _timeline.active_player
		if player and is_instance_valid(player):
			var pr := Rect2(player.global_position - actor_size / 2.0, actor_size)
			if detect_rect.intersects(pr):
				return true

	# Check echoes.
	for echo in _timeline.echo_instances:
		if is_instance_valid(echo) and echo.visible and not echo.branch.collapsed:
			var er := Rect2(echo.global_position - actor_size / 2.0, actor_size)
			if detect_rect.intersects(er):
				return true

	return false


func _break() -> void:
	_is_broken = true
	_crumble_counter = -1
	_respawn_counter = respawn_delay_ticks

	# Disable collision.
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.set_deferred("disabled", true)
	collision_layer = 0

	# Fade visual.
	_set_visual_color(Color(crumble_color.r, crumble_color.g, crumble_color.b, 0.15))


func _repair() -> void:
	_is_broken = false
	_respawn_counter = -1

	# Re-enable collision.
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.set_deferred("disabled", false)
	collision_layer = 1  # World layer

	# Restore visual.
	_set_visual_color(crumble_color)


func _set_visual_color(c: Color) -> void:
	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		visual.color = c
