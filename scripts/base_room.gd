## BaseRoom — standardized room root node with configurable bounds and editor validation.
##
## Attach this script to the root Node2D of every room scene. Provides:
##   - room_bounds export for camera limits (read by RoomManager.get_room_bounds())
##   - Configuration warnings for missing spawn points, entries, etc.
##   - Editor overlay showing the room bounds rectangle.
@tool
class_name BaseRoom
extends Node2D

@export var room_bounds: Rect2 = Rect2(0, 0, 960, 640)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if room_bounds.size.x <= 0 or room_bounds.size.y <= 0:
		warnings.append("room_bounds has zero or negative size.")

	# Warn if bounds are smaller than the default viewport (960×640).
	if room_bounds.size.x < 960 or room_bounds.size.y < 640:
		warnings.append("room_bounds (%dx%d) is smaller than the viewport (960x640). Camera may show areas outside the room." % [int(room_bounds.size.x), int(room_bounds.size.y)])

	# Check for PlayerSpawn in descendants.
	if not _has_descendant_in_group("player_spawn"):
		warnings.append("No child node in 'player_spawn' group. Add a Marker2D in the player_spawn group.")

	# Check for room entries.
	if not _has_descendant_in_group("room_entries"):
		warnings.append("No entry points (room_entries group). Players arriving from other rooms won't have a spawn position.")

	# Check for at least one RoomExit (unless it's a dead-end test room).
	var has_exit := false
	var stack: Array = get_children().duplicate()
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.get_script() and node.get_script().resource_path.ends_with("room_exit.gd"):
			has_exit = true
			break
		stack.append_array(node.get_children())
	if not has_exit:
		warnings.append("No RoomExit child found. The player cannot leave this room (OK for test rooms).")

	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Draw room bounds outline so the camera limits are visible.
	draw_rect(room_bounds, Color(0.3, 0.7, 1.0, 0.15), false, 1.0)
	draw_string(ThemeDB.fallback_font,
		room_bounds.position + Vector2(4, 14), "room_bounds",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.7, 1.0, 0.3))


func _has_descendant_in_group(group_name: String) -> bool:
	var stack: Array = get_children().duplicate()
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.is_in_group(group_name):
			return true
		stack.append_array(node.get_children())
	return false
