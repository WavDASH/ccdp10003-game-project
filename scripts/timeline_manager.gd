## TimelineManager — the heart of the time-branch / echo system.
##
## Owns the global tick, all branches, echo lifecycle, mechanism queries,
## hazard detection, and the echo validation pipeline.
##
## ### Forward-only echo persistence
## Only forward-recorded branches (direction == +1) spawn persistent RED echoes.
## Reverse is temporary navigation — no echo left behind.
## No hard cap on visible selves.
##
## ### Room-local tick
## Each room has a RoomTickContext that advances by time_direction while the
## player is present. Mechanisms use room_tick; echoes and branches use global_tick.
##
## ### Pivot-tick protocol (what happens the frame R is pressed)
##   1. Player has already recorded its state at global_tick.
##   2. Active branch is sealed at global_tick (inclusive).
##   3. time_direction flips.
##   4. New branch created starting at global_tick with the pivot frame copied in.
##   5. Echo spawned ONLY if sealed branch was forward (direction == +1).
##   6. advance_tick() runs at end of frame — tick moves in the NEW direction.
##
## ### Reversal cycle — tick-position lock
## A reversal cycle consists of exactly two R-presses:
##   READY      → R at tick A → REVERSING  (forward→reverse, store unlock_tick = A)
##   REVERSING  → R at tick B → LOCKED     (reverse→forward, B < A)
##   LOCKED     → forward play → when global_tick >= unlock_tick → READY
## The player cannot start a new reversal while LOCKED. This is NOT a
## cooldown timer — it's a positional lock tied to where the reversal began.
extends Node

# ─── Reversal cycle states ───────────────────────────────────────────
enum CycleState {
	READY,       ## Forward mode, R allowed — starts a new reversal
	REVERSING,   ## Reverse mode, R allowed — returns to forward
	LOCKED,      ## Forward mode, R blocked until global_tick reaches unlock_tick
}

# ─── Collision layer bitmasks ─────────────────────────────────────────
const LAYER_WORLD: int    = 1
const LAYER_DOOR: int     = 2
const LAYER_PLAYER: int   = 4
const LAYER_HAZARD: int   = 8
const LAYER_MECHANISM: int = 16
const LAYER_ECHO: int     = 32

# ─── Runtime state ────────────────────────────────────────────────────
var global_tick: int = 0
var time_direction: int = 1            # +1 forward, -1 reverse
var branches: Array = []               # Array of BranchTrack
var active_branch_index: int = -1
var echo_instances: Array = []         # Array of EchoPlayer nodes
var reversal_count: int = 0            # lifetime total (for stats)
var reversal_cycle: CycleState = CycleState.READY
var reversal_unlock_tick: int = -1     # global_tick the player must reach to unlock
var level_complete: bool = false

# ─── Room awareness ──────────────────────────────────────────────────
var current_room_id: String = ""
var room_tick_contexts: Dictionary = {}   # String room_id → RoomTickContext

# ─── External references (set by main.gd) ────────────────────────────
var active_player: CharacterBody2D = null
var echo_container: Node2D = null
var echo_player_scene: PackedScene = null
var player_spawn_pos: Vector2 = Vector2.ZERO

# ─── Auto-discovered level elements ─────────────────────────────────
var switches: Array = []
var timed_switches: Array = []
var doors: Array = []
var scheduled_receivers: Array = []
var hazard_rects: Array = []
var goal_rect: Rect2 = Rect2()
var has_goal: bool = false

# ─── Actor collision size (must match scene shapes) ──────────────────
var actor_collision_size: Vector2 = Vector2(24, 48)

# ─── Cached echo-validation shape (avoids per-frame allocation) ──
var _echo_validation_shape: RectangleShape2D = null

# ─── Cached crush-detection shape ────────────────────────────────
var _crush_detection_shape: RectangleShape2D = null

# ─── Signals ──────────────────────────────────────────────────────────
signal echo_spawned(echo)
signal echo_collapsed(echo, reason)
signal time_reversed(new_direction)
signal level_restart_requested()
signal level_completed()

# ─── Collapse reasons ────────────────────────────────────────────────
enum CollapseReason {
	NONE,
	GEOMETRY_OVERLAP,
	HAZARD_OVERLAP,
	GROUND_LOSS,
	CUSTOM,
}

# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	process_physics_priority = 1
	add_to_group("timeline_manager")
	_create_new_branch()


func _physics_process(_delta: float) -> void:
	_update_room_tick()
	_update_echoes()
	_update_mechanisms()
	_check_player_hazard()
	_check_player_crush()
	_check_goal()
	_advance_tick()

# ═════════════════════════════════════════════════════════════════════
#  Room management
# ═════════════════════════════════════════════════════════════════════

## Called by main.gd when a room transition occurs.
## Each room is a self-contained time sandbox. On entry we:
##   1. Set the room_id and ensure a RoomTickContext exists.
##   2. Reset ALL timeline state (tick, branches, echoes, VFX, reversal cycle).
##   3. Re-discover level elements (switches, doors, hazards, goals).
## This guarantees no branch/echo/VFX data from the previous room leaks in.
##
## Runs discovery IMMEDIATELY (not deferred) — by this point the old room
## has been removed from the tree via remove_child(), so group queries
## only return nodes from the new room. Deferring would leave stale refs
## in switches[]/doors[] for one frame.
func set_current_room(room_id: String) -> void:
	var is_new_room := (room_id != current_room_id)
	current_room_id = room_id
	if not room_tick_contexts.has(room_id):
		var ctx_script = load("res://scripts/room_tick_context.gd")
		var ctx = ctx_script.new()
		ctx.room_id = room_id
		room_tick_contexts[room_id] = ctx
	# Full timeline reset on actual room change — each room is its own sandbox.
	if is_new_room:
		reset_timeline()
	_discover_level()


func _update_room_tick() -> void:
	if current_room_id == "":
		return
	var ctx = room_tick_contexts.get(current_room_id)
	if ctx:
		ctx.advance(global_tick, time_direction)


func get_current_room_tick() -> int:
	var ctx = room_tick_contexts.get(current_room_id)
	if ctx:
		return ctx.room_tick
	return 0


func get_room_tick_at(p_global_tick: int, room_id: String) -> int:
	var ctx = room_tick_contexts.get(room_id)
	if ctx:
		return ctx.room_tick_at(p_global_tick)
	return -1

# ═════════════════════════════════════════════════════════════════════
#  Auto-discovery (runs on room load)
# ═════════════════════════════════════════════════════════════════════

func _discover_level() -> void:
	switches.clear()
	timed_switches.clear()
	doors.clear()
	scheduled_receivers.clear()
	hazard_rects.clear()
	has_goal = false

	for node in get_tree().get_nodes_in_group("switches"):
		switches.append(node)
	for node in get_tree().get_nodes_in_group("timed_switches"):
		timed_switches.append(node)
	for node in get_tree().get_nodes_in_group("doors"):
		doors.append(node)
	for node in get_tree().get_nodes_in_group("scheduled_receivers"):
		scheduled_receivers.append(node)
	for node in get_tree().get_nodes_in_group("hazards"):
		hazard_rects.append(node.get_hazard_rect())

	var goals = get_tree().get_nodes_in_group("goals")
	if goals.size() > 0:
		goal_rect = goals[0].get_goal_rect()
		has_goal = true

	var spawns = get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() > 0:
		player_spawn_pos = spawns[0].global_position

# ═════════════════════════════════════════════════════════════════════
#  Branch management
# ═════════════════════════════════════════════════════════════════════

func _create_new_branch() -> void:
	var branch := BranchTrack.new()
	branch.start_tick = global_tick
	branch.end_tick = global_tick
	branch.direction = time_direction
	branch.generation = branches.size()
	branches.append(branch)
	active_branch_index = branches.size() - 1


func get_active_branch() -> BranchTrack:
	if active_branch_index >= 0 and active_branch_index < branches.size():
		return branches[active_branch_index]
	return null


func record_frame(state: Dictionary) -> void:
	var branch := get_active_branch()
	if branch and not branch.sealed:
		# Inject room_id and room_tick into every recorded frame.
		state["room_id"] = current_room_id
		state["room_tick"] = get_current_room_tick()
		branch.record(global_tick, state)

# ═════════════════════════════════════════════════════════════════════
#  Reverse-mode interaction gate
# ═════════════════════════════════════════════════════════════════════

## CANONICAL GATE: returns true only when the active player should participate
## in mechanism/puzzle interactions. Systems that check whether the active player
## activates triggers, completes goals, or transitions rooms MUST call this first.
##
## While reversing (time_direction == -1), the player is in a non-interactive
## temporal traversal state for mechanism purposes — but still physically present.
##
## ── Semantic split: ALWAYS ACTIVE vs MECHANISM-GATED ──
##
## ALWAYS ACTIVE (work in both forward and reverse):
##   - Stand on floors, walls, platforms (StaticBody2D, layer 1)
##   - Ride moving platforms (AnimatableBody2D carries via move_and_slide)
##   - Jump through one-way platforms
##   - Physically stand on crumble blocks (collision stays active)
##   - Hazard death                   (TimelineManager._check_player_hazard)
##   These use physics collision or direct overlap checks without this gate.
##
## MECHANISM-GATED (excluded in reverse via this method):
##   - Switch / trigger activation    (TimelineManager._update_mechanisms)
##   - Goal completion                (TimelineManager._check_goal)
##   - Room exit transitions          (RoomManager._check_exits)
##   - Crumble block trigger          (CrumbleBlock._is_actor_on_top)
##   - Any future puzzle/mechanism interaction
##
## ALWAYS WORKS (unaffected by this gate):
##   - Frame recording / branch state (always records regardless)
##   - Echo interactions              (echoes have their own rules)
##   - Reversal input                 (player can always press R)
func is_player_interactable() -> bool:
	return time_direction == 1

# ═════════════════════════════════════════════════════════════════════
#  Reversal — cycle state machine with forward-only echo persistence
# ═════════════════════════════════════════════════════════════════════

## Returns true when the player is allowed to press R.
## READY: first R starts reverse. REVERSING: second R returns to forward.
## LOCKED: blocked until global_tick reaches reversal_unlock_tick.
func can_reverse() -> bool:
	return reversal_cycle != CycleState.LOCKED


func reverse_time() -> void:
	if not can_reverse():
		return

	var old_branch := get_active_branch()
	if old_branch:
		old_branch.seal(global_tick)

	# Advance cycle state BEFORE flipping direction.
	match reversal_cycle:
		CycleState.READY:
			# First R at tick A: store unlock boundary, enter reverse.
			reversal_unlock_tick = global_tick
			reversal_cycle = CycleState.REVERSING
		CycleState.REVERSING:
			# Second R at tick B (< A): return to forward, lock until tick A.
			reversal_cycle = CycleState.LOCKED

	time_direction *= -1

	_create_new_branch()
	var new_branch := get_active_branch()
	if old_branch and old_branch.has_tick(global_tick):
		new_branch.record(global_tick, old_branch.get_frame(global_tick))

	# Only spawn echo for forward-recorded branches.
	if old_branch and old_branch.direction == 1:
		_spawn_echo(old_branch)

	reversal_count += 1

	time_reversed.emit(time_direction)


func _spawn_echo(branch: BranchTrack) -> void:
	if echo_player_scene == null or echo_container == null:
		return
	var echo = echo_player_scene.instantiate()
	echo.init(branch, self)
	echo_container.add_child(echo)
	echo_instances.append(echo)
	echo_spawned.emit(echo)

# ═════════════════════════════════════════════════════════════════════
#  Tick
# ═════════════════════════════════════════════════════════════════════

func _advance_tick() -> void:
	global_tick += time_direction

	# Unlock reversal when forward progress reaches the original reversal-entry tick.
	if reversal_cycle == CycleState.LOCKED and global_tick >= reversal_unlock_tick:
		reversal_cycle = CycleState.READY
		reversal_unlock_tick = -1

# ═════════════════════════════════════════════════════════════════════
#  Echo update + validation pipeline (room-aware)
# ═════════════════════════════════════════════════════════════════════

func _update_echoes() -> void:
	var i := echo_instances.size() - 1
	while i >= 0:
		var echo = echo_instances[i]
		if not is_instance_valid(echo):
			echo_instances.remove_at(i)
			i -= 1
			continue

		if echo.branch.collapsed:
			if not echo.is_collapsing:
				echo.queue_free()
				echo_instances.remove_at(i)
			i -= 1
			continue

		if echo.branch.has_tick(global_tick):
			var frame: Dictionary = echo.branch.get_frame(global_tick)
			echo.apply_frame(frame)

			# Room-aware visibility: only show echoes in the current room.
			var frame_room: String = frame.get("room_id", "")
			if frame_room != current_room_id:
				echo.hide()
			else:
				echo.show()
				var reason := _validate_echo_at_tick(echo)
				if reason != CollapseReason.NONE:
					_collapse_echo(echo, reason)
		else:
			echo.hide()

		i -= 1


func _validate_echo_at_tick(echo) -> CollapseReason:
	if not echo.visible:
		return CollapseReason.NONE

	var space := get_viewport().world_2d.direct_space_state
	if space:
		var cs_node = echo.get_node_or_null("CollisionShape2D")
		if cs_node and cs_node.shape:
			# Lazy-init cached shape; reuse across all echoes + frames.
			if _echo_validation_shape == null:
				_echo_validation_shape = RectangleShape2D.new()
			_echo_validation_shape.size = cs_node.shape.size - Vector2(4, 4)

			var params := PhysicsShapeQueryParameters2D.new()
			params.shape = _echo_validation_shape
			params.transform = echo.global_transform
			params.collision_mask = LAYER_WORLD | LAYER_DOOR
			params.collide_with_bodies = true
			params.collide_with_areas = false

			if space.intersect_shape(params).size() > 0:
				return CollapseReason.GEOMETRY_OVERLAP

	var echo_rect := Rect2(
		echo.global_position - actor_collision_size / 2.0,
		actor_collision_size
	)
	for h_rect in hazard_rects:
		if echo_rect.intersects(h_rect):
			return CollapseReason.HAZARD_OVERLAP

	return CollapseReason.NONE


func _collapse_echo(echo, reason: CollapseReason) -> void:
	echo.branch.collapsed = true
	echo.start_collapse()
	echo_collapsed.emit(echo, reason)
	_trim_tick_history()


## Evict tick_history entries that no live branch could ever reference.
func _trim_tick_history() -> void:
	var min_tick: int = global_tick
	for b in branches:
		if not b.collapsed:
			min_tick = mini(min_tick, mini(b.start_tick, b.end_tick))
	for ctx in room_tick_contexts.values():
		ctx.trim_before(min_tick)

# ═════════════════════════════════════════════════════════════════════
#  Mechanism update (manual overlap queries)
# ═════════════════════════════════════════════════════════════════════

func _update_mechanisms() -> void:
	var player_can_interact := is_player_interactable()

	for sw in switches:
		if not is_instance_valid(sw):
			continue
		var any_pressed := false

		if player_can_interact and active_player and is_instance_valid(active_player):
			if sw.is_actor_in_zone(active_player.global_position, actor_collision_size):
				any_pressed = true

		if not any_pressed:
			for echo in echo_instances:
				if is_instance_valid(echo) and echo.visible and not echo.branch.collapsed:
					if sw.is_actor_in_zone(echo.global_position, actor_collision_size):
						any_pressed = true
						break

		sw.set_pressed(any_pressed)

	for door in doors:
		if is_instance_valid(door):
			door.evaluate_triggers()

	# Evaluate timed switches with hold timer against room_tick.
	var room_tick := get_current_room_tick()
	for ts in timed_switches:
		if is_instance_valid(ts):
			ts.evaluate_hold(room_tick)

	# Evaluate time-scheduled receivers against room_tick.
	for receiver in scheduled_receivers:
		if is_instance_valid(receiver):
			receiver.evaluate_schedule(room_tick)

# ═════════════════════════════════════════════════════════════════════
#  Hazard & goal checks
# ═════════════════════════════════════════════════════════════════════

func _check_player_hazard() -> void:
	# Hazards kill the player even during reverse — NOT gated by is_player_interactable().
	if active_player == null or not is_instance_valid(active_player):
		return
	var pr := Rect2(
		active_player.global_position - actor_collision_size / 2.0,
		actor_collision_size
	)
	for h_rect in hazard_rects:
		if pr.intersects(h_rect):
			restart_level()
			return


## Crush detection — kills the player if their collision shape overlaps
## World or Door layer bodies. Normal CharacterBody2D physics keeps the
## player separated from static geometry. Overlap only occurs when an
## external moving body (AnimatableBody2D platform, closing door) pushes
## the player into solid geometry, compressing them into an impossible space.
##
## NOT gated by is_player_interactable() — crush kills in both forward
## and reverse mode. This is a physical/environmental death, not a
## mechanism interaction.
##
## Uses a 2px-per-side shrink to avoid false positives from normal
## surface contact (CharacterBody2D's safe margin).
func _check_player_crush() -> void:
	if active_player == null or not is_instance_valid(active_player):
		return
	var space := get_viewport().world_2d.direct_space_state
	if space == null:
		return
	var cs_node = active_player.get_node_or_null("CollisionShape2D")
	if cs_node == null or not (cs_node.shape is RectangleShape2D):
		return

	# Lazy-init cached shape.
	if _crush_detection_shape == null:
		_crush_detection_shape = RectangleShape2D.new()
	# Shrink by 2px per side — tight enough to catch real embedding,
	# loose enough to ignore normal surface contact separation.
	_crush_detection_shape.size = cs_node.shape.size - Vector2(4, 4)

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _crush_detection_shape
	params.transform = active_player.global_transform
	params.collision_mask = LAYER_WORLD | LAYER_DOOR
	params.collide_with_bodies = true
	params.collide_with_areas = false
	# Exclude the player's own body from the query.
	params.exclude = [active_player.get_rid()]

	if space.intersect_shape(params).size() > 0:
		restart_level()
		return


func _check_goal() -> void:
	if not is_player_interactable():
		return
	if not has_goal or active_player == null or level_complete:
		return
	var pr := Rect2(
		active_player.global_position - actor_collision_size / 2.0,
		actor_collision_size
	)
	if pr.intersects(goal_rect):
		level_complete = true
		level_completed.emit()

# ═════════════════════════════════════════════════════════════════════
#  Timeline reset (per-room sandbox boundary)
# ═════════════════════════════════════════════════════════════════════

## Wipe all timeline state so the next room starts as a clean sandbox.
## Called on room transition. Does NOT reposition the player or reload
## the room — that's the caller's job. Does NOT emit level_restart_requested.
func reset_timeline() -> void:
	global_tick = 0
	time_direction = 1
	branches.clear()
	active_branch_index = -1
	reversal_count = 0
	reversal_cycle = CycleState.READY
	reversal_unlock_tick = -1
	level_complete = false

	# Free all echoes from the previous room.
	for echo in echo_instances:
		if is_instance_valid(echo):
			echo.queue_free()
	echo_instances.clear()

	# Reset the room tick context for the new room (created by set_current_room).
	var ctx = room_tick_contexts.get(current_room_id)
	if ctx:
		ctx.reset()

	# Start a fresh branch for the new room.
	_create_new_branch()

	# Reset the active player's movement effects so no VFX events
	# from the previous room can replay at matching tick positions.
	if active_player and active_player.has_method("reset"):
		active_player.reset()

# ═════════════════════════════════════════════════════════════════════
#  Level restart
# ═════════════════════════════════════════════════════════════════════

func restart_level() -> void:
	global_tick = 0
	time_direction = 1
	branches.clear()
	active_branch_index = -1
	reversal_count = 0
	reversal_cycle = CycleState.READY
	reversal_unlock_tick = -1
	level_complete = false

	for echo in echo_instances:
		if is_instance_valid(echo):
			echo.queue_free()
	echo_instances.clear()

	# Reset room tick for current room.
	var ctx = room_tick_contexts.get(current_room_id)
	if ctx:
		ctx.reset()

	_create_new_branch()

	if active_player:
		active_player.global_position = player_spawn_pos
		active_player.velocity = Vector2.ZERO
		if active_player.has_method("reset"):
			active_player.reset()

	# NOTE: mechanism reset (switches/doors) is handled by room reload
	# in main.gd._on_restart(). Fresh room instances start in default state.

	level_restart_requested.emit()

# ═════════════════════════════════════════════════════════════════════
#  Debug / HUD info
# ═════════════════════════════════════════════════════════════════════

func get_debug_info() -> Dictionary:
	var branch_info: Array = []
	for i in range(branches.size()):
		var b: BranchTrack = branches[i]
		branch_info.append({
			"index": i,
			"gen": b.generation,
			"range": [b.start_tick, b.end_tick],
			"dir": b.direction,
			"sealed": b.sealed,
			"collapsed": b.collapsed,
			"active": i == active_branch_index,
			"frames": b.frames.size(),
		})

	var visible_echo_count := 0
	for e in echo_instances:
		if is_instance_valid(e) and e.visible and not e.branch.collapsed:
			visible_echo_count += 1

	var cycle_name: String
	match reversal_cycle:
		CycleState.READY:
			cycle_name = "READY"
		CycleState.REVERSING:
			cycle_name = "REVERSING"
		CycleState.LOCKED:
			cycle_name = "LOCKED"

	return {
		"tick": global_tick,
		"direction": time_direction,
		"reversal_count": reversal_count,
		"can_reverse": can_reverse(),
		"cycle_state": cycle_name,
		"unlock_tick": reversal_unlock_tick,
		"active_branch": active_branch_index,
		"branch_count": branches.size(),
		"echo_count": visible_echo_count,
		"branches": branch_info,
		"room_id": current_room_id,
		"room_tick": get_current_room_tick(),
	}
