## TimeScheduledReceiver — a receiver that opens/closes based on room_tick schedule.
##
## Unlike trigger-driven receivers, this one ignores triggers entirely. Its
## state is determined by whether the current room_tick falls within any of the
## configured time windows.
##
## Reversal behavior: when time reverses, room_tick decrements and the schedule
## evaluates in reverse — a door that opened at tick 60 "un-opens" when
## room_tick drops below 60.
@tool
class_name TimeScheduledReceiver
extends BaseMechanismReceiver

@export_group("Schedule")
## Each Vector2i = one time window: (open_room_tick, close_room_tick).
## The receiver is open when room_tick falls within ANY window.
## Example: [(60, 120)] means open from tick 60 to 119 (inclusive start, exclusive end).
@export var schedule: Array[Vector2i] = []

## -1 = no loop. >0 = schedule repeats every N room_ticks.
## Example: loop_period=120 with schedule [(30, 60)] means open for ticks 30-59
## in each 120-tick cycle.
@export var loop_period: int = -1


func _runtime_ready() -> void:
	add_to_group("scheduled_receivers")


## Editor validation: warn about schedule issues.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if schedule.is_empty():
		warnings.append("Schedule is empty. This receiver will never open.")
	else:
		for i in range(schedule.size()):
			var w: Vector2i = schedule[i]
			if w.x >= w.y:
				warnings.append("Schedule window %d (%d, %d) has open_tick >= close_tick." % [i, w.x, w.y])
	return warnings


## Called by TimelineManager each frame with the current room_tick.
func evaluate_schedule(room_tick: int) -> void:
	# Negative room_ticks (reversed past entry point) — nothing should be open.
	if room_tick < 0:
		if is_open:
			is_open = false
			_on_open_close(false)
		return

	var effective_tick := room_tick
	if loop_period > 0:
		effective_tick = room_tick % loop_period

	var should_be_open := false
	for window in schedule:
		if effective_tick >= window.x and effective_tick < window.y:
			should_be_open = true
			break

	if is_open != should_be_open:
		is_open = should_be_open
		_on_open_close(is_open)
