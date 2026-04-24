## HUD — gameplay info, timeline bar, reversal status, and debug overlay.
extends Control

const DIR_COLOR_FWD := Color(1.0, 0.45, 0.35)
const DIR_COLOR_REV := Color(0.45, 0.6, 1.0)
const STATUS_READY  := Color(0.4, 0.9, 0.4)
const STATUS_WARN   := Color(1.0, 0.9, 0.3)
const STATUS_LOCKED := Color(1.0, 0.35, 0.3)

var timeline_manager = null:
	set(value):
		timeline_manager = value
		if _timeline_bar:
			_timeline_bar.timeline_manager = value

var _debug_visible: bool = false

# UI nodes
var _timeline_bar = null
var _dir_label: Label = null
var _status_label: Label = null
var _legend_label: Label = null
var _controls_label: Label = null
var _debug_label: Label = null
var _complete_label: Label = null
var _complete_subtitle: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Timeline bar (top) ──
	_timeline_bar = Control.new()
	_timeline_bar.name = "TimelineBar"
	_timeline_bar.set_script(load("res://scripts/timeline_bar.gd"))
	_timeline_bar.position = Vector2(40, 6)
	_timeline_bar.size = Vector2(880, 26)
	_timeline_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timeline_bar)
	if timeline_manager:
		_timeline_bar.timeline_manager = timeline_manager

	# ── Direction label (below bar, left) ──
	_dir_label = Label.new()
	_dir_label.position = Vector2(42, 36)
	_dir_label.add_theme_font_size_override("font_size", 15)
	_dir_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_dir_label.add_theme_constant_override("shadow_offset_x", 1)
	_dir_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_dir_label)

	# ── Reversal status label (below bar, right area) ──
	_status_label = Label.new()
	_status_label.position = Vector2(440, 36)
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_status_label)

	# ── Color legend (bottom-left) ──
	_legend_label = Label.new()
	_legend_label.position = Vector2(10, 596)
	_legend_label.add_theme_font_size_override("font_size", 11)
	_legend_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_legend_label.text = "WHITE = You   RED = Echo (fwd playback)   BLUE = Echo (rev playback)"
	add_child(_legend_label)

	# ── Controls hint ──
	_controls_label = Label.new()
	_controls_label.position = Vector2(10, 616)
	_controls_label.add_theme_font_size_override("font_size", 11)
	_controls_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	_controls_label.text = "A/D: Move  |  Space/I: Jump  |  Shift/L: Dash  |  R/J: Reverse  |  Backspace: Restart  |  F3: Debug"
	add_child(_controls_label)

	# ── Debug panel (F3 toggle) ──
	_debug_label = Label.new()
	_debug_label.position = Vector2(10, 60)
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_label.visible = false
	add_child(_debug_label)

	# ── Level complete banner ──
	_complete_label = Label.new()
	_complete_label.add_theme_font_size_override("font_size", 36)
	_complete_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	_complete_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_complete_label.add_theme_constant_override("shadow_offset_x", 2)
	_complete_label.add_theme_constant_override("shadow_offset_y", 2)
	_complete_label.text = "LEVEL COMPLETE!"
	_complete_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_complete_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_complete_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_complete_label.visible = false
	add_child(_complete_label)

	# ── Level complete subtitle ──
	_complete_subtitle = Label.new()
	_complete_subtitle.add_theme_font_size_override("font_size", 16)
	_complete_subtitle.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	_complete_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_complete_subtitle.add_theme_constant_override("shadow_offset_x", 2)
	_complete_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_complete_subtitle.text = "You reached the goal.\nPress Backspace to restart."
	_complete_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_complete_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_complete_subtitle.offset_top = 36
	_complete_subtitle.offset_bottom = 90
	_complete_subtitle.offset_left = -200
	_complete_subtitle.offset_right = 200
	_complete_subtitle.visible = false
	add_child(_complete_subtitle)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_toggle"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible

	if timeline_manager == null:
		return

	var info: Dictionary = timeline_manager.get_debug_info()
	var dir: int = info["direction"]

	# ── Direction + tick ──
	if dir == 1:
		_dir_label.text = ">> FORWARD   Tick: %d" % info["tick"]
		_dir_label.add_theme_color_override("font_color", DIR_COLOR_FWD)
	else:
		_dir_label.text = "<< REVERSE (non-interactive)   Tick: %d" % info["tick"]
		_dir_label.add_theme_color_override("font_color", DIR_COLOR_REV)

	# ── Reversal cycle status ──
	var cycle: String = info.get("cycle_state", "READY")
	match cycle:
		"READY":
			_status_label.text = "R: Reversal Ready"
			_status_label.add_theme_color_override("font_color", STATUS_READY)
		"REVERSING":
			_status_label.text = "R: Return to Forward"
			_status_label.add_theme_color_override("font_color", STATUS_WARN)
		"LOCKED":
			var unlock: int = info.get("unlock_tick", 0)
			_status_label.text = "R: Locked (reach tick %d)" % unlock
			_status_label.add_theme_color_override("font_color", STATUS_LOCKED)

	# ── Debug panel ──
	if _debug_visible:
		var lines := PackedStringArray()
		lines.append("=== BRANCHES ===")
		for b in info["branches"]:
			var tag := ""
			if b["active"]:
				tag = " *ACTIVE*"
			elif b["collapsed"]:
				tag = " [COLLAPSED]"
			elif b["sealed"]:
				tag = " [sealed]"
			var d_str := "FWD" if b["dir"] == 1 else "REV"
			var r = b["range"]
			lines.append("  #%d  gen=%d  %d..%d  %s  %df%s" % [
				b["index"], b["gen"], r[0], r[1], d_str, b["frames"], tag
			])
		lines.append("")
		var unlock_str := ""
		if info.get("cycle_state", "") == "LOCKED":
			unlock_str = "  |  Unlock at tick: %d" % info.get("unlock_tick", -1)
		lines.append("Cycle: %s  |  Can reverse: %s  |  Reversals: %d%s" % [
			info.get("cycle_state", "?"),
			"YES" if info["can_reverse"] else "NO",
			info["reversal_count"],
			unlock_str,
		])
		lines.append("Room: %s  |  Room tick: %d" % [
			info["room_id"], info["room_tick"],
		])
		lines.append("Visible echoes: %d" % info["echo_count"])
		# Movement debug from player
		if timeline_manager.active_player and timeline_manager.active_player.has_method("get_movement_debug"):
			var mv: Dictionary = timeline_manager.active_player.get_movement_debug()
			lines.append("")
			lines.append("=== MOVEMENT ===")
			lines.append("State: %s  |  Dash: %s  |  DashTimer: %d" % [
				mv.get("state", "?"),
				"YES" if mv.get("dash_available", false) else "NO",
				mv.get("dash_timer", 0),
			])
			lines.append("Coyote: %d  |  JumpBuf: %d  |  OnWall: %s" % [
				mv.get("coyote", 0),
				mv.get("jump_buffer", 0),
				"YES" if mv.get("on_wall", false) else "NO",
			])
			lines.append("WallGrace: %d  |  EdgeGrace: %s  |  Vel: (%.0f, %.0f)" % [
				mv.get("wall_grace", 0),
				"YES" if mv.get("edge_grace", false) else "NO",
				mv.get("vel_x", 0.0),
				mv.get("vel_y", 0.0),
			])
		_debug_label.text = "\n".join(lines)


func show_level_complete() -> void:
	_complete_label.visible = true
	if _complete_subtitle:
		_complete_subtitle.visible = true


func hide_level_complete() -> void:
	_complete_label.visible = false
	if _complete_subtitle:
		_complete_subtitle.visible = false
