## GenerateTestTextures — @tool script to create test textures for tiling validation.
##
## Attach this to any Node in the editor, then call generate() from the
## inspector's "Tool" menu or run it once. It creates small .png files in
## res://textures/ that can be assigned to block_texture / base_texture exports.
##
## After generating, you can remove this script from the node.
@tool
extends Node

const GRID_SIZE: int = 16  # 16x16 pixel texture


## Call this from the editor to generate textures.
func _ready() -> void:
	if Engine.is_editor_hint():
		generate()


func generate() -> void:
	_generate_grid("res://textures/test_grid.png",
		Color(0.45, 0.45, 0.55, 1.0), Color(0.35, 0.35, 0.42, 1.0))
	_generate_grid("res://textures/test_checker.png",
		Color(0.5, 0.5, 0.6, 1.0), Color(0.3, 0.3, 0.35, 1.0))
	print("GenerateTestTextures: textures saved to res://textures/")


func _generate_grid(path: String, color_a: Color, color_b: Color) -> void:
	var img := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			# Grid pattern: 1px border lines
			if x == 0 or y == 0:
				img.set_pixel(x, y, color_b)
			else:
				img.set_pixel(x, y, color_a)
	img.save_png(path)
