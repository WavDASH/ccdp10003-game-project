## BaseMechanismReceiver — base class for elements that respond to triggers.
##
## Extends BasePlaceable with trigger evaluation logic.
## Subclass this for doors, moving platforms, laser emitters, etc.
## The TimelineManager calls evaluate_triggers() each frame.
##
## ── Timeline replay ──
## State transitions (open/close) are recorded at their room_tick during
## forward play. During reverse the receiver replays that history backward
## instead of re-evaluating triggers live. After a reversal, future log
## entries are trimmed so a new forward pass can produce different events.
@tool
class_name BaseMechanismReceiver
extends BasePlaceable

@export_group("Trigger Wiring")
## NodePaths to BaseMechanismTrigger nodes (used when set in editor).
@export var triggers: Array[NodePath] = []:
	set(value):
		triggers = value
		queue_redraw()
		update_configuration_warnings()

## If true, ALL triggers must be active. If false, ANY suffices.
@export var require_all: bool = true

## Frames to wait before closing after triggers are lost. 0 = instant close.
## Acts as a grace period — if triggers re-satisfy during the delay, the
## close is cancelled and the receiver stays open.
@export var close_delay_ticks: int = 0

## Resolved trigger node references.
var trigger_nodes: Array = []

## Current state.
var is_open: bool = false

## Close-delay countdown. -1 = idle (no pending close).
var _close_delay_counter: int = -1

## State history — records open/close transitions at room_ticks.
## Array of {tick: int, open: bool}, sorted by tick (forward play appends).
var _state_log: Array = []

## Timeline manager reference (for time_direction and room_tick).
var _timeline: Node = null


func _runtime_ready() -> void:
	_timeline = _find_timeline()
	call_deferred("_resolve_triggers")


func _find_timeline() -> Node:
	var nodes = get_tree().get_nodes_in_group("timeline_manager")
	if nodes.size() > 0:
		return nodes[0]
	return null


## Resolves NodePaths to actual trigger nodes.  Skipped if trigger_nodes
## was already populated externally (e.g. by the level builder).
func _resolve_triggers() -> void:
	if trigger_nodes.size() > 0:
		return
	for path in triggers:
		var node = get_node_or_null(path)
		if node:
			trigger_nodes.append(node)


## Evaluate trigger states according to the configured rule.
## During forward play: evaluates live + records state transitions.
## During reverse play: replays state from recorded history.
func evaluate_triggers() -> void:
	# ── Reverse: replay from history ──
	if _timeline and _timeline.time_direction == -1:
		_replay_state()
		return

	# ── Forward: live evaluation + recording ──
	var room_tick: int = _timeline.get_current_room_tick() if _timeline else 0

	# Trim future log entries from a previous forward pass (after reversal).
	while _state_log.size() > 0 and _state_log.back().tick > room_tick:
		_state_log.pop_back()

	var triggers_met: bool
	if trigger_nodes.is_empty():
		triggers_met = false
	elif require_all:
		triggers_met = true
		for t in trigger_nodes:
			if not t.activated:
				triggers_met = false
				break
	else:
		triggers_met = false
		for t in trigger_nodes:
			if t.activated:
				triggers_met = true
				break

	if triggers_met:
		_close_delay_counter = -1   # Cancel any pending close.
		if not is_open:
			is_open = true
			_state_log.append({tick = room_tick, open = true})
			_on_open_close(true)
	else:
		if is_open:
			if close_delay_ticks <= 0:
				# Instant close.
				is_open = false
				_close_delay_counter = -1
				_state_log.append({tick = room_tick, open = false})
				_on_open_close(false)
			else:
				# Start or continue countdown.
				if _close_delay_counter < 0:
					_close_delay_counter = close_delay_ticks
				_close_delay_counter -= 1
				if _close_delay_counter < 0:
					is_open = false
					_state_log.append({tick = room_tick, open = false})
					_on_open_close(false)


## Replay the correct open/close state for the current room_tick from the
## recorded forward-play history. Called instead of live evaluation during
## reverse play.
func _replay_state() -> void:
	if _timeline == null:
		return
	var room_tick: int = _timeline.get_current_room_tick()
	var target := _state_from_log(room_tick)
	if is_open != target:
		is_open = target
		_on_open_close(is_open)


## Look up the effective state at a given room_tick by scanning the log.
## Returns false (closed) if no transition has been recorded yet.
func _state_from_log(room_tick: int) -> bool:
	var result := false
	for entry in _state_log:
		if entry.tick <= room_tick:
			result = entry.open
		else:
			break
	return result


## Override in subclass for open/close behaviour.
func _on_open_close(_now_open: bool) -> void:
	pass


## Force the receiver back to closed state (used on level restart).
func force_close() -> void:
	is_open = false
	_close_delay_counter = -1
	_state_log.clear()
	_on_open_close(false)


## Draw yellow wiring lines from this receiver to each trigger node.
## Called from _draw() in subclasses so wiring is visible in the editor.
func _draw_trigger_wiring() -> void:
	for path in triggers:
		var node = get_node_or_null(path)
		if node and node is Node2D:
			var target_pos := to_local(node.global_position)
			draw_line(Vector2.ZERO, target_pos, Color(1.0, 0.8, 0.2, 0.3), 1.5)
			var d := 4.0
			draw_polygon(
				PackedVector2Array([
					target_pos + Vector2(0, -d), target_pos + Vector2(d, 0),
					target_pos + Vector2(0, d), target_pos + Vector2(-d, 0),
				]),
				PackedColorArray([Color(1.0, 0.8, 0.2, 0.4), Color(1.0, 0.8, 0.2, 0.4),
					Color(1.0, 0.8, 0.2, 0.4), Color(1.0, 0.8, 0.2, 0.4)])
			)


## Editor validation: warn about trigger wiring issues.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if triggers.is_empty():
		warnings.append("No triggers assigned. This receiver will never open.")
	else:
		for i in range(triggers.size()):
			var path: NodePath = triggers[i]
			if path.is_empty():
				warnings.append("Trigger slot %d has an empty path." % i)
			elif not get_node_or_null(path):
				warnings.append("Trigger path '%s' does not resolve to a node." % str(path))
	return warnings
