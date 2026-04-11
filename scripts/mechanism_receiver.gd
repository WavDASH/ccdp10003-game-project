## BaseMechanismReceiver — base class for elements that respond to triggers.
##
## Extends BasePlaceable with trigger evaluation logic.
## Subclass this for doors, moving platforms, laser emitters, etc.
## The TimelineManager calls evaluate_triggers() each frame.
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

## If true, once opened the receiver stays open until force_close().
@export var latching: bool = false

## Resolved trigger node references.
var trigger_nodes: Array = []

## Current state.
var is_open: bool = false


func _runtime_ready() -> void:
	call_deferred("_resolve_triggers")


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
func evaluate_triggers() -> void:
	if latching and is_open:
		return   # already latched open

	var new_state: bool
	if trigger_nodes.is_empty():
		new_state = false
	elif require_all:
		new_state = true
		for t in trigger_nodes:
			if not t.activated:
				new_state = false
				break
	else:
		new_state = false
		for t in trigger_nodes:
			if t.activated:
				new_state = true
				break

	if is_open != new_state:
		is_open = new_state
		_on_open_close(is_open)


## Override in subclass for open/close behaviour.
func _on_open_close(_now_open: bool) -> void:
	pass


## Force the receiver back to closed state (used on level restart).
func force_close() -> void:
	is_open = false
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
