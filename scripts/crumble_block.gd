## CrumbleBlock — a platform that crumbles after an actor stands on it.
##
## Extends TerrainBlock. When an actor (player or echo) stands on top during
## forward play, a crumble timer starts. After crumble_delay_ticks the block
## breaks (collision disabled, visual fades). It respawns after
## respawn_delay_ticks, or never if that value is -1.
##
## ── Timeline replay ──
## State transitions (SOLID → CRUMBLING → BROKEN → SOLID) are recorded at
## their room_tick. During reverse play the block replays that history
## backward — no new crumble triggers fire. This keeps the block's state
## consistent with what echoes experienced during the original forward pass.
##
## After a reversal the log is trimmed to the current room_tick so a new
## forward pass can produce different events (e.g. no actor steps on it).
##
## Detection uses a thin rect above the block surface (not full overlap).
@tool
class_name CrumbleBlock
extends TerrainBlock

enum BlockState { SOLID, CRUMBLING, BROKEN }

@export_group("Crumble")
## Ticks after an actor steps on before the block breaks.
@export var crumble_delay_ticks: int = 30

## Ticks after breaking before the block reappears. -1 = never respawn.
@export var respawn_delay_ticks: int = 180

@export_group("Crumble Visuals")
@export var crumble_color: Color = Color(0.5, 0.35, 0.2, 1.0):
	set(value):
		crumble_color = value
		if _current_state == BlockState.SOLID:
			block_color = crumble_color

@export var warning_color: Color = Color(0.8, 0.4, 0.15, 1.0)

## ── Internal state ──────────────────────────────────────────────────
var _current_state: BlockState = BlockState.SOLID
## Sorted list of {tick: int, state: BlockState}. Forward play appends;
## reverse play reads. Trimmed on re-entry to forward after a reversal.
var _state_log: Array = []

## Forward-play counters (only ticked during forward).
var _crumble_counter: int = -1
var _respawn_counter: int = -1

var _timeline: Node = null


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group("crumble_blocks")
		block_color = crumble_color
		_timeline = _find_timeline()


func _find_timeline() -> Node:
	var nodes = get_tree().get_nodes_in_group("timeline_manager")
	if nodes.size() > 0:
		return nodes[0]
	return null


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _timeline == null:
		return

	var room_tick: int = _timeline.get_current_room_tick()

	if _timeline.time_direction == 1:
		_forward_tick(room_tick)
	else:
		_reverse_tick(room_tick)


# ═════════════════════════════════════════════════════════════════════
#  Forward play — normal crumble logic + state recording
# ═════════════════════════════════════════════════════════════════════

func _forward_tick(room_tick: int) -> void:
	# Trim any log entries beyond current room_tick. These are leftovers
	# from a previous forward pass that was reversed. The new forward pass
	# may produce different events.
	while _state_log.size() > 0 and _state_log.back().tick > room_tick:
		_state_log.pop_back()

	# After trimming, sync _current_state to whatever the log says at
	# this room_tick. Handles the first forward frame after a reversal
	# where _current_state may still reflect the old reverse-replay state.
	var logged := _state_from_log(room_tick)
	if _current_state != logged:
		_apply_block_state(logged)
		# Reset counters — the new forward pass starts fresh from this state.
		_crumble_counter = -1
		_respawn_counter = -1

	match _current_state:
		BlockState.SOLID:
			if _is_actor_on_top():
				_record_transition(BlockState.CRUMBLING, room_tick)
				_crumble_counter = crumble_delay_ticks
		BlockState.CRUMBLING:
			_crumble_counter -= 1
			# Warning flash.
			if _crumble_counter >= 0:
				if _crumble_counter % 6 < 3:
					_set_visual_color(warning_color)
				else:
					_set_visual_color(crumble_color)
			if _crumble_counter < 0:
				_record_transition(BlockState.BROKEN, room_tick)
				_respawn_counter = respawn_delay_ticks if respawn_delay_ticks >= 0 else -1
		BlockState.BROKEN:
			if _respawn_counter >= 0:
				_respawn_counter -= 1
				if _respawn_counter < 0:
					_record_transition(BlockState.SOLID, room_tick)


# ═════════════════════════════════════════════════════════════════════
#  Reverse play — replay state history backward
# ═════════════════════════════════════════════════════════════════════

func _reverse_tick(room_tick: int) -> void:
	var target := _state_from_log(room_tick)
	if target != _current_state:
		_apply_block_state(target)
	elif target == BlockState.CRUMBLING:
		# Update flash even when state hasn't changed.
		_update_crumble_flash_from_log(room_tick)


# ═════════════════════════════════════════════════════════════════════
#  State log helpers
# ═════════════════════════════════════════════════════════════════════

## Record a transition and apply it immediately.
func _record_transition(new_state: BlockState, room_tick: int) -> void:
	_state_log.append({tick = room_tick, state = new_state})
	_apply_block_state(new_state)


## Find the effective state at a given room_tick by scanning the log.
func _state_from_log(room_tick: int) -> BlockState:
	var result := BlockState.SOLID
	for entry in _state_log:
		if entry.tick <= room_tick:
			result = entry.state as BlockState
		else:
			break
	return result


## Find the room_tick when the most recent CRUMBLING transition began
## at or before the given room_tick. Returns -1 if not found.
func _find_crumble_start(room_tick: int) -> int:
	var crumble_tick: int = -1
	for entry in _state_log:
		if entry.tick > room_tick:
			break
		if entry.state == BlockState.CRUMBLING:
			crumble_tick = entry.tick
	return crumble_tick


## Update crumble flash visual during reverse replay.
func _update_crumble_flash_from_log(room_tick: int) -> void:
	var start := _find_crumble_start(room_tick)
	if start >= 0:
		var elapsed := room_tick - start
		if elapsed % 6 < 3:
			_set_visual_color(warning_color)
		else:
			_set_visual_color(crumble_color)


# ═════════════════════════════════════════════════════════════════════
#  State application (collision + visual)
# ═════════════════════════════════════════════════════════════════════

func _apply_block_state(state: BlockState) -> void:
	_current_state = state
	var cs = get_node_or_null("CollisionShape2D")
	match state:
		BlockState.SOLID:
			if cs:
				cs.set_deferred("disabled", false)
			collision_layer = 1
			_set_visual_color(crumble_color)
		BlockState.CRUMBLING:
			if cs:
				cs.set_deferred("disabled", false)
			collision_layer = 1
			_set_visual_color(warning_color)
		BlockState.BROKEN:
			if cs:
				cs.set_deferred("disabled", true)
			collision_layer = 0
			_set_visual_color(Color(crumble_color.r, crumble_color.g, crumble_color.b, 0.15))


# ═════════════════════════════════════════════════════════════════════
#  Actor detection (forward play only)
# ═════════════════════════════════════════════════════════════════════

func _is_actor_on_top() -> bool:
	if _timeline == null:
		return false

	# Thin detection rect sitting on top of the block surface.
	var detect_rect := Rect2(
		global_position.x - block_size.x / 2.0,
		global_position.y - block_size.y / 2.0 - 8,
		block_size.x,
		8
	)
	var actor_size: Vector2 = _timeline.actor_collision_size

	# Check player (only if interactable — reverse player doesn't trigger crumble).
	if _timeline.is_player_interactable():
		var player = _timeline.active_player
		if player and is_instance_valid(player):
			var pr := Rect2(player.global_position - actor_size / 2.0, actor_size)
			if detect_rect.intersects(pr):
				return true

	# Check echoes.
	for echo in _timeline.echo_instances:
		if is_instance_valid(echo) and echo.visible and not echo.branch.collapsed:
			var er := Rect2(echo.global_position - actor_size / 2.0, actor_size)
			if detect_rect.intersects(er):
				return true

	return false


func _set_visual_color(c: Color) -> void:
	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		visual.color = c
