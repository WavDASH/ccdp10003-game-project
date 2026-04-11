# IMPLEMENTATION_NOTES.md

Technical notes on design decisions made during the build.

---

## Pivot-Tick Semantics

When the player presses **R**, the following happens in a single physics frame:

1. The active player has **already** run `move_and_slide()` and called `timeline_manager.record_frame()` at the current `global_tick`.
2. `reverse_time()` is called:
   - The active branch is **sealed** at `global_tick` (inclusive — it has data for that tick).
   - `time_direction` is flipped (`*= -1`).
   - A new branch is created starting at `global_tick`. The pivot frame is **copied** into the new branch so both branches share data at the pivot tick.
   - An `EchoPlayer` is spawned for the sealed branch.
3. Later in the same frame, `TimelineManager._physics_process()` runs:
   - `_update_echoes()` positions the new echo at the pivot tick (same position as the player).
   - `_advance_tick()` moves the tick by `time_direction` — **the direction is already flipped**, so the tick immediately moves in the new direction.

**There is no special "pivot frame skip."** The tick advances every frame. On the reversal frame, the direction has already changed, so the advance goes in the correct new direction. This avoids the complexity of an `is_pivot_frame` flag.

**Branch ranges are `[start_tick, end_tick]` inclusive.** Both the sealed branch and the new branch contain data at the pivot tick.

---

## Echo Detection: Manual Overlap Queries

All echo-related detection uses **manual physics overlap queries** (`PhysicsDirectSpaceState2D.intersect_shape`) or **direct Rect2 intersection checks**. We never rely on `Area2D` body_entered/body_exited signals for echoes, because echoes teleport to recorded positions each frame and signals may not fire reliably for teleporting bodies.

### What uses physics queries (intersect_shape)
- **Echo collapse: geometry check** — queries the echo's (shrunk) collision shape against Layers 1+2 (World + Door). Uses the echo's `global_transform` which contains its current position.

### What uses manual Rect2 checks
- **Echo collapse: hazard check** — compares echo rect against registered hazard rects.
- **Mechanism trigger activation** — compares actor rect (player or echo) against trigger zone rect.
- **Player hazard detection** — compares player rect against hazard rects.
- **Goal zone detection** — compares player rect against goal rect.

### Why this split
The physics query for geometry overlap is necessary because static geometry (walls, doors) lives in the physics server and its state changes dynamically (doors open/close). Rect2 checks are simpler and avoid any physics-server sync concerns for stationary elements like hazard zones and trigger areas whose positions are fixed.

---

## Collision Layer Map

| Bit | Layer # | Name | Used by |
|-----|---------|------|---------|
| 1   | 1       | World | Static geometry: floors, walls, platforms, ceiling |
| 2   | 2       | Door  | Door StaticBody2D (separate so collapse queries can distinguish) |
| 4   | 3       | ActivePlayer | The one controlled character |
| 8   | 4       | Hazard | Spike pits, lethal zones (detected by manual query, not physics) |
| 16  | 5       | MechanismTrigger | Switch zones (detected by Rect2 check, not physics) |
| 32  | 6       | Echo | Echo replay instances |

**Active player** (CharacterBody2D): layer=4, mask=3 (collides with World + Door via `move_and_slide`).
**Echo** (CharacterBody2D): layer=32, mask=0 (no physics — teleported to recorded positions).

Door is on its own layer (not merged with World) so that:
- Collapse queries can distinguish "inside a wall" from "inside a closed door"
- Future mechanics can treat doors differently from static geometry

---

## Reverse-Mode Interaction Rule

**Rule:** While the active player is reversing time (`time_direction == -1`), they are a **non-interactive temporal traversal entity**. They cannot participate in any gameplay interaction. Reverse mode is for repositioning through time, not for affecting puzzle state.

**Canonical gate:** `TimelineManager.is_player_interactable()` — returns `true` only when `time_direction == 1`. Every system that checks whether the active player activates, triggers, overlaps, or interacts with a gameplay element MUST call this first.

### Semantic Split: Terrain/Physics vs Gameplay/Mechanism

This is the fundamental distinction that governs what the reverse-mode player can and cannot do.

**Terrain/Physics interactions — ALWAYS ACTIVE:**

These use Godot's physics engine (`CharacterBody2D.move_and_slide` against collision layers 1+2). No gating needed.

| Element | Collision type | Why it's terrain |
|---|---|---|
| Floors, walls, ceiling (TerrainBlock) | StaticBody2D, layer 1 | Structural geometry |
| Moving platforms (MovingPlatform) | AnimatableBody2D, layer 1 | Carries player via physics |
| One-way platforms (TerrainBlock) | StaticBody2D, layer 1 | Structural geometry |
| CrumbleBlock (standing on) | StaticBody2D, layer 1 | Structural geometry |
| Doors (closed state) | StaticBody2D, layer 2 | Blocking body |

**Always-active interactions (work in both forward and reverse):**

| System | Why always active | Where |
|---|---|---|
| Floors, walls, ceiling | Physics collision (layer 1) | `move_and_slide()` |
| Moving platforms | Physics collision (layer 1) | `move_and_slide()` |
| One-way platforms | Physics collision (layer 1) | `move_and_slide()` |
| CrumbleBlock (standing on) | Physics collision (layer 1) | `move_and_slide()` |
| Doors (closed state) | Physics collision (layer 2) | `move_and_slide()` |
| **Hazard death** | **Direct overlap check, NOT gated** | `TimelineManager._check_player_hazard()` |

**Mechanism/Puzzle interactions — GATED (excluded in reverse):**

These use manual Rect2 overlap checks. All gated by `is_player_interactable()`.

| System | What is gated | Where |
|---|---|---|
| Switch activation | Player can't press switches | `TimelineManager._update_mechanisms()` |
| Goal completion | Player can't complete level | `TimelineManager._check_goal()` |
| Room exit transitions | Player can't change rooms | `RoomManager._check_exits()` |
| CrumbleBlock trigger | Player can't start crumble timer | `CrumbleBlock._is_actor_on_top()` |

### What always works regardless of direction

- Frame recording and branch management (always records)
- Echo interactions (echoes follow their own rules, unaffected)
- Reversal input (player can always press R again)
- **Hazard death** (player can die while reversing)

### Transitive correctness

Systems like MovingPlatform don't directly check the player — they read trigger state (e.g. `switch.activated`). Since the reverse player can't activate switches, these systems are transitively correct without their own gate.

**For new systems:** If you add any system that checks `active_player.global_position` for puzzle/mechanism purposes, you MUST gate it behind `is_player_interactable()`. Physics collision and hazard death are the exceptions — those are always active.

---

## Mechanism Framework

`MechanismTrigger` and `MechanismReceiver` are base classes designed for extension:

- **Trigger** (`mechanism_trigger.gd`): Has a rectangular zone. TimelineManager queries actor overlap each frame and calls `set_pressed()`. Override `_on_state_change()` for visual feedback.
- **Receiver** (`mechanism_receiver.gd`): References one or more triggers. Supports `require_all` (AND) or any (OR) logic. Supports `latching` (stays open once triggered). Override `_on_state_change()` for behaviour.

MVP implements `SwitchTrigger` (pressure plate) and `DoorReceiver` (blocking gate). Future types (timed switches, moving platforms, laser emitters) subclass the same base.

---

## Echo Validation Pipeline

`_validate_echo_at_tick()` in TimelineManager runs every frame for each visible echo. It returns a `CollapseReason` enum value.

**Implemented checks:**
1. Geometry overlap (World + Door layers) — 2px tolerance margin, using a cached `RectangleShape2D` (avoids per-frame allocation)
2. Hazard overlap (Rect2 check against registered hazard rects)

**Reserved slots (not yet implemented):**
3. Ground loss — would cast a ray downward from echo feet
4. Custom — hook point for per-level scripts

Collapse is **permanent** for a branch. Once collapsed, the echo plays a flicker animation and is freed.

---

## Configurable Limit Hooks

`TimelineManager` currently exposes one limit:
- `reversal_cooldown_ticks: int = 15` — minimum ticks between reversals, checked by `can_reverse()`

**Planned but not yet implemented:**
- `max_reversals` — cap on total reversals per level
- `max_rewind_duration` — cap on how far back the player can rewind
- `max_active_echoes` — cap on simultaneous visible echoes

These would be `@export` vars set per-level in the editor.

---

## Level Architecture

Levels are built as **room scenes** in `scenes/rooms/`. Each room is a standalone `.tscn` file loaded by `RoomManager`. `main.gd` creates the player, echo container, HUD, screen FX, and wires subsystems — but level content lives in room scenes.

**Key `.tscn` files:**
- `scenes/main.tscn` — Root Node2D with `main.gd` + `TimelineManager` child
- `scenes/player.tscn` — CharacterBody2D + CollisionShape2D + Visual + TimeAwareAnimator + Camera2D
- `scenes/echo_player.tscn` — CharacterBody2D + CollisionShape2D + Visual + TimeAwareAnimator
- `scenes/rooms/room_01.tscn`, `room_02.tscn` — Room scenes with geometry, mechanisms, spawns, exits
- `scenes/rooms/room_template.tscn` — Starter room template (duplicate to create new rooms)
- `scenes/*.tscn` — Reusable component scenes (switch, door, hazard, etc.)
- `templates/*.tscn` — Starting-point templates for creating new entity types

---

## Editor Component Reference — Inspector Properties

Every reusable component uses @tool scripts for WYSIWYG editing. This section documents **which property to edit** for each component type.

### Common: resize_anchor (all resizable components)

All size-bearing components (BasePlaceable subclasses and TerrainBlock) expose a `resize_anchor` enum. Set it **before** changing the size to control which edge stays fixed:

| Value | Behavior |
|-------|----------|
| CENTER (default) | Size grows equally in all directions |
| TOP_LEFT | Top-left corner stays pinned |
| LEFT | Left edge stays pinned (vertical center unchanged) |
| BOTTOM | Bottom edge stays pinned (horizontal center unchanged) |
| ... | 9 options total: CENTER + 4 edges + 4 corners |

**Workflow:** Select a node → set `resize_anchor` → change the size property → position auto-adjusts.

---

### TerrainBlock (floors, walls, platforms)

**Scene:** `scenes/terrain_block.tscn` | **Script:** `scripts/terrain_block.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `block_size` | Width × height of collision + visual | **Primary size control** — edit this |
| `resize_anchor` | Which edge stays fixed when resizing | Set to LEFT/BOTTOM before growing a wall/floor |
| `block_color` | Fill color (or texture tint) | Change for visual variety |
| `block_texture` | Tiles across the block; set `block_color` to WHITE for full brightness | Art replacement |
| `block_material` | ShaderMaterial override | Advanced visuals |
| `one_way` | One-way collision (player can jump through from below) | Drop-through platforms |

**Do NOT edit:** `CollisionShape2D` or `Visual` children directly — they are synced from `block_size`.

---

### SwitchTrigger (pressure plate)

**Scene:** `scenes/switch.tscn` | **Script:** `scripts/switch_trigger.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `visual_size` | Width × height of the visible plate | **Primary size control** |
| `trigger_size` | Width × height of the invisible detection zone | Make wider than visual for forgiving activation |
| `unpressed_color` | Color when not pressed | |
| `pressed_color` | Color when an actor stands on it | |

**Note:** `trigger_size` and `visual_size` are independent. When they differ, a dashed cyan outline shows the trigger zone in the editor.

---

### DoorReceiver (trigger-driven door)

**Scene:** `scenes/door.tscn` | **Script:** `scripts/door_receiver.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `door_size` | Width × height of collision + visual | **Primary size control** |
| `closed_color` | Opaque color when closed | |
| `open_color` | Faded color when open (alpha ~0.1) | |
| `triggers` | Array of NodePaths to trigger nodes | Wire to SwitchTrigger(s) |
| `require_all` | true = AND logic, false = OR logic | Multi-switch puzzles |
| `latching` | Once opened, stays open permanently | One-time gates |

---

### TimeScheduledDoor (time-driven door)

**Scene:** `scenes/time_scheduled_door.tscn` | **Script:** `scripts/time_scheduled_door.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `door_size` | Width × height of collision + visual | **Primary size control** |
| `schedule` | Array of Vector2i: each (open_tick, close_tick) in room-local ticks | `[(0, 60)]` = open ticks 0-59 |
| `loop_period` | -1 = no loop, >0 = schedule repeats every N room_ticks | `120` = 2-second cycle at 60fps |
| `closed_color` | Opaque purple when closed | |
| `open_color` | Faded purple when open | |

**Does NOT use triggers.** Driven entirely by room_tick schedule.

---

### Hazard (kill zone)

**Scene:** `scenes/hazard.tscn` | **Script:** `scripts/hazard.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `hazard_size` | Width × height of the kill zone | **Primary size control** |
| `base_color` | Red fill color | |

---

### GoalZone (level exit)

**Scene:** `scenes/goal_zone.tscn` | **Script:** `scripts/goal_zone.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `zone_size` | Width × height of the goal area | **Primary size control** |
| `base_color` | Yellow/transparent fill | |

---

### RoomExit (room transition trigger)

**Scene:** `scenes/room_exit.tscn` | **Script:** `scripts/room_exit.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `exit_size` | Width × height of the detection zone | **Primary size control** |
| `target_room` | Room ID to load (e.g. `"room_02"`) | Must match main.gd room registry |
| `target_entry` | Entry point name in target room (e.g. `"left"`) | Matches Marker2D name suffix |
| `exit_direction` | Which edge: `"left"`, `"right"`, `"up"`, `"down"` | Used by RoomManager for positioning |

---

### TimedSwitch (hold-timer pressure plate)

**Scene:** `scenes/timed_switch.tscn` | **Script:** `scripts/timed_switch.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `visual_size` | Width × height of the visible plate | **Primary size control** |
| `trigger_size` | Width × height of the invisible detection zone | Inherited from BaseMechanismTrigger |
| `hold_ticks` | Room_ticks the switch stays active after actor leaves | 60 = 1 second at 60fps |
| `unpressed_color` | Cyan color when idle | |
| `pressed_color` | Bright cyan when active | |

---

### MovingPlatform (trigger-driven elevator)

**Scene:** `scenes/moving_platform.tscn` | **Script:** `scripts/moving_platform.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `platform_size` | Width × height of collision + visual | **Primary size control** |
| `point_b` | End position relative to placed position | `(0, -200)` = moves 200px up |
| `move_speed` | Pixels per second | |
| `platform_color` | Green fill color | |
| `triggers` | Array of NodePaths to trigger nodes | Wire to switch(es) |
| `require_all` | AND vs OR logic for multiple triggers | |

**Editor:** A green line + ghost rectangle shows the travel path to `point_b`.

---

### CrumbleBlock (breakable platform)

**Scene:** `scenes/crumble_block.tscn` | **Script:** `scripts/crumble_block.gd`

| Property | What it does | Typical use |
|----------|-------------|-------------|
| `block_size` | Width × height (inherited from TerrainBlock) | **Primary size control** |
| `crumble_delay_ticks` | Ticks after stepping on before it breaks | 30 = 0.5s |
| `respawn_delay_ticks` | Ticks after breaking before reappearing (-1 = never) | 180 = 3s |
| `crumble_color` | Normal color (brownish) | |
| `warning_color` | Flash color during crumble countdown | |

**Flashes** between `crumble_color` and `warning_color` during countdown, then fades to near-transparent when broken. Respects reverse-mode rule: reverse player doesn't trigger crumble.

---

### General rules

1. **Edit the component's own size property** (`block_size`, `door_size`, `hazard_size`, etc.) — never resize children manually.
2. **entity_size / base_color** are inherited plumbing. Subclass properties (like `door_size`) drive them automatically.
3. **Visual child** is a Polygon2D placeholder. Replace it with Sprite2D / AnimatedSprite2D / NinePatchRect for real art — the script won't touch non-Polygon2D visuals.
4. **Set resize_anchor before changing size** if you want a specific edge pinned.

---

## Movement System

### State Machine

`ActivePlayer` uses a 3-state machine for movement:

| State | Behavior |
|---|---|
| `NORMAL` | Standard ground/air movement, jump, wall jump entry, dash entry |
| `DASH` | Forced velocity for `dash_lock_frames`, then wind-down with gravity/input |
| `WALL_JUMP_LOCK` | Brief forced horizontal velocity away from wall, then return to NORMAL |

### Physics Process Order (within ActivePlayer)

1. `_update_input()` — resolve horizontal priority (last-pressed wins), vertical direction
2. `_update_timers()` — coyote time (with edge grace), wall contact grace, jump buffer countdown
3. State dispatch (`_state_normal`, `_state_dash`, `_state_wall_jump_lock`)
4. `_post_movement()` — animation update, frame recording, reversal input

### Horizontal Movement

Acceleration-based, not instant. Parameters differ for ground vs air:

| Parameter | Default | Purpose |
|---|---|---|
| `ground_accel` | 1800 | Reach max_speed in ~9 frames |
| `ground_decel` | 2600 | Stop in ~6 frames |
| `air_accel` | 1200 | Slower air control |
| `air_decel` | 800 | Minimal air friction |

When velocity exceeds `max_speed` (e.g. after dash), `move_toward` naturally decays it back, creating Celeste-like momentum curves.

### Horizontal Input Priority

When both left and right are held, the most recently pressed key wins. On release, the still-held opposite direction takes over immediately.

### Jump System

- **Coyote time** (6 frames): can still jump after walking off a ledge
- **Edge grace** (`edge_jump_grace_pixels` = 4): uses `test_move()` to check if the player is within a few pixels of a floor below them, even when `is_on_floor()` is false. Activates coyote time for ledge-adjacent jumps where the collision shape extends past the platform visually. This is a spatial extension to coyote time's temporal grace.
- **Jump buffer** (6 frames): buffered jump input before landing
- **Variable height**: releasing jump early multiplies upward velocity by 0.4
- **Apex gravity**: gravity reduced by 50% when `abs(velocity.y) < 80` (creates hang time)
- **Terminal velocity**: max fall speed capped at 600 px/s

### Eight-Direction Dash

- 8 directions from normalized input vector
- On ground + holding only down → dashes forward (Celeste rule)
- No input → dashes in facing direction
- One dash per airborne period, refills on landing
- Lock phase (`dash_lock_frames` = 6): forced velocity, no gravity, no input
- Post-lock: gravity/input resume, velocity retained and decays naturally
- Jumping during dash preserves current horizontal momentum (no special boost)

### Wall Jump

- **Wall contact grace** (`wall_jump_grace_frames` = 4): after leaving a wall, wall jump remains available for a grace window. The last contacted wall normal is cached. This means the player can touch a wall, release the direction (or never press it), and still wall jump within the grace window.
- Uses cached `_last_wall_normal` for jump direction — always pushes away from the last contacted wall, even if the player is no longer pressing into it
- Fallback: if no wall normal is cached, pushes away from `facing` direction
- Brief lock period (6 frames) prevents immediate re-grab
- Refills dash by default (`wall_jump_refills_dash` export)
- Priority: ground/coyote jump > wall jump
- Wall contact counter is consumed on wall jump (reset to 0) to prevent double-jumps

### Wall Slide

When the player is airborne, falling, and pressing into a wall, fall speed is capped at `wall_slide_max_fall_speed` (default 120 px/s) instead of `max_fall_speed` (900 px/s). This creates a slow slide down walls, giving the player time to decide whether to wall jump.

- Detection: `is_on_wall() and velocity.y > 0 and input direction opposes wall normal`
- Implemented inside `_apply_gravity()` by selecting a lower `target_fall` before `move_toward()`
- No separate state — wall slide is a modifier within NORMAL state gravity
- Works correctly with wall jump: pressing into wall triggers slide, then jump input triggers wall jump
- Echo-compatible: the reduced fall speed produces different positions recorded in frame data; echoes replay them

### Corner Correction

- **Vertical**: when jumping up and head clips a corner, nudges horizontally (up to 6px)
- **Horizontal**: when dashing into a corner, nudges vertically (up to 6px)
- Uses `test_move()` with shifted transforms — deterministic
- Runs before `move_and_slide()`; corrections captured in recorded position

### Reverse-Time Compatibility

All movement features work identically during reverse mode. Echoes replay position snapshots, not physics, so all movement improvements are automatically echo-compatible:

- Frame data format unchanged: `{position, velocity, facing, on_floor}` + animation state
- New animation names ("dash", "wall_slide") captured by existing `TimeAwareAnimator.get_animation_state()`
- No changes to `echo_player.gd`, `branch_track.gd`, or `time_aware_animator.gd`
- Corner corrections are captured in the final recorded position
- Dash/wall jump state is internal to the player — echoes don't need it

### reset() Method

Called on level restart and room transitions. Resets all movement state:
- State → NORMAL, velocity → zero
- Dash available → true, all timers → 0
- Coyote/buffer counters → 0
- Wall contact grace counter → 0, cached wall normal → zero
- Input tracking → zeroed

---

## Process Priority

- **ActivePlayer**: `process_physics_priority = 0` (runs first — input, movement, recording, reversal)
- **TimelineManager**: `process_physics_priority = 1` (runs second — echo update, mechanism query, hazard check, tick advance)

This ensures the player's state is recorded before the TimelineManager reads it, and echoes are updated at the same tick the player just recorded.

---

## Time-Aware Animation System

`TimeAwareAnimator` is a **component node** (child, not base class) that handles direction-aware animation playback. Any entity opts in by adding a TimeAwareAnimator child as a sibling to an AnimatedSprite2D or AnimationPlayer.

### How it works

Each `_physics_process`, the animator reads `time_direction` from TimelineManager:
- **Forward (+1):** AnimatedSprite2D plays normally; AnimationPlayer `speed_scale = 1`
- **Reverse (-1):** AnimatedSprite2D frames are manually decremented; AnimationPlayer `speed_scale = -1`

The manual frame decrement for AnimatedSprite2D uses a time accumulator (`_manual_frame_time`) that respects the animation's FPS setting. The accumulator resets when the animation name changes to prevent glitches during animation transitions.

### State recording for echo replay

- `get_animation_state() -> Dictionary` — captures `{anim_name, anim_frame, anim_flip_h}` (AnimatedSprite2D) or `{anim_name, anim_progress}` (AnimationPlayer)
- `apply_animation_state(state: Dictionary)` — restores exact state from recorded frame data
- ActivePlayer merges animation state into every recorded frame via `frame_data.merge(animator.get_animation_state())`
- EchoPlayer calls `animator.apply_animation_state(frame)` in `apply_frame()` for frame-accurate replay

### Player/Echo animation

Both `player.tscn` and `echo_player.tscn` have a TimeAwareAnimator child. At runtime, the Polygon2D placeholder Visual is replaced with an AnimatedSprite2D using programmatic SpriteFrames (idle, run, jump, fall, dash, wall_slide). The animation state machine in `active_player.gd` selects animations based on movement state.

### Mechanism animation

Mechanisms can also use TimeAwareAnimator. Mechanism animation state is NOT recorded in branch frame data — mechanism state is deterministic from trigger/schedule inputs. TimeAwareAnimator on mechanisms only handles direction-aware playback speed.

Example: GoalZone creates an AnimationPlayer + TimeAwareAnimator at runtime for a pulsing visual effect that reverses with time direction.

### Target detection

TimeAwareAnimator auto-detects the first `AnimatedSprite2D` or `AnimationPlayer` among its siblings. Override with `target_node_path` export for manual control. Timeline reference is found via `/root/Main/TimelineManager` path or `"timeline_manager"` group fallback.

Because Godot fires `_ready()` on children before parents, and both the player and echo replace their placeholder Polygon2D with an `AnimatedSprite2D` in the parent's `_ready()`, the animator's initial `_find_target()` sees only the placeholder and sets `_target = null`. Two countermeasures make this robust:
1. After installing the AnimatedSprite2D, the parent calls `animator.refresh_target()`.
2. `get_animation_state()`, `apply_animation_state()`, and `_physics_process()` each run `_ensure_target()` which re-runs `_find_target()` if `_target` is null or no longer valid.

---

## Movement Presentation Effects (Replayable VFX)

Movement VFX — dash afterimages, future jump/landing/wall-jump bursts — are driven by **MovementEffects** ([scripts/movement_effects.gd](scripts/movement_effects.gd)). Both ActivePlayer and EchoPlayer attach one programmatically.

### Core principle: VFX as temporal objects

VFX events are **temporal objects with a tick lifespan**, not one-shot cosmetic spawns. Each effect exists for a deterministic range of ticks `[spawn_tick, spawn_tick + lifetime]`. At any tick within that range, the effect's alpha is:

```
alpha = start_alpha × (1.0 − age / lifetime)
where age = current_tick − spawn_tick
```

This single formula produces correct visuals in both time directions:
- **Forward:** `current_tick` increases → `age` increases → alpha decreases → afterimage fades out.
- **Reverse:** `current_tick` decreases → `age` decreases → alpha increases → afterimage brightens. When `current_tick` drops below `spawn_tick`, `age < 0`, and the afterimage disappears (it hadn't been spawned yet in forward time).

No special-case code for reverse presentation. The same `update_tick(current_tick)` call manages ghosts identically in both directions.

### What reverse looks like visually

Forward dash presentation:
1. Player starts dash, moves outward along the path.
2. Afterimages appear behind the player, then fade out over ~18 ticks.
3. Player reaches destination; trail fades to nothing.

Reverse (rewinding the above):
1. The still-fading afterimages are **already visible** as the rewind begins (because in forward time they hadn't fully faded yet at the end of the dash).
2. The echo moves backward along the same path.
3. As the echo rewinds past each afterimage's spawn tick, that afterimage **brightens to full alpha** then **vanishes** (it didn't exist before its spawn tick).
4. The echo returns to the original dash starting point with no trail remaining.

The visual reads as "the original dash presentation being rewound," not "a new dash in the opposite direction."

### Aging modes: monotonic vs global

The `age` of a VFX event determines its alpha. Two aging modes exist:

| Mode | Who uses it | How age is computed |
|---|---|---|
| **Monotonic** (`use_monotonic_aging = true`) | Live player | `age = _mono_tick − event._mono_spawn`. `_mono_tick` increments +1 every `update_tick` call regardless of game time direction. |
| **Global** (`use_monotonic_aging = false`) | Echoes | `age = external_tick − event.tick`. Uses the `global_tick` passed to `update_tick`. |

**Why the live player needs monotonic aging:** In reverse mode, `global_tick` decreases. If the live player generates a dash trail at `global_tick = 100` and then `global_tick` drops to 99, the global-aging formula gives `age = 99 − 100 = −1`, which is out of range — the ghost disappears immediately. Monotonic aging ensures the live player's own effects always fade forward in real time, even when the game clock runs backward.

Echoes use global aging because their VFX events are pre-loaded from the sealed branch. The global tick determines which events should be visible, and the age formula correctly shows/hides them when traversing the timeline in either direction.

### Pipeline

**Live player** — each tick in `_post_movement()`:
1. `generate_events(state, current_tick)` — applies trigger rules, returns event dicts, registers them internally. In monotonic mode, events are tagged with `_mono_spawn` (the internal counter at spawn time).
2. Events are stored in `frame_data["vfx"]` for the recording.
3. `update_tick(current_tick)` — increments `_mono_tick` (monotonic mode), then creates/updates/removes ghost Sprite2D nodes for all events whose lifespan overlaps the current tick.

**Echoes** — at creation + each `apply_frame()`:
1. At creation: `load_events_from_branch(branch)` — scans the sealed branch's entire frame history and pre-loads all VFX events with their tick numbers.
2. Each tick: `update_tick(timeline_manager.global_tick)` — same ghost management as the live player. Because all events are pre-loaded, ghosts appear/disappear at the correct ticks regardless of traversal direction.

### Ghost lifecycle

Ghosts are Sprite2D children of the MovementEffects node with `top_level = true`, so they:
- Render in world space (fixed position, not following the actor).
- Are automatically freed when the actor is freed (no manual cleanup).
- **Do NOT inherit parent visibility.** When an echo is hidden (outside its tick range), `top_level` ghosts remain visible. The echo's `_notification(NOTIFICATION_VISIBILITY_CHANGED)` handler calls `_movement_effects.clear_ghosts()` to explicitly remove them.

Each tick, `update_tick` iterates all known events:
- If `0 ≤ age ≤ lifetime`: create ghost if missing, update alpha if present.
- Otherwise: remove ghost if present.

`clear_ghosts()` immediately frees all active ghost sprites and empties the pool. This is called when an echo goes out of its tick range and is hidden by `TimelineManager._update_echoes()`.

### Recording format

Frame data carries two VFX-related fields:

| Field | Type | Purpose |
|---|---|---|
| `motion_state` | int | Player state enum (NORMAL=0, DASH=1, WALL_JUMP_LOCK=2). Used by trigger rules. |
| `vfx` | Array (optional) | VFX event dicts. Only present on ticks where events fired. |

Each VFX event dict:
```
{
  "type":      "dash_trail",
  "tick":      int,          # global tick when the event was generated
  "position":  Vector2,      # world spawn position
  "flip_h":    bool,         # sprite horizontal flip
  "anim_name": String,       # animation name for texture snapshot
  "anim_frame": int,         # frame index for texture snapshot
}
```

### Echo animation isolation

The echo's `TimeAwareAnimator._physics_process` is disabled at startup (`set_physics_process(false)`). Echo animation is driven entirely by `apply_animation_state()` from recorded frame data. This prevents the TAA's auto-playback from fighting with recorded state.

### Tunable exports on MovementEffects

| Property | Purpose |
|---|---|
| `dash_trail_enabled` | Master toggle for dash afterimages |
| `dash_trail_interval_ticks` | Ticks between ghost spawns during DASH state |
| `dash_trail_lifetime_ticks` | How many ticks each ghost lives (18 ≈ 0.3s at 60 FPS) |
| `dash_trail_start_alpha` | Peak ghost alpha (at spawn tick, age = 0) |
| `dash_trail_tint` | Color tint applied on top of `actor_tint` |
| `dash_trail_z_offset` | Draw order offset (0 = same as gameplay elements) |

### Adding a future effect (jump burst, landing dust, etc.)

1. Add an export group and parameters (lifetime, alpha, tint, etc.) in `movement_effects.gd`.
2. Add the trigger rule in `generate_events()` — typically a state or transition check. The event dict must include `"type"` and `"tick"`.
3. Add a `match` branch in `_get_lifetime_for_type()` and `_get_alpha_for_type()` for the new event type.
4. Add a `_create_ghost` variant if the new effect uses a different visual (particles, multiple sprites, etc.).
5. No changes to echo_player, branch_track, or timeline_manager are required — the `"vfx"` array in frame data accommodates any event type, and the tick-driven ghost management handles any lifespan shape.
