## BasePlaceable — shared foundation for all editor-placed level entities.
##
## Provides @tool support, size-driven placeholder visuals, and art-replaceable
## exports (color, texture, material). Subclasses override _sync_size() for
## collision and _runtime_ready() for group registration / runtime logic.
@tool
class_name BasePlaceable
extends Node2D

## Which point stays fixed when you resize in the Inspector.
## CENTER = default (size grows equally in all directions).
## TOP_LEFT, LEFT, BOTTOM, etc. = that edge/corner stays pinned.
enum ResizeAnchor { CENTER, TOP_LEFT, TOP, TOP_RIGHT, RIGHT, BOTTOM_RIGHT, BOTTOM, BOTTOM_LEFT, LEFT }

@export_group("Layout")
@export var resize_anchor: ResizeAnchor = ResizeAnchor.CENTER

## ── Size (drives collision in subclasses, drives placeholder visual) ──
@export var entity_size: Vector2 = Vector2(64, 64):
	set(value):
		var old_size := entity_size
		entity_size = value
		_adjust_position_for_anchor(old_size, entity_size)
		_sync_size()
		_sync_placeholder_visual()

## ── Visual properties (editable in Inspector, applied to placeholder Polygon2D) ──
## NOTE on textures: When base_texture is null, base_color fills the polygon.
## When base_texture is set, base_color TINTS the texture (Polygon2D behavior).
## Set base_color to WHITE for full-brightness textures.
@export_group("Visuals")
@export var base_color: Color = Color(0.5, 0.5, 0.5, 1.0):
	set(value):
		base_color = value
		_sync_placeholder_visual()

@export var base_texture: Texture2D = null:
	set(value):
		base_texture = value
		_sync_placeholder_visual()

@export var base_material: Material = null:
	set(value):
		base_material = value
		_sync_placeholder_visual()


func _ready() -> void:
	_sync_size()
	_sync_placeholder_visual()
	if not Engine.is_editor_hint():
		_runtime_ready()


## Shifts position so the anchor point stays fixed when size changes.
func _adjust_position_for_anchor(old_size: Vector2, new_size: Vector2) -> void:
	if not Engine.is_editor_hint():
		return  # only relevant during editing
	var delta := new_size - old_size
	if delta == Vector2.ZERO:
		return
	# Anchor offsets: how much to shift position per unit of size change.
	# CENTER = (0, 0), TOP_LEFT = (+0.5, +0.5), BOTTOM_RIGHT = (-0.5, -0.5), etc.
	var offset := Vector2.ZERO
	match resize_anchor:
		ResizeAnchor.CENTER:
			pass
		ResizeAnchor.TOP_LEFT:
			offset = Vector2(0.5, 0.5)
		ResizeAnchor.TOP:
			offset = Vector2(0.0, 0.5)
		ResizeAnchor.TOP_RIGHT:
			offset = Vector2(-0.5, 0.5)
		ResizeAnchor.RIGHT:
			offset = Vector2(-0.5, 0.0)
		ResizeAnchor.BOTTOM_RIGHT:
			offset = Vector2(-0.5, -0.5)
		ResizeAnchor.BOTTOM:
			offset = Vector2(0.0, -0.5)
		ResizeAnchor.BOTTOM_LEFT:
			offset = Vector2(0.5, -0.5)
		ResizeAnchor.LEFT:
			offset = Vector2(0.5, 0.0)
	position += delta * offset


## Override in subclasses for runtime-only initialization (group registration, etc.).
func _runtime_ready() -> void:
	pass


## Override in subclasses that have collision shapes to sync them to entity_size.
func _sync_size() -> void:
	pass


## Applies visual properties to the "Visual" child if it is still a Polygon2D.
## Safe no-op if the user has replaced the Visual with Sprite2D, AnimatedSprite2D, etc.
func _sync_placeholder_visual() -> void:
	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		var hw := entity_size.x / 2.0
		var hh := entity_size.y / 2.0
		visual.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh),
		])
		# UVs map (0,0)→(width,height) so textures tile naturally.
		# A 64×64 texture on a 128×64 entity tiles 2×1.
		visual.uv = PackedVector2Array([
			Vector2(0, 0), Vector2(entity_size.x, 0),
			Vector2(entity_size.x, entity_size.y), Vector2(0, entity_size.y),
		])
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		visual.color = base_color
		visual.texture = base_texture
		visual.material = base_material


## Editor validation: warn about common misconfigurations.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not get_node_or_null("Visual"):
		warnings.append("Missing 'Visual' child node. Add a Polygon2D, Sprite2D, or AnimatedSprite2D.")
	if entity_size.x <= 0 or entity_size.y <= 0:
		warnings.append("entity_size has a zero or negative dimension.")
	return warnings


## Utility: get the world-space bounding rect for this entity.
func get_entity_rect() -> Rect2:
	return Rect2(global_position - entity_size / 2.0, entity_size)
