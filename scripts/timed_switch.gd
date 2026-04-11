## TimedSwitch — a switch that stays active for a duration after release.
##
## When an actor steps on the switch, it activates immediately.
## When the actor steps off, it stays active for hold_ticks physics frames
## before deactivating. This uses room_tick so reversal naturally "un-counts"
## the hold timer.
##
## Visual: brightens when active, dims when the hold timer expires.
@tool
class_name TimedSwitch
extends BaseMechanismTrigger

@export_group("Timed Switch")
@export var visual_size: Vector2 = Vector2(64, 12):
	set(value):
		visual_size = value
		entity_size = visual_size

@export_group("Timing")
## How many room_ticks the switch stays active after the actor leaves.
@export var hold_ticks: int = 120

@export_group("Switch Colors")
@export var unpressed_color: Color = Color(0.1, 0.5, 0.6, 1.0):
	set(value):
		unpressed_color = value
		if not activated:
			base_color = unpressed_color

@export var pressed_color: Color = Color(0.2, 1.0, 1.0, 1.0):
	set(value):
		pressed_color = value
		if activated:
			base_color = pressed_color

## Room_tick when the switch was last physically pressed (actor on top).
## -1 = never pressed.
var _last_pressed_tick: int = -1

## Whether an actor is currently standing on the switch this frame.
var _physically_pressed: bool = false


func _init() -> void:
	entity_size = Vector2(64, 12)
	base_color = Color(0.1, 0.5, 0.6, 1.0)


func _runtime_ready() -> void:
	add_to_group("switches")
	add_to_group("timed_switches")


## Called by TimelineManager each frame with the computed overlap state.
## For TimedSwitch, we override set_pressed to add hold-timer logic.
func set_pressed(value: bool) -> void:
	_physically_pressed = value
	# Actual activation state is computed in evaluate_hold() using room_tick.
	# We DON'T call super here — evaluate_hold() handles state transitions.


## Called by TimelineManager each frame with the current room_tick.
## Computes whether the switch should be active based on physical press
## state and the hold timer.
func evaluate_hold(room_tick: int) -> void:
	if _physically_pressed:
		_last_pressed_tick = room_tick

	var should_be_active := false
	if _physically_pressed:
		should_be_active = true
	elif _last_pressed_tick >= 0:
		var elapsed := room_tick - _last_pressed_tick
		should_be_active = elapsed >= 0 and elapsed < hold_ticks

	if activated != should_be_active:
		activated = should_be_active
		_on_state_change()
		state_changed.emit(activated)


func _on_state_change() -> void:
	base_color = pressed_color if activated else unpressed_color
