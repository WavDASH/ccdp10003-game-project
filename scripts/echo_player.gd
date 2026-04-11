## EchoPlayer — semi-transparent replay puppet for a sealed branch.
##
## Does NOT run physics.  Each frame, TimelineManager sets its position
## from recorded data.  Has a collision shape so manual overlap queries
## can detect it (mechanism triggers, collapse checks).
##
## Color reflects playback direction relative to current time flow:
##   RED  = echo playing forward  (time_direction == branch.direction)
##   BLUE = echo playing backward (time_direction != branch.direction)
extends CharacterBody2D

const PlayerSpriteFramesScript = preload("res://scripts/player_sprite_frames.gd")

const COLOR_FORWARD := Color(0.92, 0.22, 0.18, 0.6)   # red — same direction
const COLOR_REVERSE := Color(0.18, 0.42, 0.92, 0.6)    # blue — opposite direction

var branch: BranchTrack = null
var timeline_manager = null
var is_collapsing: bool = false

var _collapse_timer: float = 0.0
const COLLAPSE_DURATION: float = 0.3

var _visual: Node = null
var _movement_effects: Node = null


func init(p_branch: BranchTrack, p_manager) -> void:
	branch = p_branch
	timeline_manager = p_manager


func _ready() -> void:
	_setup_animated_sprite()
	_setup_movement_effects()
	_update_tint()

	# Disable TimeAwareAnimator's own _physics_process on echoes.
	# Echo animation is driven entirely by apply_frame() → apply_animation_state()
	# with recorded data. The TAA's auto-playback (forward play / reverse frame
	# decrement) is redundant and fights with the recorded state.
	var animator = get_node_or_null("TimeAwareAnimator")
	if animator:
		animator.set_physics_process(false)


func _setup_movement_effects() -> void:
	_movement_effects = Node.new()
	_movement_effects.name = "MovementEffects"
	_movement_effects.set_script(preload("res://scripts/movement_effects.gd"))
	_movement_effects.actor_tint = Color(1, 1, 1, 1)
	if _visual is AnimatedSprite2D:
		_movement_effects.sprite_frames = (_visual as AnimatedSprite2D).sprite_frames
	add_child(_movement_effects)
	# Pre-load all VFX events from the sealed branch so that update_tick
	# can show afterimages at any tick within their lifespan.
	if branch:
		_movement_effects.load_events_from_branch(branch)


## Replaces the editor Polygon2D "Visual" with an AnimatedSprite2D at runtime.
func _setup_animated_sprite() -> void:
	var old_visual = get_node_or_null("Visual")
	if old_visual:
		old_visual.queue_free()

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Visual"
	sprite.sprite_frames = PlayerSpriteFramesScript.create()
	sprite.animation = "idle"
	add_child(sprite)
	move_child(sprite, 1)
	_visual = sprite

	# Tell the TimeAwareAnimator sibling to re-resolve its target now that
	# the real AnimatedSprite2D exists (its _ready() ran before us).
	var animator = get_node_or_null("TimeAwareAnimator")
	if animator and animator.has_method("refresh_target"):
		animator.refresh_target()


## Called by TimelineManager with the recorded frame for this tick.
func apply_frame(frame: Dictionary) -> void:
	global_position = frame.get("position", global_position)
	_update_tint()

	# Restore animation state if TimeAwareAnimator child exists.
	var animator = get_node_or_null("TimeAwareAnimator")
	if animator and animator.has_method("apply_animation_state"):
		animator.apply_animation_state(frame)

	# Update tick-driven VFX. The echo's MovementEffects was pre-loaded
	# with all historical VFX events at creation. update_tick computes
	# which afterimages are alive at the current tick and manages their
	# alpha deterministically — same formula works forward and reverse.
	if _movement_effects and timeline_manager:
		_movement_effects.actor_tint = _visual.self_modulate if _visual else Color(1, 1, 1, 1)
		_movement_effects.update_tick(timeline_manager.global_tick)


## Updates visual tint based on whether the echo is currently being
## replayed forward or backward relative to its recorded direction.
## Uses self_modulate (works on AnimatedSprite2D and Polygon2D alike).
func _update_tint() -> void:
	if _visual == null or timeline_manager == null or branch == null:
		return
	# Echo plays "forward" when current time_direction matches the
	# direction the branch was originally recorded in.
	if timeline_manager.time_direction == branch.direction:
		_visual.self_modulate = COLOR_FORWARD
	else:
		_visual.self_modulate = COLOR_REVERSE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not visible and _movement_effects:
			_movement_effects.clear_ghosts()


func start_collapse() -> void:
	is_collapsing = true
	_collapse_timer = 0.0


func _process(delta: float) -> void:
	if is_collapsing:
		_collapse_timer += delta
		if _visual:
			_visual.visible = fmod(_collapse_timer * 20.0, 2.0) > 1.0
		if _collapse_timer >= COLLAPSE_DURATION:
			queue_free()
