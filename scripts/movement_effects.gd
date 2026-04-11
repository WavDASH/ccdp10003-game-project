## MovementEffects — tick-driven replayable movement VFX manager.
##
## VFX events are temporal objects with a tick lifespan. At any tick, each
## effect's visual state is a deterministic function of (current_tick - spawn_tick).
##
## Two aging modes:
##   monotonic (live player) — internal counter increments +1 every update_tick
##       call regardless of game time direction. Live effects always fade
##       forward in real time even when the game clock runs backward.
##   global (echoes) — uses the external tick (global_tick) passed to
##       update_tick. Effects age forward/backward with the game clock,
##       producing correct rewind visuals.
##
## Ghosts are children of this node with top_level=true. When the parent
## actor is hidden (echo goes out of tick range), call clear_ghosts() to
## remove them — top_level children do not inherit parent visibility.
extends Node

const MOTION_STATE_NORMAL := 0
const MOTION_STATE_DASH := 1
const MOTION_STATE_WALL_JUMP_LOCK := 2

# ─── Dash trail parameters ──────────────────────────────────────────
@export_group("Dash Trail")
@export var dash_trail_enabled: bool = true
## Spawn a ghost every N ticks while in DASH state.
@export var dash_trail_interval_ticks: int = 2
## How many ticks each ghost lives. At 60 FPS, 18 ticks ≈ 0.3 seconds.
@export var dash_trail_lifetime_ticks: int = 18
## Peak alpha (at spawn tick, age = 0).
@export var dash_trail_start_alpha: float = 0.55
## Color tint applied on top of actor_tint.
@export var dash_trail_tint: Color = Color(0.85, 0.95, 1.0, 1.0)
## Draw order offset. 0 = same as gameplay elements.
@export var dash_trail_z_offset: int = 0

# ─── Runtime state ──────────────────────────────────────────────────
## Actor-level tint (white for player, red/blue for echoes).
var actor_tint: Color = Color(1, 1, 1, 1)
## SpriteFrames for ghost textures.
var sprite_frames: SpriteFrames = null
## If true, age advances by +1 per update_tick call (live player).
## If false, age is computed from the passed tick (echoes).
var use_monotonic_aging: bool = false

# ─── Event registry ─────────────────────────────────────────────────
var _known_events: Array = []
# ─── Active ghosts (event index → Sprite2D) ─────────────────────────
var _active_ghosts: Dictionary = {}

# ─── Monotonic counter (live player mode) ───────────────────────────
var _mono_tick: int = 0

# ─── Generation state (live player trigger rules) ───────────────────
var _gen_tick_counter: int = 0
var _gen_last_trail_tick: int = -9999
var _gen_prev_motion_state: int = MOTION_STATE_NORMAL


# ═════════════════════════════════════════════════════════════════════
#  Event generation (live player only)
# ═════════════════════════════════════════════════════════════════════

## Applies trigger rules. Returns events to store in frame_data["vfx"].
## global_tick: the game clock tick (for recording / echo replay).
func generate_events(state: Dictionary, global_tick: int) -> Array:
	_gen_tick_counter += 1
	var events: Array = []
	var motion_state: int = int(state.get("motion_state", MOTION_STATE_NORMAL))

	if dash_trail_enabled and motion_state == MOTION_STATE_DASH:
		if _gen_tick_counter - _gen_last_trail_tick >= dash_trail_interval_ticks:
			var ev := {
				"type": "dash_trail",
				"tick": global_tick,
				"position": state.get("position", Vector2.ZERO),
				"flip_h": bool(state.get("flip_h", false)),
				"anim_name": state.get("anim_name", ""),
				"anim_frame": int(state.get("anim_frame", 0)),
			}
			# For monotonic aging, tag with the internal counter.
			if use_monotonic_aging:
				ev["_mono_spawn"] = _mono_tick
			events.append(ev)
			_known_events.append(ev)
			_gen_last_trail_tick = _gen_tick_counter

	_gen_prev_motion_state = motion_state
	return events


# ═════════════════════════════════════════════════════════════════════
#  Event pre-registration (echoes only)
# ═════════════════════════════════════════════════════════════════════

## Scans the sealed branch for all recorded VFX events.
func load_events_from_branch(branch) -> void:
	_known_events.clear()
	for tick_key in branch.frames:
		var frame_dict: Dictionary = branch.frames[tick_key]
		var vfx: Array = frame_dict.get("vfx", [])
		for ev in vfx:
			var ev_copy: Dictionary = ev.duplicate()
			if not ev_copy.has("tick"):
				ev_copy["tick"] = tick_key
			_known_events.append(ev_copy)


# ═════════════════════════════════════════════════════════════════════
#  Per-tick ghost management
# ═════════════════════════════════════════════════════════════════════

## Call every physics tick.
## external_tick: global_tick for echoes, ignored for monotonic mode
##                (but still passed for consistency).
func update_tick(external_tick: int) -> void:
	if use_monotonic_aging:
		_mono_tick += 1

	for i in _known_events.size():
		var event: Dictionary = _known_events[i]
		var event_type: String = event.get("type", "")
		var lifetime: int = _get_lifetime_for_type(event_type)
		if lifetime <= 0:
			continue

		var age: int = _compute_age(event, external_tick)

		if age >= 0 and age <= lifetime:
			var alpha: float = _get_alpha_for_type(event_type, age, lifetime)
			if not _active_ghosts.has(i):
				_create_ghost(i, event, alpha)
			else:
				_update_ghost(i, alpha)
		else:
			if _active_ghosts.has(i):
				_remove_ghost(i)


func _compute_age(event: Dictionary, external_tick: int) -> int:
	if use_monotonic_aging and event.has("_mono_spawn"):
		return _mono_tick - int(event["_mono_spawn"])
	return external_tick - int(event.get("tick", 0))


## Full reset — clears all events, ghosts, and generation state.
## Called on room transition or level restart so no stale VFX data
## from a previous room can leak into the current one.
func reset() -> void:
	clear_ghosts()
	_known_events.clear()
	_mono_tick = 0
	_gen_tick_counter = 0
	_gen_last_trail_tick = -9999
	_gen_prev_motion_state = MOTION_STATE_NORMAL


## Remove all active ghosts immediately. Called when the parent actor
## is hidden (echo goes out of tick range). top_level children do not
## inherit parent visibility, so this explicit cleanup is required.
func clear_ghosts() -> void:
	for idx in _active_ghosts:
		var ghost = _active_ghosts[idx]
		if ghost != null and is_instance_valid(ghost):
			ghost.queue_free()
	_active_ghosts.clear()


func _get_lifetime_for_type(event_type: String) -> int:
	match event_type:
		"dash_trail":
			return dash_trail_lifetime_ticks
	return 0


func _get_alpha_for_type(event_type: String, age: int, lifetime: int) -> float:
	match event_type:
		"dash_trail":
			var t: float = float(age) / float(lifetime)
			return dash_trail_start_alpha * (1.0 - t) * actor_tint.a
	return 0.0


# ═════════════════════════════════════════════════════════════════════
#  Ghost lifecycle
# ═════════════════════════════════════════════════════════════════════

func _create_ghost(idx: int, event: Dictionary, alpha: float) -> void:
	if sprite_frames == null:
		return
	var anim: String = event.get("anim_name", "")
	if anim == "" or not sprite_frames.has_animation(anim):
		return
	var frame_idx: int = int(event.get("anim_frame", 0))
	if frame_idx >= sprite_frames.get_frame_count(anim):
		return
	var tex: Texture2D = sprite_frames.get_frame_texture(anim, frame_idx)
	if tex == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = bool(event.get("flip_h", false))
	ghost.z_index = dash_trail_z_offset
	ghost.top_level = true
	ghost.modulate = Color(
		dash_trail_tint.r * actor_tint.r,
		dash_trail_tint.g * actor_tint.g,
		dash_trail_tint.b * actor_tint.b,
		alpha,
	)
	add_child(ghost)
	ghost.global_position = event.get("position", Vector2.ZERO)
	_active_ghosts[idx] = ghost


func _update_ghost(idx: int, alpha: float) -> void:
	var ghost = _active_ghosts.get(idx)
	if ghost == null or not is_instance_valid(ghost):
		_active_ghosts.erase(idx)
		return
	ghost.modulate.a = alpha


func _remove_ghost(idx: int) -> void:
	var ghost = _active_ghosts.get(idx)
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	_active_ghosts.erase(idx)
