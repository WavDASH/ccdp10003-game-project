## Hazard — concrete static hazard zone (spike pit, lava, etc.).
##
## Extends BaseHazard. Place as an instanced scene in the editor.
## Size and color are editable via @tool setters — collision rect and
## placeholder visual stay in sync automatically.
@tool
class_name Hazard
extends BaseHazard

@export_group("Hazard")
@export var hazard_size: Vector2 = Vector2(92, 50):
	set(value):
		hazard_size = value
		entity_size = hazard_size


func _init() -> void:
	entity_size = Vector2(92, 50)
	base_color = Color(0.85, 0.1, 0.1, 1.0)
