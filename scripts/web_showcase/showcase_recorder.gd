## ShowcaseRecorder — samples scene state into a ShowcaseReplayData resource
## during authoring, saves it to disk for the replay viewer.
##
## Hotkeys (only active when this node is in the tree, i.e. in the recording
## stage — never in the exported web build):
##   F9  start recording (resets the buffer)
##   F10 stop and save to save_path
##   F11 discard the in-progress recording
##   F8  insert a marker at the current time (cycles through preset labels)
##
## References are auto-discovered:
##   - active_player    via group "active_player" (or scene tree search)
##   - timeline_manager via group "timeline_manager"
##   - switches         via group "switches" (sorted by global_position.x)
##   - door             via group "doors" (first one)
extends Node

const ShowcaseReplayData = preload("res://scripts/web_showcase/showcase_replay_data.gd")

@export var save_path: String = "res://data/web_showcase/core_time_play_replay.tres"
@export var fps: int = 60
@export var actor_size: Vector2 = Vector2(24, 48)

const MARKER_LABELS := [
	"Start",
	"Record Action",
	"Rewind",
	"Echo Appears",
	"Cooperate",
	"Door Opens",
]

var recording: bool = false
var data: Resource = null   # ShowcaseReplayData
var _marker_idx: int = 0

var _active_player: Node = null
var _timeline: Node = null


func _ready() -> void:
	# Defer one frame so other scene scripts (recording_stage) finish wiring.
	call_deferred("_resolve_refs")


func _resolve_refs() -> void:
	var t := get_tree()
	if t == null:
		return
	# Player: prefer group, fall back to name search.
	var ap := t.get_first_node_in_group("active_player")
	if ap == null:
		ap = t.root.find_child("ActivePlayer", true, false)
	_active_player = ap
	# Timeline manager.
	_timeline = t.get_first_node_in_group("timeline_manager")
	if not recording:
		print("[ShowcaseRecorder] ready. F9 start | F10 save | F11 discard | F8 marker")


# ─────────────────────────────────────────────────────────────────────
#  Hotkey handling
# ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F9:
			_start()
		KEY_F10:
			_stop_and_save()
		KEY_F11:
			_discard()
		KEY_F8:
			_insert_marker()


func _start() -> void:
	data = ShowcaseReplayData.new()
	data.fps = fps
	data.duration = 0.0
	data.frames = []
	data.markers = []
	_marker_idx = 0
	recording = true
	print("[ShowcaseRecorder] RECORDING")


func _stop_and_save() -> void:
	if not recording:
		print("[ShowcaseRecorder] (nothing recording)")
		return
	recording = false
	if data == null or data.frames.is_empty():
		print("[ShowcaseRecorder] empty recording — not saved")
		return
	var dir_path := save_path.get_base_dir()
	var d := DirAccess.open("res://")
	if d and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var err := ResourceSaver.save(data, save_path)
	if err == OK:
		print("[ShowcaseRecorder] saved %d frames (%.2fs) → %s" % [data.frames.size(), data.duration, save_path])
	else:
		# Fallback to user:// if res:// blocked.
		var alt := "user://core_time_play_replay.tres"
		var err2 := ResourceSaver.save(data, alt)
		if err2 == OK:
			print("[ShowcaseRecorder] save to res:// failed (err=%d), wrote to %s" % [err, alt])
		else:
			push_error("[ShowcaseRecorder] save failed: %d / %d" % [err, err2])


func _discard() -> void:
	recording = false
	data = null
	_marker_idx = 0
	print("[ShowcaseRecorder] DISCARDED")


func _insert_marker() -> void:
	if not recording or data == null:
		print("[ShowcaseRecorder] (not recording — marker ignored)")
		return
	var label: String = MARKER_LABELS[mini(_marker_idx, MARKER_LABELS.size() - 1)]
	_marker_idx += 1
	data.markers.append({"t": data.duration, "label": label})
	print("[ShowcaseRecorder] marker @ %.2fs: %s" % [data.duration, label])


# ─────────────────────────────────────────────────────────────────────
#  Sampling
# ─────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not recording or data == null:
		return
	var t: float = data.duration
	var frame := _sample_frame(t)
	data.frames.append(frame)
	data.duration = t + delta


func _sample_frame(t: float) -> Dictionary:
	var f := {
		"t": t,
		"player_pos": Vector2.ZERO,
		"player_facing": 1,
		"player_anim": "",
		"player_visible": true,
		"echo_pos": Vector2.ZERO,
		"echo_facing": 1,
		"echo_anim": "",
		"echo_visible": false,
		"switch_a_pressed": false,
		"switch_b_pressed": false,
		"door_open": false,
		"door_progress": 0.0,
		"time_mode": "forward",
	}

	# Player.
	if _active_player and is_instance_valid(_active_player):
		f["player_pos"] = _active_player.global_position
		var fac = _active_player.get("facing")
		if typeof(fac) == TYPE_INT:
			f["player_facing"] = fac
		f["player_visible"] = _active_player.visible
		f["player_anim"] = _read_animation(_active_player)

	# Echo (first echo only — showcase has at most one).
	if _timeline and is_instance_valid(_timeline):
		var echoes = _timeline.get("echo_instances")
		if echoes is Array and echoes.size() > 0:
			for e in echoes:
				if e and is_instance_valid(e) and e.visible:
					f["echo_pos"] = e.global_position
					f["echo_visible"] = true
					var efac = e.get("facing")
					if typeof(efac) == TYPE_INT:
						f["echo_facing"] = efac
					f["echo_anim"] = _read_animation(e)
					break
		# time_mode from direction.
		var dir = _timeline.get("time_direction")
		if dir == -1:
			f["time_mode"] = "reverse"
		elif f["echo_visible"]:
			f["time_mode"] = "echo"
		else:
			f["time_mode"] = "forward"

	# Switches: sort by x to assign A (left) / B (right).
	var switches := get_tree().get_nodes_in_group("switches")
	if switches.size() >= 1:
		switches.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
		var sa = switches[0]
		var act_a = sa.get("activated")
		f["switch_a_pressed"] = bool(act_a) if act_a != null else false
		if switches.size() >= 2:
			var sb = switches[1]
			var act_b = sb.get("activated")
			f["switch_b_pressed"] = bool(act_b) if act_b != null else false

	# Door (first in group).
	var doors := get_tree().get_nodes_in_group("doors")
	if doors.size() > 0:
		var door = doors[0]
		var open_v = door.get("is_open")
		f["door_open"] = bool(open_v) if open_v != null else false
		# Best-effort progress: 1.0 if open, 0.0 if closed (door_receiver
		# has no public progress field, so we approximate).
		f["door_progress"] = 1.0 if f["door_open"] else 0.0

	return f


func _read_animation(node: Node) -> String:
	# Best-effort: look for a TimeAwareAnimator child with get_animation_state().
	var animator := node.find_child("TimeAwareAnimator", true, false)
	if animator and animator.has_method("get_animation_state"):
		var st = animator.get_animation_state()
		if st is Dictionary and st.has("name"):
			return String(st["name"])
	# Fallback: AnimatedSprite2D directly.
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return String(child.animation)
	return ""
