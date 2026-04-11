## BaseHazard — base class for all hazard zones.
##
## Extends BasePlaceable with hazard-specific defaults and the get_hazard_rect()
## API that TimelineManager uses for kill detection.
@tool
class_name BaseHazard
extends BasePlaceable

func _init() -> void:
	entity_size = Vector2(92, 50)
	base_color = Color(0.85, 0.1, 0.1, 1.0)


func _runtime_ready() -> void:
	add_to_group("hazards")


## Returns the world-space hazard rect (alias for get_entity_rect).
func get_hazard_rect() -> Rect2:
	return get_entity_rect()


## Editor: draw a labeled outline so hazard zones stand out in the scene.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var hw := entity_size.x / 2.0
	var hh := entity_size.y / 2.0
	var rect := Rect2(Vector2(-hw, -hh), entity_size)
	# Red dashed outline
	var color := Color(1.0, 0.2, 0.2, 0.6)
	draw_rect(rect, color, false, 1.5)
	# Diagonal hatch lines for hazard pattern
	var step := 12.0
	var x := rect.position.x
	while x < rect.end.x:
		var x0 := x
		var x1 := x + step
		draw_line(Vector2(clampf(x0, rect.position.x, rect.end.x), rect.end.y),
			Vector2(clampf(x1, rect.position.x, rect.end.x), rect.position.y),
			Color(1.0, 0.2, 0.2, 0.25), 1.0)
		x += step
	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-hw + 2, -hh - 4), "HAZARD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.3, 0.3, 0.7))
