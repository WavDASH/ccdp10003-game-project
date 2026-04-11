## RoomTickContext — per-room tick counter that advances while the player is present.
##
## global_tick is the master clock (never pauses).
## room_tick is derived — advances by time_direction only while the player is in this room.
## tick_history maps global_tick → room_tick for echo replay and mechanism queries.
class_name RoomTickContext
extends RefCounted

var room_id: String = ""
var room_tick: int = 0
var tick_history: Dictionary = {}   # int global_tick → int room_tick


## Called each _physics_process when the player is in this room.
func advance(p_global_tick: int, p_time_direction: int) -> void:
	tick_history[p_global_tick] = room_tick
	room_tick += p_time_direction


## Lookup room_tick for a historical global_tick (for echo replay / mechanism queries).
func room_tick_at(p_global_tick: int) -> int:
	return tick_history.get(p_global_tick, -1)


## Remove tick_history entries for global_ticks strictly before min_tick.
## Call periodically (e.g. after a branch is collapsed) to bound memory.
func trim_before(min_tick: int) -> void:
	var to_erase: Array = []
	for t in tick_history:
		if int(t) < min_tick:
			to_erase.append(t)
	for t in to_erase:
		tick_history.erase(t)


## Called on room restart (player death).
func reset() -> void:
	room_tick = 0
	tick_history.clear()
