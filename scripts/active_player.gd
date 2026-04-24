## ActivePlayer — Celeste-inspired player controller with state machine.
##
## Runs full CharacterBody2D physics. Records state every tick into the
## active branch via TimelineManager.record_frame(). Triggers reversal
## when R is pressed.
##
## Features: acceleration-based movement, variable jump height, coyote time,
## jump buffering, apex gravity, 8-direction dash, wall jump, corner correction.
## All movement is automatically echo-compatible because echoes replay position
## snapshots, not physics.
extends CharacterBody2D

const PlayerSpriteFramesScript = preload("res://scripts/player_sprite_frames.gd")

# ─── Movement state machine ─────────────────────────────────────────
enum State { NORMAL, DASH, WALL_JUMP_LOCK }

# ─── Tunable parameters ─────────────────────────────────────────────

@export_group("Horizontal Movement")
@export var max_speed: float = 300.0
## Acceleration when grounded with directional input (~5 frames to max).
@export var ground_accel: float = 3800.0
## Deceleration when grounded with no input (~4 frames to stop).
@export var ground_decel: float = 3600.0
## Acceleration when airborne with directional input.
@export var air_accel: float = 2800.0
## Deceleration when airborne with no input.
@export var air_decel: float = 1600.0
## Extra multiplier applied to accel when input opposes current velocity.
## Makes direction changes snap rather than skate.
@export var turn_accel_mult: float = 1.8

@export_group("Gravity")
## Base (ascent) gravity — how fast upward velocity decelerates.
@export var gravity: float = 1800.0
## Descent gravity multiplier — fall faster than rise for decisive drops.
@export var fall_gravity_mult: float = 1.6
## Terminal velocity — hard cap on downward speed (prevents runaway fall).
@export var max_fall_speed: float = 750.0
## Gravity multiplier near the apex of a jump (creates hang time contrast).
@export var apex_gravity_mult: float = 0.55
## Velocity threshold below which apex gravity kicks in.
@export var apex_velocity_threshold: float = 60.0

@export_group("Jump")
@export var jump_speed: float = 580.0
@export var coyote_frames: int = 6
@export var jump_buffer_frames: int = 6
## Upward velocity multiplier when jump is released early.
@export var jump_cut_multiplier: float = 0.3
## Pixels below the player to check for "near floor" edge grace.
## If the player is within this distance of a floor, coyote time still activates.
## Covers cases where the collision shape extends past a ledge visually.
@export var edge_jump_grace_pixels: int = 4

@export_group("Dash")
@export var dash_speed: float = 480.0
## Frames of forced velocity (no gravity, no input).
@export var dash_lock_frames: int = 6
## Total frames in dash state (lock + wind-down).
@export var dash_total_frames: int = 12

@export_group("Wall Jump")
@export var wall_jump_h_speed: float = 260.0
@export var wall_jump_v_speed: float = 490.0
## Frames of forced horizontal velocity after wall jump.
@export var wall_jump_lock_frames: int = 6
@export var wall_jump_refills_dash: bool = true
## Grace frames after leaving a wall during which wall jump is still allowed.
## Allows the player to release the wall direction and still jump away.
@export var wall_jump_grace_frames: int = 4

@export_group("Wall Slide")
## Maximum fall speed when sliding down a wall (pressing into it).
@export var wall_slide_max_fall_speed: float = 120.0

@export_group("Corner Correction")
## Maximum pixel nudge for corner correction.
@export var corner_correction_pixels: int = 6

# ─── External references ────────────────────────────────────────────
var timeline_manager = null   # set by main.gd
var facing: int = 1           # +1 right, -1 left

# ─── Internal state ─────────────────────────────────────────────────
var _state: State = State.NORMAL

## Input
var _input_dir_h: float = 0.0
var _input_dir_v: float = 0.0
var _last_pressed_h: int = 0

## Jump / coyote / buffer
var _coyote_counter: int = 0
var _jump_buffer_counter: int = 0
var _was_on_floor: bool = false
var _is_jumping: bool = false

## Dash
var _dash_available: bool = true
var _dash_timer: int = 0
var _dash_dir: Vector2 = Vector2.ZERO

## Wall jump
var _wall_jump_timer: int = 0
var _wall_contact_counter: int = 0
var _last_wall_normal: Vector2 = Vector2.ZERO

## Animation
var _sprite: AnimatedSprite2D = null

## Movement VFX emitter (replayable by echoes).
var _movement_effects: Node = null


# ═════════════════════════════════════════════════════════════════════
#  Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	process_physics_priority = 0   # run BEFORE TimelineManager
	_setup_animated_sprite()
	_setup_movement_effects()


func _setup_movement_effects() -> void:
	_movement_effects = Node.new()
	_movement_effects.name = "MovementEffects"
	_movement_effects.set_script(preload("res://scripts/movement_effects.gd"))
	_movement_effects.actor_tint = Color(1, 1, 1, 1)
	_movement_effects.sprite_frames = _sprite.sprite_frames if _sprite else null
	_movement_effects.use_monotonic_aging = true
	add_child(_movement_effects)


func _physics_process(delta: float) -> void:
	_update_input()
	_update_timers()

	match _state:
		State.NORMAL:
			_state_normal(delta)
		State.DASH:
			_state_dash(delta)
		State.WALL_JUMP_LOCK:
			_state_wall_jump_lock(delta)

	_post_movement()


## Resets all movement state. Called on level restart and room transitions.
func reset() -> void:
	_state = State.NORMAL
	velocity = Vector2.ZERO
	_dash_available = true
	_dash_timer = 0
	_dash_dir = Vector2.ZERO
	_wall_jump_timer = 0
	_coyote_counter = 0
	_jump_buffer_counter = 0
	_is_jumping = false
	_was_on_floor = false
	_input_dir_h = 0.0
	_input_dir_v = 0.0
	_last_pressed_h = 0
	_wall_contact_counter = 0
	_last_wall_normal = Vector2.ZERO
	# Clear all replayable VFX events so no dash trails from a
	# previous room leak into the current one.
	if _movement_effects and _movement_effects.has_method("reset"):
		_movement_effects.reset()


# ═════════════════════════════════════════════════════════════════════
#  Input
# ═════════════════════════════════════════════════════════════════════

func _update_input() -> void:
	# ── Horizontal: last-pressed priority ──
	if Input.is_action_just_pressed("move_right"):
		_last_pressed_h = 1
	if Input.is_action_just_pressed("move_left"):
		_last_pressed_h = -1

	var left_held := Input.is_action_pressed("move_left")
	var right_held := Input.is_action_pressed("move_right")

	if left_held and right_held:
		_input_dir_h = float(_last_pressed_h)
	elif right_held:
		_input_dir_h = 1.0
	elif left_held:
		_input_dir_h = -1.0
	else:
		_input_dir_h = 0.0

	# ── Vertical (for dash direction) ──
	var up_held := Input.is_action_pressed("move_up")
	var down_held := Input.is_action_pressed("move_down")
	if up_held and not down_held:
		_input_dir_v = -1.0
	elif down_held and not up_held:
		_input_dir_v = 1.0
	else:
		_input_dir_v = 0.0


func _update_timers() -> void:
	# ── Coyote time (with edge grace) ──
	var on_floor := is_on_floor()
	var near_floor := on_floor or _check_edge_grace()
	if near_floor:
		_coyote_counter = coyote_frames
	elif _was_on_floor and _coyote_counter > 0:
		_coyote_counter -= 1
	else:
		_coyote_counter = 0
	_was_on_floor = on_floor

	# ── Wall contact grace ──
	if is_on_wall():
		_wall_contact_counter = wall_jump_grace_frames
		_last_wall_normal = get_wall_normal()
	elif _wall_contact_counter > 0:
		_wall_contact_counter -= 1

	# ── Jump buffer ──
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_counter = jump_buffer_frames
	elif _jump_buffer_counter > 0:
		_jump_buffer_counter -= 1


# ═════════════════════════════════════════════════════════════════════
#  State: NORMAL (ground + air movement, jump, dash entry, wall jump)
# ═════════════════════════════════════════════════════════════════════

func _state_normal(delta: float) -> void:
	var on_floor := is_on_floor()

	# ── Dash refill on landing ──
	if on_floor:
		_dash_available = true

	# ── Gravity ──
	_apply_gravity(delta)

	# ── Jump (ground/coyote) ──
	var can_jump := on_floor or _coyote_counter > 0
	if _jump_buffer_counter > 0 and can_jump:
		_execute_ground_jump()
	# ── Wall jump (airborne near wall) ──
	elif _jump_buffer_counter > 0 and _can_wall_jump():
		_execute_wall_jump()
		return   # state changed to WALL_JUMP_LOCK

	# ── Variable jump height ──
	if _is_jumping and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier
		_is_jumping = false
	if velocity.y >= 0.0:
		_is_jumping = false

	# ── Horizontal movement ──
	_apply_horizontal_movement(delta)

	# ── Dash entry ──
	if Input.is_action_just_pressed("dash") and _dash_available:
		_enter_dash()
		return   # state changed to DASH

	# ── Corner correction + physics ──
	_corner_correct_vertical(delta)
	move_and_slide()


# ═════════════════════════════════════════════════════════════════════
#  State: DASH
# ═════════════════════════════════════════════════════════════════════

func _state_dash(delta: float) -> void:
	_dash_timer -= 1

	var in_lock := _dash_timer > (dash_total_frames - dash_lock_frames)

	if in_lock:
		# Lock phase: forced velocity, no gravity, no input.
		velocity = _dash_dir * dash_speed
	else:
		# Post-lock: gravity and input resume. Dash velocity decays naturally
		# through the acceleration system (move_toward toward max_speed).
		_apply_gravity(delta)
		_apply_horizontal_movement(delta)

	# ── Allow jump during dash ──
	var on_floor := is_on_floor()
	var can_jump := on_floor or _coyote_counter > 0
	if _jump_buffer_counter > 0 and can_jump:
		_execute_ground_jump()
		_state = State.NORMAL
		move_and_slide()
		return
	elif _jump_buffer_counter > 0 and _can_wall_jump():
		_execute_wall_jump()
		return

	# ── Corner correction + physics ──
	_corner_correct_vertical(delta)
	_corner_correct_horizontal(delta)
	move_and_slide()

	# ── Dash end ──
	if _dash_timer <= 0:
		# When dash ends, zero out vertical velocity if dashing horizontally
		# to prevent awkward post-dash fall acceleration.
		if abs(_dash_dir.y) < 0.1:
			velocity.y = 0.0
		# Clamp horizontal velocity to max_speed so dash doesn't leave
		# lingering inertia the player has to fight against.
		velocity.x = clampf(velocity.x, -max_speed, max_speed)
		_state = State.NORMAL

	# ── Landing refills dash ──
	if is_on_floor():
		_dash_available = true


# ═════════════════════════════════════════════════════════════════════
#  State: WALL_JUMP_LOCK
# ═════════════════════════════════════════════════════════════════════

func _state_wall_jump_lock(delta: float) -> void:
	_wall_jump_timer -= 1

	_apply_gravity(delta)

	# No horizontal input during lock — velocity is set by wall jump.

	# ── Allow dash during wall jump lock ──
	if Input.is_action_just_pressed("dash") and _dash_available:
		_enter_dash()
		return

	move_and_slide()

	if _wall_jump_timer <= 0:
		_state = State.NORMAL

	# ── Landing refills dash ──
	if is_on_floor():
		_dash_available = true


# ═════════════════════════════════════════════════════════════════════
#  Movement helpers
# ═════════════════════════════════════════════════════════════════════

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var grav := gravity
	# Apex gravity reduction: slightly lighter near the peak of a jump.
	if abs(velocity.y) < apex_velocity_threshold:
		grav *= apex_gravity_mult
	elif velocity.y > 0.0:
		# Descent: fall faster than rise.
		grav *= fall_gravity_mult

	# Wall slide friction: cap fall speed when pressing into a wall.
	var target_fall := max_fall_speed
	if is_on_wall() and velocity.y > 0.0 and _input_dir_h != 0.0:
		var wall_normal := get_wall_normal()
		if signf(_input_dir_h) != signf(wall_normal.x):
			target_fall = wall_slide_max_fall_speed
	velocity.y = move_toward(velocity.y, target_fall, grav * delta)


func _apply_horizontal_movement(delta: float) -> void:
	var on_floor := is_on_floor()
	if _input_dir_h != 0.0:
		facing = 1 if _input_dir_h > 0.0 else -1
		var target_vx := _input_dir_h * max_speed
		var accel := ground_accel if on_floor else air_accel
		# Turn boost: if input opposes current velocity, accelerate harder.
		if velocity.x != 0.0 and signf(velocity.x) != signf(_input_dir_h):
			accel *= turn_accel_mult
		velocity.x = move_toward(velocity.x, target_vx, accel * delta)
	else:
		var decel := ground_decel if on_floor else air_decel
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)


# ═════════════════════════════════════════════════════════════════════
#  Jump helpers
# ═════════════════════════════════════════════════════════════════════

func _execute_ground_jump() -> void:
	velocity.y = -jump_speed
	_jump_buffer_counter = 0
	_coyote_counter = 0
	_is_jumping = true


## Edge grace: if the player is within a few pixels of a floor below them,
## treat as "near floor" for coyote time activation. Catches cases where the
## collision shape extends past a ledge before the player visually looks airborne.
func _check_edge_grace() -> bool:
	if edge_jump_grace_pixels <= 0:
		return false
	return test_move(global_transform, Vector2(0, edge_jump_grace_pixels))


## Wall jump eligibility. Uses the grace counter so the player can release
## the wall direction (or never press it) and still wall jump within the
## grace window. No need to press INTO the wall at the moment of jumping.
func _can_wall_jump() -> bool:
	return not is_on_floor() and _wall_contact_counter > 0 and _state != State.DASH


func _execute_wall_jump() -> void:
	# Use cached wall normal from grace tracking — allows wall jump even
	# after releasing the wall direction.
	var wall_normal := _last_wall_normal
	if wall_normal == Vector2.ZERO:
		wall_normal = Vector2(-facing, 0)  # fallback: push away from facing
	velocity.x = wall_normal.x * wall_jump_h_speed
	velocity.y = -wall_jump_v_speed
	facing = 1 if wall_normal.x > 0 else -1
	_jump_buffer_counter = 0
	_coyote_counter = 0
	_wall_contact_counter = 0
	_is_jumping = true
	_wall_jump_timer = wall_jump_lock_frames
	_state = State.WALL_JUMP_LOCK
	if wall_jump_refills_dash:
		_dash_available = true


# ═════════════════════════════════════════════════════════════════════
#  Dash helpers
# ═════════════════════════════════════════════════════════════════════

func _enter_dash() -> void:
	_dash_dir = _resolve_dash_dir()
	_dash_timer = dash_total_frames
	_dash_available = false
	_is_jumping = false
	_coyote_counter = 0
	velocity = _dash_dir * dash_speed
	_state = State.DASH


func _resolve_dash_dir() -> Vector2:
	var dir := Vector2(_input_dir_h, _input_dir_v)
	# Celeste rule: grounded + holding only down → dash forward instead.
	if is_on_floor() and dir.y > 0 and dir.x == 0:
		dir = Vector2(facing, 0)
	# No directional input → dash in facing direction.
	if dir == Vector2.ZERO:
		dir = Vector2(facing, 0)
	return dir.normalized()


# ═════════════════════════════════════════════════════════════════════
#  Corner correction
# ═════════════════════════════════════════════════════════════════════

## Vertical corner correction: nudges horizontally when the player's head
## barely clips a ledge corner while jumping up.
func _corner_correct_vertical(delta: float) -> void:
	if velocity.y >= 0.0:
		return   # only when moving upward
	var motion := Vector2(velocity.x * delta, velocity.y * delta)
	if not test_move(global_transform, motion):
		return   # no collision — nothing to correct
	# Try horizontal nudges of 1..N pixels in both directions.
	for offset in range(1, corner_correction_pixels + 1):
		for sign_dir in [1, -1]:
			var shifted := global_transform
			shifted.origin.x += offset * sign_dir
			if not test_move(shifted, motion):
				global_position.x += offset * sign_dir
				return


## Horizontal corner correction: nudges vertically when dashing into a
## corner at high speed.
func _corner_correct_horizontal(delta: float) -> void:
	if abs(velocity.x) < 100.0:
		return   # only for fast horizontal movement (dash)
	var motion := Vector2(velocity.x * delta, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	for offset in range(1, corner_correction_pixels + 1):
		for sign_dir in [1, -1]:
			var shifted := global_transform
			shifted.origin.y += offset * sign_dir
			if not test_move(shifted, motion):
				global_position.y += offset * sign_dir
				return


# ═════════════════════════════════════════════════════════════════════
#  Post-movement (animation, recording, reversal)
# ═════════════════════════════════════════════════════════════════════

func _post_movement() -> void:
	_update_animation()

	# ── Generate + manage VFX ──
	var current_tick: int = timeline_manager.global_tick if timeline_manager else 0
	var vfx_events: Array = []
	if _movement_effects and _sprite:
		vfx_events = _movement_effects.generate_events({
			"position": global_position,
			"flip_h": _sprite.flip_h,
			"motion_state": int(_state),
			"anim_name": _sprite.animation,
			"anim_frame": _sprite.frame,
		}, current_tick)
		_movement_effects.update_tick(current_tick)

	# ── Record state (includes VFX events so echoes can replay them) ──
	if timeline_manager:
		var frame_data := {
			"position": global_position,
			"velocity": velocity,
			"facing": facing,
			"on_floor": is_on_floor(),
			"motion_state": int(_state),
		}
		if vfx_events.size() > 0:
			frame_data["vfx"] = vfx_events
		var animator = get_node_or_null("TimeAwareAnimator")
		if animator and animator.has_method("get_animation_state"):
			frame_data.merge(animator.get_animation_state())
		timeline_manager.record_frame(frame_data)

	# ── Reversal ──
	if Input.is_action_just_pressed("reverse") and timeline_manager:
		timeline_manager.reverse_time()


# ═════════════════════════════════════════════════════════════════════
#  Animation
# ═════════════════════════════════════════════════════════════════════

func _setup_animated_sprite() -> void:
	var old_visual = get_node_or_null("Visual")
	if old_visual:
		old_visual.queue_free()

	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Visual"
	_sprite.sprite_frames = PlayerSpriteFramesScript.create()
	_sprite.animation = "idle"
	_sprite.play()
	add_child(_sprite)
	move_child(_sprite, 1)

	# Tell the TimeAwareAnimator sibling to re-resolve its target now that
	# the real AnimatedSprite2D exists (its _ready() ran before us).
	var animator = get_node_or_null("TimeAwareAnimator")
	if animator and animator.has_method("refresh_target"):
		animator.refresh_target()


func _update_animation() -> void:
	if _sprite == null:
		return

	_sprite.flip_h = (facing < 0)

	var on_floor_now := is_on_floor()
	var target_anim: String

	if _state == State.DASH:
		target_anim = "dash"
	elif not on_floor_now:
		if is_on_wall() and velocity.y > 0.0 and _state == State.NORMAL:
			target_anim = "wall_slide"
		elif velocity.y < 0.0:
			target_anim = "jump"
		else:
			target_anim = "fall"
	elif abs(velocity.x) > 10.0:
		target_anim = "run"
	else:
		target_anim = "idle"

	if _sprite.animation != target_anim:
		_sprite.animation = target_anim
		_sprite.play()


# ═════════════════════════════════════════════════════════════════════
#  Debug
# ═════════════════════════════════════════════════════════════════════

func get_movement_debug() -> Dictionary:
	return {
		"state": State.keys()[_state],
		"dash_available": _dash_available,
		"dash_timer": _dash_timer,
		"coyote": _coyote_counter,
		"jump_buffer": _jump_buffer_counter,
		"input_h": _input_dir_h,
		"input_v": _input_dir_v,
		"on_wall": is_on_wall(),
		"wall_grace": _wall_contact_counter,
		"edge_grace": _check_edge_grace(),
		"vel_x": velocity.x,
		"vel_y": velocity.y,
	}
