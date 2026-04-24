## BaseRoom — standardized room root node with configurable bounds, editor
## validation, and automatic room-shell geometry sync.
##
## Attach this script to the root Node2D of every room scene. Provides:
##   - room_bounds export for camera limits + room-shell sizing
##   - wall_thickness export for shell wall depth
##   - Per-room camera configuration (mode, zoom, smoothing, bounds)
##   - Automatic sync of room-shell geometry when room_bounds or
##     wall_thickness change in the Inspector
##   - Configuration warnings for missing spawn points, entries, etc.
##   - Editor overlay showing the room bounds rectangle
##
## ── Room-shell auto-sync ──
## If the room has a child node named "RoomShell", changing room_bounds in
## the Inspector automatically repositions and resizes the four walls
## (Floor, Ceiling, WallLeft, WallRight) inside it, plus the Background
## polygon. This is opt-in — rooms without a RoomShell node are unaffected.
##
## Manually placed content (Geometry, Mechanisms, Hazards, etc.) is NEVER
## touched by the shell sync.
@tool
class_name BaseRoom
extends Node2D

enum CameraMode {
	FOLLOW,     ## Camera follows player, clamped to room bounds. Default.
	FIT_ROOM,   ## Camera zooms to show the entire room at once.
	CUSTOM,     ## Camera follows player with custom zoom / bounds.
}

@export var room_bounds: Rect2 = Rect2(0, 0, 960, 640):
	set(value):
		room_bounds = value
		if is_node_ready():
			_sync_room_shell()
			update_configuration_warnings()
		queue_redraw()

@export var wall_thickness: float = 32.0:
	set(value):
		wall_thickness = value
		if is_node_ready():
			_sync_room_shell()
		queue_redraw()

@export_group("Camera")
@export var camera_mode: CameraMode = CameraMode.FOLLOW:
	set(value):
		camera_mode = value
		update_configuration_warnings()
		queue_redraw()

## Zoom override (CUSTOM mode only). Higher = zoomed in, lower = zoomed out.
@export var camera_zoom: Vector2 = Vector2(1, 1)

## Camera movement bounds (CUSTOM mode only). Leave at zero-size to use room_bounds.
@export var camera_bounds: Rect2 = Rect2()

@export var camera_smoothing_enabled: bool = true
@export var camera_smoothing_speed: float = 8.0


const VIEWPORT_SIZE := Vector2(960, 640)


func _ready() -> void:
	if Engine.is_editor_hint():
		_sync_room_shell()


## Returns a Dictionary of resolved camera settings for this room.
## Keys: zoom (Vector2), limits (Rect2), smoothing (bool), smoothing_speed (float).
func get_camera_config() -> Dictionary:
	var config := {
		"smoothing": camera_smoothing_enabled,
		"smoothing_speed": camera_smoothing_speed,
	}

	match camera_mode:
		CameraMode.FIT_ROOM:
			var fit_zoom := minf(
				VIEWPORT_SIZE.x / room_bounds.size.x,
				VIEWPORT_SIZE.y / room_bounds.size.y)
			config["zoom"] = Vector2(fit_zoom, fit_zoom)
			config["limits"] = room_bounds
		CameraMode.CUSTOM:
			config["zoom"] = camera_zoom
			if camera_bounds.size.x > 0 and camera_bounds.size.y > 0:
				config["limits"] = camera_bounds
			else:
				config["limits"] = room_bounds
		_: # FOLLOW
			config["zoom"] = Vector2(1, 1)
			config["limits"] = room_bounds

	return config


# ═════════════════════════════════════════════════════════════════════
#  Room-shell auto-sync
# ═════════════════════════════════════════════════════════════════════

## Repositions and resizes room-shell geometry to match room_bounds.
## Only affects nodes under the "RoomShell" container (opt-in).
func _sync_room_shell() -> void:
	var shell = get_node_or_null("RoomShell")
	if shell == null:
		return   # No RoomShell → no auto-sync (legacy rooms untouched)

	var bounds := room_bounds
	var wt := wall_thickness
	var cx := bounds.position.x + bounds.size.x / 2.0
	var cy := bounds.position.y + bounds.size.y / 2.0

	# ── Shell walls ──
	# Set block_size first (its setter may shift position via resize_anchor),
	# then override position with the correct shell placement.
	_sync_shell_block(shell.get_node_or_null("Floor"),
		Vector2(cx, bounds.end.y - wt / 2.0),
		Vector2(bounds.size.x, wt))
	_sync_shell_block(shell.get_node_or_null("Ceiling"),
		Vector2(cx, bounds.position.y + wt / 2.0),
		Vector2(bounds.size.x, wt))
	_sync_shell_block(shell.get_node_or_null("WallLeft"),
		Vector2(bounds.position.x + wt / 2.0, cy),
		Vector2(wt, bounds.size.y))
	_sync_shell_block(shell.get_node_or_null("WallRight"),
		Vector2(bounds.end.x - wt / 2.0, cy),
		Vector2(wt, bounds.size.y))

	# ── Background polygon ──
	var bg = get_node_or_null("Background")
	if bg is Polygon2D:
		bg.position = Vector2.ZERO
		bg.scale = Vector2.ONE
		bg.polygon = PackedVector2Array([
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y),
		])


func _sync_shell_block(node: Node, pos: Vector2, size: Vector2) -> void:
	if node == null:
		return
	# Set size first (triggers TerrainBlock._sync_visuals), then position.
	if "block_size" in node:
		node.block_size = size
	node.position = pos


# ═════════════════════════════════════════════════════════════════════
#  Editor helpers
# ═════════════════════════════════════════════════════════════════════

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

	# Check for RoomShell.
	if not get_node_or_null("RoomShell"):
		warnings.append("No RoomShell child. Room-shell auto-sync is disabled. Add a RoomShell node with Floor/Ceiling/WallLeft/WallRight children for automatic sizing.")

	# Camera warnings.
	if camera_mode == CameraMode.CUSTOM and camera_zoom.x <= 0:
		warnings.append("camera_zoom has a zero or negative component. Camera will not render correctly.")
	if camera_mode == CameraMode.FIT_ROOM and (room_bounds.size.x < 960 or room_bounds.size.y < 640):
		warnings.append("FIT_ROOM on a room smaller than the viewport will zoom in, not out. Use FOLLOW instead.")

	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Draw room bounds outline so the camera limits are visible.
	draw_rect(room_bounds, Color(0.3, 0.7, 1.0, 0.15), false, 1.0)
	var label := "room_bounds %dx%d" % [int(room_bounds.size.x), int(room_bounds.size.y)]
	if wall_thickness != 32.0:
		label += "  wall=%d" % int(wall_thickness)
	var mode_names := ["FOLLOW", "FIT_ROOM", "CUSTOM"]
	label += "  cam=%s" % mode_names[camera_mode]
	if camera_mode == CameraMode.FIT_ROOM:
		var fit_zoom := minf(
			VIEWPORT_SIZE.x / room_bounds.size.x,
			VIEWPORT_SIZE.y / room_bounds.size.y)
		label += " (%.2fx)" % fit_zoom
	elif camera_mode == CameraMode.CUSTOM:
		label += " (%.2fx)" % camera_zoom.x
	draw_string(ThemeDB.fallback_font,
		room_bounds.position + Vector2(4, 14), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.7, 1.0, 0.3))
	# Draw camera bounds if custom and different from room bounds.
	if camera_mode == CameraMode.CUSTOM and camera_bounds.size.x > 0 and camera_bounds.size.y > 0:
		draw_rect(camera_bounds, Color(1.0, 0.8, 0.2, 0.25), false, 1.0)
		draw_string(ThemeDB.fallback_font,
			camera_bounds.position + Vector2(4, -4), "camera_bounds",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.8, 0.2, 0.3))


func _has_descendant_in_group(group_name: String) -> bool:
	var stack: Array = get_children().duplicate()
	while stack.size() > 0:
		var node = stack.pop_back()
		if node.is_in_group(group_name):
			return true
		stack.append_array(node.get_children())
	return false
