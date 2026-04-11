## PlayerSpriteFrames — programmatic SpriteFrames for player/echo placeholder animations.
##
## Creates simple colored-rectangle frames for 4 animations:
##   idle (2 frames, subtle breathing), run (4 frames, width variation),
##   jump (1 frame, tall/narrow), fall (1 frame, wide/short).
##
## No PNG files needed. Uses Image.create() + ImageTexture.
## Shared between ActivePlayer and EchoPlayer.
class_name PlayerSpriteFrames
extends RefCounted

## Base size matching the player's collision shape.
const BASE_W: int = 24
const BASE_H: int = 48


static func create() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")

	# ── idle: subtle size oscillation ──
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 3.0)
	sf.set_animation_loop("idle", true)
	sf.add_frame("idle", _rect_tex(BASE_W, BASE_H, Color.WHITE))
	sf.add_frame("idle", _rect_tex(BASE_W - 2, BASE_H - 2, Color(0.92, 0.92, 0.98)))

	# ── run: width variation to simulate leg movement ──
	sf.add_animation("run")
	sf.set_animation_speed("run", 10.0)
	sf.set_animation_loop("run", true)
	sf.add_frame("run", _rect_tex(BASE_W, BASE_H, Color.WHITE))
	sf.add_frame("run", _rect_tex(BASE_W - 2, BASE_H - 2, Color(0.95, 0.95, 1.0)))
	sf.add_frame("run", _rect_tex(BASE_W, BASE_H - 4, Color.WHITE))
	sf.add_frame("run", _rect_tex(BASE_W - 2, BASE_H - 2, Color(0.95, 0.95, 1.0)))

	# ── jump: taller, narrower ──
	sf.add_animation("jump")
	sf.set_animation_speed("jump", 1.0)
	sf.set_animation_loop("jump", false)
	sf.add_frame("jump", _rect_tex(BASE_W - 4, BASE_H + 4, Color(0.9, 0.95, 1.0)))

	# ── fall: wider, shorter ──
	sf.add_animation("fall")
	sf.set_animation_speed("fall", 1.0)
	sf.set_animation_loop("fall", false)
	sf.add_frame("fall", _rect_tex(BASE_W + 2, BASE_H - 4, Color(0.95, 0.9, 1.0)))

	# ── dash: wide, short, bright — conveys speed ──
	sf.add_animation("dash")
	sf.set_animation_speed("dash", 1.0)
	sf.set_animation_loop("dash", false)
	sf.add_frame("dash", _rect_tex(BASE_W + 8, BASE_H - 10, Color(1.0, 1.0, 1.0)))

	# ── wall_slide: narrow, subtle blue tint — pressed against wall ──
	sf.add_animation("wall_slide")
	sf.set_animation_speed("wall_slide", 1.0)
	sf.set_animation_loop("wall_slide", false)
	sf.add_frame("wall_slide", _rect_tex(BASE_W - 4, BASE_H, Color(0.85, 0.9, 1.0)))

	return sf


## Creates a centered rectangle texture of the given size and color.
## The image is padded to a consistent size so the sprite doesn't jitter.
static func _rect_tex(w: int, h: int, color: Color) -> ImageTexture:
	# Use a consistent canvas size so all frames align.
	var canvas_w: int = BASE_W + 4  # 28
	var canvas_h: int = BASE_H + 4  # 52
	var img := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # transparent background

	# Center the colored rectangle on the canvas.
	var x0: int = (canvas_w - w) / 2
	var y0: int = (canvas_h - h) / 2
	var rect := Rect2i(x0, y0, w, h)
	img.fill_rect(rect, color)

	return ImageTexture.create_from_image(img)
