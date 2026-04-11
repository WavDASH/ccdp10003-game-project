## BranchTrack — one continuous temporal pass of recorded player states.
##
## Stores frame data keyed by global tick.
## Tick ranges are inclusive: [start_tick, end_tick].
class_name BranchTrack
extends RefCounted

var frames: Dictionary = {}       # int tick -> Dictionary FrameState
var start_tick: int = 0           # first recorded tick (inclusive)
var end_tick: int = 0             # last recorded tick (inclusive)
var direction: int = 1            # +1 forward, -1 reverse (when recorded)
var generation: int = 0           # echo generation index (0, 1, 2, ...)
var sealed: bool = false          # true once recording has stopped
var collapsed: bool = false       # true if echo was invalidated


func record(tick: int, state: Dictionary) -> void:
	frames[tick] = state
	end_tick = tick


func has_tick(tick: int) -> bool:
	return frames.has(tick)


func get_frame(tick: int) -> Dictionary:
	return frames.get(tick, {})


func seal(pivot_tick: int) -> void:
	end_tick = pivot_tick
	sealed = true


func get_tick_range() -> Vector2i:
	return Vector2i(start_tick, end_tick)
