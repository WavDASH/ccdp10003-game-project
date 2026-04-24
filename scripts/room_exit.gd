## RoomExit — trigger zone at a room edge that transitions to another room.
##
## Place at room edges. RoomManager checks player overlap each frame.
## entity_size defines the invisible detection rectangle.
@tool
class_name RoomExit
extends BasePlaceable

@export_group("Target")
@export var target_room: String = "":
	set(value):
		target_room = value
		queue_redraw()
		update_configuration_warnings()

@export var target_entry: String = "left"
@export var exit_direction: String = "right":   ## which edge: left, right, up, down
	set(value):
		exit_direction = value
		update_configuration_warnings()


func _init() -> void:
	entity_size = Vector2(16, 100)
	base_color = Color(0.2, 0.8, 0.2, 0.15)


func _runtime_ready() -> void:
	add_to_group("room_exits")


## Check if an actor overlaps this exit zone.
func is_actor_in_zone(actor_pos: Vector2, actor_size: Vector2) -> bool:
	var my_rect := Rect2(global_position - entity_size / 2.0, entity_size)
	var actor_rect := Rect2(actor_pos - actor_size / 2.0, actor_size)
	return my_rect.intersects(actor_rect)


## Editor validation: warn about misconfigured exits.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if target_room == "":
		warnings.append("target_room is empty. This exit will not trigger a room transition.")
	if exit_direction not in ["left", "right", "up", "down"]:
		warnings.append("exit_direction '%s' is not valid. Use left, right, up, or down." % exit_direction)
	return warnings


## Editor-only: draw zone boundary + target label so the exit is clearly visible.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := entity_size.x / 2.0
	var hh := entity_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), entity_size)
	# Green dashed outline for the detection zone
	var color := Color(0.2, 0.9, 0.2, 0.5)
	draw_rect(rect, color, false, 1.5)
	# Arrow indicating exit direction
	var arrow_color := Color(0.2, 0.9, 0.2, 0.4)
	match exit_direction:
		"right":
			draw_line(Vector2(hw - 6, 0), Vector2(hw + 4, 0), arrow_color, 2.0)
			draw_line(Vector2(hw + 4, 0), Vector2(hw, -4), arrow_color, 1.5)
			draw_line(Vector2(hw + 4, 0), Vector2(hw, 4), arrow_color, 1.5)
		"left":
			draw_line(Vector2(-hw + 6, 0), Vector2(-hw - 4, 0), arrow_color, 2.0)
			draw_line(Vector2(-hw - 4, 0), Vector2(-hw, -4), arrow_color, 1.5)
			draw_line(Vector2(-hw - 4, 0), Vector2(-hw, 4), arrow_color, 1.5)
		"up":
			draw_line(Vector2(0, -hh + 6), Vector2(0, -hh - 4), arrow_color, 2.0)
		"down":
			draw_line(Vector2(0, hh - 6), Vector2(0, hh + 4), arrow_color, 2.0)
	# Target room label
	if target_room != "":
		draw_string(ThemeDB.fallback_font,
			Vector2(-hw, -hh - 4), "EXIT -> " + target_room,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.2, 0.9, 0.2, 0.7))
