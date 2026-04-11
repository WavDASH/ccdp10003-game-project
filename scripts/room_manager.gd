## RoomManager — loads/unloads room scenes, detects exits, handles transitions.
##
## Rooms are registered by ID → scene path. The manager checks exit overlap each
## frame and emits room_changed when a transition occurs.
extends Node2D

## Maps room_id → resource path, e.g. { "room_01": "res://scenes/rooms/room_01.tscn" }
@export var room_registry: Dictionary = {}

## Player collision size for exit overlap checks (must match player scene).
var actor_collision_size: Vector2 = Vector2(24, 48)

## Set by main.gd — used to check is_player_interactable() before room exits.
var timeline_manager = null

var current_room_id: String = ""
var current_room_node: Node2D = null
var _exits: Array = []

## External references (set by main.gd).
var active_player: CharacterBody2D = null

signal room_changed(new_room_id: String)
signal player_spawn_found(spawn_pos: Vector2)


func _physics_process(_delta: float) -> void:
	if active_player == null or not is_instance_valid(active_player):
		return
	_check_exits()


## Load the initial room.
func load_room(room_id: String, entry_name: String = "") -> void:
	_unload_current_room()

	if not room_registry.has(room_id):
		push_error("RoomManager: unknown room_id '%s'" % room_id)
		return

	var scene_path: String = room_registry[room_id]
	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("RoomManager: failed to load '%s'" % scene_path)
		return

	current_room_node = scene.instantiate()
	current_room_node.name = "CurrentRoom"
	add_child(current_room_node)
	current_room_id = room_id

	# Discover exits in the new room.
	_exits.clear()
	for node in get_tree().get_nodes_in_group("room_exits"):
		_exits.append(node)

	# Position player at the named entry point (or first spawn).
	var placed := false
	if entry_name != "":
		for node in get_tree().get_nodes_in_group("room_entries"):
			if node.name.to_lower().contains(entry_name.to_lower()):
				_place_player(node.global_position)
				placed = true
				break

	if not placed:
		# Fallback: use PlayerSpawn marker.
		var spawns = get_tree().get_nodes_in_group("player_spawn")
		if spawns.size() > 0:
			_place_player(spawns[0].global_position)
			placed = true

	# Notify spawn position for TimelineManager.
	if placed and active_player:
		player_spawn_found.emit(active_player.global_position)

	room_changed.emit(current_room_id)


func _unload_current_room() -> void:
	_exits.clear()
	if current_room_node and is_instance_valid(current_room_node):
		# Remove immediately so old nodes don't appear in group queries
		# alongside new room's nodes.
		remove_child(current_room_node)
		current_room_node.queue_free()
		current_room_node = null
	current_room_id = ""


func _place_player(pos: Vector2) -> void:
	if active_player and is_instance_valid(active_player):
		active_player.global_position = pos
		active_player.velocity = Vector2.ZERO
		if active_player.has_method("reset"):
			active_player.reset()


func _check_exits() -> void:
	# Reverse-mode player is non-interactive — no room transitions.
	if timeline_manager and not timeline_manager.is_player_interactable():
		return

	for exit in _exits:
		if not is_instance_valid(exit):
			continue
		if exit.is_actor_in_zone(active_player.global_position, actor_collision_size):
			var target_room: String = exit.target_room
			var target_entry: String = exit.target_entry
			if target_room != "" and target_room != current_room_id:
				load_room(target_room, target_entry)
				return


## Returns room bounds for camera limiting. Checks current room root for
## an @export var room_bounds: Rect2. Falls back to 960x640 default.
func get_room_bounds() -> Rect2:
	if current_room_node:
		var bounds = current_room_node.get("room_bounds")
		if bounds is Rect2:
			return bounds
	return Rect2(0, 0, 960, 640)
