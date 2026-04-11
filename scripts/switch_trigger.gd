## SwitchTrigger — a pressure switch that activates when any actor overlaps.
##
## Visual: a thin coloured rectangle that brightens when pressed.
## Place as an instanced scene in the editor; the Visual polygon is synced
## to visual_size via @tool setters.
@tool
class_name SwitchTrigger
extends BaseMechanismTrigger

@export_group("Switch")
@export var visual_size: Vector2 = Vector2(64, 12):
	set(value):
		visual_size = value
		entity_size = visual_size

@export_group("Switch Colors")
@export var unpressed_color: Color = Color(0.6, 0.55, 0.0, 1.0):
	set(value):
		unpressed_color = value
		if not activated:
			base_color = unpressed_color

@export var pressed_color: Color = Color(1.0, 1.0, 0.2, 1.0):
	set(value):
		pressed_color = value
		if activated:
			base_color = pressed_color


func _init() -> void:
	entity_size = Vector2(64, 12)
	base_color = Color(0.6, 0.55, 0.0, 1.0)


func _runtime_ready() -> void:
	add_to_group("switches")


func _on_state_change() -> void:
	base_color = pressed_color if activated else unpressed_color
