## TerrainBlock — @tool resizable floor/wall/platform with synced collision + visual.
##
## Extends StaticBody2D directly (IS the physics body). Exports block_size
## which drives both the CollisionShape2D and the placeholder Polygon2D.
## Art-replaceable: swap the Visual child for a Sprite2D / NinePatchRect in the
## editor without changing this script.
@tool
class_name TerrainBlock
extends StaticBody2D

## Which point stays fixed when you resize in the Inspector.
enum ResizeAnchor { CENTER, TOP_LEFT, TOP, TOP_RIGHT, RIGHT, BOTTOM_RIGHT, BOTTOM, BOTTOM_LEFT, LEFT }

@export var resize_anchor: ResizeAnchor = ResizeAnchor.CENTER

@export var block_size: Vector2 = Vector2(128, 32):
	set(value):
		var old_size := block_size
		block_size = value
		_adjust_position_for_anchor(old_size, block_size)
		_sync_visuals()

## NOTE on textures: When block_texture is null, block_color fills the polygon.
## When block_texture is set, block_color TINTS the texture. Set to WHITE for
## full-brightness textures.
@export_group("Visuals")
@export var block_color: Color = Color(0.32, 0.32, 0.38, 1.0):
	set(value):
		block_color = value
		_sync_visuals()

@export var block_texture: Texture2D = null:
	set(value):
		block_texture = value
		_sync_visuals()

@export var block_material: Material = null:
	set(value):
		block_material = value
		_sync_visuals()

@export_group("Physics")
@export var one_way: bool = false:
	set(value):
		one_way = value
		_sync_one_way()


## Shifts position so the anchor point stays fixed when size changes.
func _adjust_position_for_anchor(old_size: Vector2, new_size: Vector2) -> void:
	if not Engine.is_editor_hint():
		return
	var delta := new_size - old_size
	if delta == Vector2.ZERO:
		return
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


func _ready() -> void:
	collision_mask = 0
	_ensure_children()
	_sync_visuals()
	_sync_one_way()


## Creates CollisionShape2D + Visual Polygon2D if they don't exist yet.
func _ensure_children() -> void:
	if not get_node_or_null("CollisionShape2D"):
		var cs := CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		cs.shape = RectangleShape2D.new()
		add_child(cs)
		if Engine.is_editor_hint():
			cs.owner = get_tree().edited_scene_root

	if not get_node_or_null("Visual"):
		var vis := Polygon2D.new()
		vis.name = "Visual"
		add_child(vis)
		if Engine.is_editor_hint():
			vis.owner = get_tree().edited_scene_root


func _sync_visuals() -> void:
	# Sync collision shape
	var cs = get_node_or_null("CollisionShape2D")
	if cs and cs.shape is RectangleShape2D:
		cs.shape.size = block_size

	# Sync placeholder visual (Polygon2D only — safe no-op for Sprite2D etc.)
	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		var hw := block_size.x / 2.0
		var hh := block_size.y / 2.0
		visual.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh),
		])
		# UVs map (0,0)→(width,height) so textures tile naturally.
		visual.uv = PackedVector2Array([
			Vector2(0, 0), Vector2(block_size.x, 0),
			Vector2(block_size.x, block_size.y), Vector2(0, block_size.y),
		])
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		visual.color = block_color
		visual.texture = block_texture
		visual.material = block_material


func _sync_one_way() -> void:
	var cs = get_node_or_null("CollisionShape2D")
	if cs:
		cs.one_way_collision = one_way


## Editor validation: warn about missing children.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not get_node_or_null("CollisionShape2D"):
		warnings.append("Missing CollisionShape2D child. Re-instance the scene to fix.")
	if not get_node_or_null("Visual"):
		warnings.append("Missing Visual child node.")
	if block_size.x <= 0 or block_size.y <= 0:
		warnings.append("block_size has a zero or negative dimension.")
	return warnings
