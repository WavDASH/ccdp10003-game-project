## ShowcaseReplayViewer — non-interactive replay viewer for the website.
##
## Loads a ShowcaseReplayData resource and drives all visuals (player, echo,
## switches, door, screen tint, captions) from recorded frame data. No
## TimelineManager, no ActivePlayer, no SwitchTrigger — every visual is a
## simple Node2D that this script positions and tints per frame.
##
## Controls (mouse only):
##   Play / Pause, Reverse, Restart, Speed (0.5/1/2x), Timeline scrub.
extends Node2D

const REPLAY_PATH := "res://data/web_showcase/core_time_play_replay.tres"

@export var replay_data: Resource = null  # ShowcaseReplayData

# ── Visual node refs (set in scene) ──
@onready var screen_tint: ColorRect      = $ScreenTint
@onready var player_visual: Node2D       = $Room/PlayerVisual
@onready var echo_visual: Node2D         = $Room/EchoVisual
@onready var switch_a_visual: Node2D     = $Room/SwitchAVisual
@onready var switch_b_visual: Node2D     = $Room/SwitchBVisual
@onready var door_visual: Node2D         = $Room/DoorVisual

# ── UI refs ──
@onready var title_label: Label          = $UI/TitleLabel
@onready var caption_label: Label        = $UI/CaptionLabel
@onready var timeline_slider: HSlider    = $UI/BottomBar/TimelineSlider
@onready var marker_strip: Control       = $UI/BottomBar/MarkerStrip
@onready var play_pause_button: Button   = $UI/Buttons/PlayPauseButton
@onready var reverse_button: Button      = $UI/Buttons/ReverseButton
@onready var restart_button: Button      = $UI/Buttons/RestartButton
@onready var speed_button: OptionButton  = $UI/Buttons/SpeedButton
@onready var no_replay_overlay: Label    = $UI/NoReplayOverlay

# ── Playback state ──
var current_time: float = 0.0
var playback_speed: float = 1.0
var playing: bool = true
var reverse_playback: bool = false
var _scrubbing: bool = false

# ── Visual constants (project palette) ──
const COL_PLAYER     := Color(0.95, 0.95, 1.0, 1.0)
const COL_PLAYER_OUT := Color(1.0, 1.0, 1.0, 0.6)
const COL_ECHO       := Color(0.55, 0.75, 1.0, 0.55)
const COL_ECHO_OUT   := Color(0.7, 0.85, 1.0, 0.5)
const COL_SWITCH_OFF := Color(0.6, 0.55, 0.0, 1.0)
const COL_SWITCH_ON  := Color(1.0, 1.0, 0.25, 1.0)
const COL_DOOR_OPEN  := Color(0.6, 0.35, 0.15, 0.25)
const COL_DOOR_CLOSED:= Color(0.6, 0.35, 0.15, 1.0)

const TINT_FORWARD := Color(0.8, 0.45, 0.2, 0.04)
const TINT_REVERSE := Color(0.15, 0.4, 1.0, 0.16)
const TINT_ECHO    := Color(0.5, 0.6, 1.0, 0.05)

const CAPTIONS := {
	"Start":         "One player cannot hold two switches at once.",
	"Record Action": "First, the player records an action.",
	"Rewind":        "Rewinding does not erase the action.",
	"Echo Appears":  "The past action becomes an Echo.",
	"Cooperate":     "The Echo repeats the first action while the present self takes a new path.",
	"Door Opens":    "The solution is built from history.",
}


func _ready() -> void:
	if replay_data == null:
		if ResourceLoader.exists(REPLAY_PATH):
			replay_data = load(REPLAY_PATH)
	_setup_ui()
	_setup_speed_options()
	_connect_signals()
	if replay_data == null or replay_data.frames.is_empty():
		_show_no_replay()
		return
	no_replay_overlay.visible = false
	timeline_slider.min_value = 0.0
	timeline_slider.max_value = maxf(replay_data.duration, 0.001)
	timeline_slider.step = 0.001
	_build_marker_strip()
	apply_sample(sample_replay(0.0))
	_update_caption(0.0)
	_update_play_button()


func _setup_ui() -> void:
	title_label.text = "Core Time Mechanic"
	caption_label.text = ""
	if no_replay_overlay:
		no_replay_overlay.visible = false


func _setup_speed_options() -> void:
	speed_button.clear()
	speed_button.add_item("0.5×", 0)
	speed_button.add_item("1×", 1)
	speed_button.add_item("2×", 2)
	speed_button.select(1)


func _connect_signals() -> void:
	timeline_slider.value_changed.connect(_on_slider_changed)
	timeline_slider.drag_started.connect(_on_slider_drag_started)
	timeline_slider.drag_ended.connect(_on_slider_drag_ended)
	play_pause_button.pressed.connect(_on_play_pause)
	reverse_button.pressed.connect(_on_reverse)
	restart_button.pressed.connect(_on_restart)
	speed_button.item_selected.connect(_on_speed_selected)


# ─────────────────────────────────────────────────────────────────────
#  Process loop
# ─────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if replay_data == null or replay_data.frames.is_empty():
		return
	if playing and not _scrubbing:
		var dir := -1.0 if reverse_playback else 1.0
		current_time = clampf(current_time + delta * playback_speed * dir,
			0.0, replay_data.duration)
		# Auto-pause at boundaries.
		if current_time <= 0.0 and reverse_playback:
			playing = false
			_update_play_button()
		elif current_time >= replay_data.duration and not reverse_playback:
			playing = false
			_update_play_button()
		timeline_slider.set_value_no_signal(current_time)
		apply_sample(sample_replay(current_time))
		_update_caption(current_time)


# ─────────────────────────────────────────────────────────────────────
#  Sampling
# ─────────────────────────────────────────────────────────────────────

func sample_replay(t: float) -> Dictionary:
	var frames: Array = replay_data.frames
	if frames.is_empty():
		return {}
	if t <= frames[0].t:
		return frames[0]
	if t >= frames[frames.size() - 1].t:
		return frames[frames.size() - 1]
	var lo := 0
	var hi := frames.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if frames[mid].t <= t:
			lo = mid
		else:
			hi = mid
	var fa: Dictionary = frames[lo]
	var fb: Dictionary = frames[hi]
	var span := fb.t - fa.t
	var alpha := 0.0 if span <= 0.0 else clampf((t - fa.t) / span, 0.0, 1.0)
	# Interpolate continuous fields; take nearest-previous for discrete ones.
	var out := fa.duplicate(true)
	out["t"] = t
	out["player_pos"] = fa.player_pos.lerp(fb.player_pos, alpha)
	out["echo_pos"] = fa.echo_pos.lerp(fb.echo_pos, alpha)
	out["door_progress"] = lerpf(fa.door_progress, fb.door_progress, alpha)
	return out


func apply_sample(sample: Dictionary) -> void:
	if sample.is_empty():
		return
	# Player
	player_visual.position = sample.player_pos
	player_visual.visible = sample.get("player_visible", true)
	var pf: int = sample.get("player_facing", 1)
	player_visual.scale.x = 1.0 if pf >= 0 else -1.0
	# Echo
	var echo_v: bool = sample.get("echo_visible", false)
	echo_visual.visible = echo_v
	if echo_v:
		echo_visual.position = sample.echo_pos
		var ef: int = sample.get("echo_facing", 1)
		echo_visual.scale.x = 1.0 if ef >= 0 else -1.0
	# Switches
	_set_switch_visual(switch_a_visual, sample.get("switch_a_pressed", false))
	_set_switch_visual(switch_b_visual, sample.get("switch_b_pressed", false))
	# Door
	_set_door_visual(sample.get("door_open", false), sample.get("door_progress", 0.0))
	# Screen tint by mode
	var mode: String = sample.get("time_mode", "forward")
	match mode:
		"reverse": screen_tint.color = TINT_REVERSE
		"echo":    screen_tint.color = TINT_ECHO
		_:         screen_tint.color = TINT_FORWARD


func _set_switch_visual(node: Node2D, pressed: bool) -> void:
	var poly: Polygon2D = node.get_node_or_null("Plate")
	if poly:
		poly.color = COL_SWITCH_ON if pressed else COL_SWITCH_OFF


func _set_door_visual(is_open: bool, progress: float) -> void:
	var poly: Polygon2D = door_visual.get_node_or_null("Body")
	if poly:
		var p := clampf(progress, 0.0, 1.0)
		# Alpha fades when opening.
		poly.color = COL_DOOR_CLOSED.lerp(COL_DOOR_OPEN, p)
	# Optional: vertical lift to suggest opening
	door_visual.scale.y = lerpf(1.0, 0.05, clampf(progress, 0.0, 1.0))


# ─────────────────────────────────────────────────────────────────────
#  Markers / captions
# ─────────────────────────────────────────────────────────────────────

func _build_marker_strip() -> void:
	for c in marker_strip.get_children():
		c.queue_free()
	if replay_data.duration <= 0.0:
		return
	var w := marker_strip.size.x
	for m in replay_data.markers:
		var mt: float = m.get("t", 0.0)
		var label: String = m.get("label", "")
		var lbl := Label.new()
		lbl.text = label
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		var x := (mt / replay_data.duration) * w
		lbl.position = Vector2(x - 30, 0)
		lbl.size = Vector2(120, 14)
		marker_strip.add_child(lbl)


func _update_caption(t: float) -> void:
	var label_text := ""
	var best_t := -INF
	for m in replay_data.markers:
		var mt: float = m.get("t", 0.0)
		if mt <= t and mt >= best_t:
			best_t = mt
			label_text = String(m.get("label", ""))
	caption_label.text = CAPTIONS.get(label_text, "")


# ─────────────────────────────────────────────────────────────────────
#  UI signal handlers
# ─────────────────────────────────────────────────────────────────────

func _on_slider_changed(v: float) -> void:
	current_time = v
	apply_sample(sample_replay(current_time))
	_update_caption(current_time)


func _on_slider_drag_started() -> void:
	_scrubbing = true
	playing = false
	_update_play_button()


func _on_slider_drag_ended(_value_changed: bool) -> void:
	_scrubbing = false


func _on_play_pause() -> void:
	playing = not playing
	# If we were at the end and pressing play forward, restart.
	if playing and not reverse_playback and current_time >= replay_data.duration:
		current_time = 0.0
		timeline_slider.set_value_no_signal(0.0)
	if playing and reverse_playback and current_time <= 0.0:
		current_time = replay_data.duration
		timeline_slider.set_value_no_signal(current_time)
	_update_play_button()


func _on_reverse() -> void:
	reverse_playback = not reverse_playback
	reverse_button.modulate = Color(0.6, 0.8, 1.0) if reverse_playback else Color(1, 1, 1)


func _on_restart() -> void:
	current_time = 0.0
	reverse_playback = false
	playing = true
	reverse_button.modulate = Color(1, 1, 1)
	timeline_slider.set_value_no_signal(0.0)
	apply_sample(sample_replay(0.0))
	_update_caption(0.0)
	_update_play_button()


func _on_speed_selected(idx: int) -> void:
	match idx:
		0: playback_speed = 0.5
		1: playback_speed = 1.0
		2: playback_speed = 2.0


func _update_play_button() -> void:
	play_pause_button.text = "❚❚ Pause" if playing else "▶ Play"


# ─────────────────────────────────────────────────────────────────────
#  Fallback overlay
# ─────────────────────────────────────────────────────────────────────

func _show_no_replay() -> void:
	timeline_slider.editable = false
	play_pause_button.disabled = true
	reverse_button.disabled = true
	restart_button.disabled = true
	speed_button.disabled = true
	if no_replay_overlay:
		no_replay_overlay.visible = true
		no_replay_overlay.text = "No replay loaded.\n\nRun core_time_play_recording_stage.tscn,\npress F9 to record, F10 to save."
