## ShowcaseReplayData — recorded scene state for the web replay viewer.
##
## Saved to res://data/web_showcase/core_time_play_replay.tres by the
## recorder during authoring, loaded by the replay viewer for playback.
## Contains presentation-only state (positions, visibility, mechanism
## states), no inputs.
class_name ShowcaseReplayData
extends Resource

@export var fps: int = 60
@export var duration: float = 0.0

## Each frame is a Dictionary with:
##   t: float, player_pos: Vector2, player_facing: int, player_anim: String,
##   player_visible: bool, echo_pos: Vector2, echo_facing: int,
##   echo_anim: String, echo_visible: bool, switch_a_pressed: bool,
##   switch_b_pressed: bool, door_open: bool, door_progress: float,
##   time_mode: String   # "forward" | "reverse" | "echo"
@export var frames: Array = []

## Each marker: { "t": float, "label": String }
@export var markers: Array = []
