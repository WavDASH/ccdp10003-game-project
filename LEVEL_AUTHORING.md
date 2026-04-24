# Level Authoring Guide

Practical reference for building and editing rooms in the Godot 4.6 editor.

> **New here?** Read `BEGINNER_GUIDE.md` first for a full walkthrough of concepts, project structure, and step-by-step room creation.

---

## Quick Start: Adding a New Room

1. **Duplicate** `scenes/rooms/room_template.tscn` and rename it to `room_XX.tscn`.
2. **Change `room_bounds`** in the Inspector to your desired room size (e.g. `Rect2(0, 0, 1920, 640)` for a double-wide room). The shell walls, ceiling, floor, and background update automatically.
3. **Add** puzzle content under the **Geometry** node (terrain, platforms, etc.).
4. **Position** the `PlayerSpawn` marker where the player should start.
5. **Add** entry Marker2D(s) in the `room_entries` group (e.g. `EntryLeft`, `EntryRight`).
6. **Register** the room in `main.gd`'s room registry:
   ```gdscript
   room_manager.room_registry["room_XX"] = "res://scenes/rooms/room_XX.tscn"
   ```
7. **Wire exits** — place RoomExit instances that point to the new room (set `target_room` and `target_entry`).

### Room structure

The template uses a two-layer geometry approach:

- **RoomShell** — auto-synced boundary walls (Floor, Ceiling, WallLeft, WallRight). These resize and reposition automatically when you change `room_bounds` or `wall_thickness` in the Inspector.
- **Geometry** — manually placed level content (platforms, obstacles, extra walls). NOT affected by room_bounds changes.
- **Background** — Polygon2D that auto-resizes with room_bounds.

### Room conventions
- Default size: **960x640** pixels (one viewport). Change via `room_bounds`.
- `wall_thickness`: default 32px. Applies to all four shell walls.
- Player spawn / entries / exits: Marker2D / RoomExit nodes in dedicated containers — positioned manually.

---

## Per-Room Camera Settings

Each room can configure its own camera behavior via exports in the Inspector under the **Camera** group on the room root node.

### Camera Mode

| Mode | Behavior |
|---|---|
| `FOLLOW` (default) | Camera follows the player, clamped to room bounds. Zoom 1:1. Standard for rooms that are viewport-sized or larger. |
| `FIT_ROOM` | Camera zooms out to show the entire room at once. Good for large puzzle rooms where the player needs to see everything. Zoom is auto-calculated from room_bounds vs viewport (960x640). |
| `CUSTOM` | Camera follows the player with a custom zoom level and optional custom bounds. Use for tighter or wider framing. |

### Camera Properties

| Property | Default | Purpose |
|---|---|---|
| `camera_mode` | FOLLOW | Which camera behavior to use |
| `camera_zoom` | (1, 1) | Zoom override (CUSTOM mode only). `(2, 2)` = 2x zoom in, `(0.5, 0.5)` = 2x zoom out |
| `camera_bounds` | (empty) | Camera movement bounds (CUSTOM mode only). Leave at zero-size to use room_bounds |
| `camera_smoothing_enabled` | true | Whether camera smoothly follows or snaps to player |
| `camera_smoothing_speed` | 8.0 | How fast the camera catches up (higher = snappier) |

### Examples

**Standard room (960x640):** Leave everything at defaults. Camera follows player at 1:1 zoom.

**Large room with full overview:** Set `camera_mode = FIT_ROOM`. A 1920x1280 room auto-calculates zoom to 0.5x so the whole room is visible.

**Tight follow camera:** Set `camera_mode = CUSTOM`, `camera_zoom = (1.5, 1.5)`. Camera follows player zoomed in 50%.

**Custom camera bounds:** Set `camera_mode = CUSTOM`, `camera_bounds = Rect2(100, 0, 760, 640)`. Camera only pans within the specified rectangle (useful for keeping important areas visible).

**No smoothing (instant snap):** Set `camera_smoothing_enabled = false` on any mode.

### Room transitions

When the player enters a new room, the destination room's camera settings are applied automatically. The camera zoom, limits, and smoothing update instantly on room load.

### Editor overlay

The room bounds overlay shows the current camera mode and effective zoom:
- `cam=FOLLOW` — standard follow camera
- `cam=FIT_ROOM (0.50x)` — shows calculated zoom factor
- `cam=CUSTOM (1.50x)` — shows custom zoom factor

In CUSTOM mode with explicit camera_bounds, a yellow rectangle shows the camera movement area.

---

## Placing Components

### General workflow

1. **Instance the scene** from the `scenes/` folder (not `templates/`).
2. **Position** the node in the 2D editor.
3. **Edit properties** in the Inspector (see "Which Property to Edit" below).
4. **Never edit child nodes** (CollisionShape2D, Visual) directly — they are synced from the parent's exported size property.

### Resize workflow

All resizable components support `resize_anchor`:
1. Set `resize_anchor` to the edge/corner that should stay fixed (e.g. `BOTTOM` for a floor).
2. Change the size property (`block_size`, `door_size`, `exit_size`, etc.).
3. The node's position auto-adjusts so the chosen anchor stays pinned.

---

## Which Property to Edit

### TerrainBlock (floors, walls, platforms)
**Scene:** `scenes/terrain_block.tscn`

| Property | Purpose |
|---|---|
| `block_size` | Width x height — **primary size control** |
| `block_color` | Fill color |
| `block_texture` | Tiling texture (set `block_color` to WHITE for full brightness) |
| `one_way` | Jump-through-from-below platform |
| `resize_anchor` | Which edge stays fixed when resizing |

### CrumbleBlock (breakable platform)
**Scene:** `scenes/crumble_block.tscn`

| Property | Purpose |
|---|---|
| `block_size` | Width x height |
| `crumble_delay_ticks` | Ticks after standing on before it breaks (30 = 0.5s) |
| `respawn_delay_ticks` | Ticks after breaking before reappearing (-1 = never) |
| `crumble_color` / `warning_color` | Normal vs flashing colors |

### SwitchTrigger (pressure plate)
**Scene:** `scenes/switch.tscn`

| Property | Purpose |
|---|---|
| `visual_size` | Width x height of the visible plate |
| `trigger_size` | Width x height of the invisible detection zone (often larger) |
| `unpressed_color` / `pressed_color` | Color feedback |

When `trigger_size` differs from `visual_size`, a dashed cyan outline shows the trigger zone in the editor.

### TimedSwitch (hold-timer pressure plate)
**Scene:** `scenes/timed_switch.tscn`

| Property | Purpose |
|---|---|
| `visual_size` | Width x height of the visible plate |
| `trigger_size` | Detection zone size |
| `hold_ticks` | Room_ticks the switch stays active after actor leaves (60 = 1s) |
| `unpressed_color` / `pressed_color` | Color feedback |

### DoorReceiver (trigger-driven door)
**Scene:** `scenes/door.tscn`

| Property | Purpose |
|---|---|
| `door_size` | Width x height — **primary size control** |
| `triggers` | Array of NodePaths to trigger nodes |
| `require_all` | true = AND, false = OR |
| `close_delay_ticks` | Frames to wait before closing after triggers lost (0 = instant) |
| `closed_color` / `open_color` | Visual states |

### TimeScheduledDoor (time-driven door)
**Scene:** `scenes/time_scheduled_door.tscn`

| Property | Purpose |
|---|---|
| `door_size` | Width x height |
| `schedule` | Array of Vector2i: each `(open_tick, close_tick)` in room-local ticks |
| `loop_period` | -1 = no loop, >0 = schedule repeats every N room_ticks |
| `closed_color` / `open_color` | Visual states |

**Example:** Door opens 1 second after room entry:
- `schedule = [(60, 2147483647)]` — opens at tick 60, stays open
- `schedule = [(60, 180)]` — opens at tick 60, closes at tick 180

### MovingPlatform (trigger-driven elevator)
**Scene:** `scenes/moving_platform.tscn`

| Property | Purpose |
|---|---|
| `platform_size` | Width x height |
| `point_b` | End position relative to placed position (e.g. `(0, -200)` = 200px up) |
| `move_speed` | Pixels per second |
| `triggers` | Array of NodePaths to trigger nodes |
| `require_all` | AND vs OR logic |
| `platform_color` | Fill color |

A green line + ghost rectangle shows the travel path in the editor.

### Hazard (kill zone)
**Scene:** `scenes/hazard.tscn`

| Property | Purpose |
|---|---|
| `hazard_size` | Width x height — **primary size control** |
| `base_color` | Fill color (red) |

### GoalZone (level completion)
**Scene:** `scenes/goal_zone.tscn`

| Property | Purpose |
|---|---|
| `zone_size` | Width x height |
| `base_color` | Fill color (gold/transparent) |

### TutorialHintZone (contextual tutorial hint)
**Scene:** `scenes/tutorial_hint_zone.tscn`

Drops a short hint label into the world that fades in when the player enters the zone and fades out when they leave. By default each hint appears once per game session.

| Property | Purpose |
|---|---|
| `hint_text` | The text to display (supports line breaks) |
| `zone_size` | Width x height of the trigger rectangle |
| `show_once` | If true (default), hint appears only the first time per session |
| `hint_id` | Stable id for the show-once registry. Falls back to node path if empty. Set this if you want the hint to survive a room-path rename |
| `label_offset` | Position of the label relative to the zone center (negative Y = above) |
| `font_size` | Label font size |
| `fade_duration` | Fade in/out time in seconds |

**Authoring:**
1. Instance `scenes/tutorial_hint_zone.tscn` into a room.
2. Position it at the moment the hint is relevant (e.g. near the first switch, or right before the puzzle's aha moment).
3. Set `hint_text` and adjust `zone_size` so the zone covers the player's path.
4. Group multiple zones under a `Tutorial` Node2D for tidy scene hierarchy.

**Resetting shown hints:** Call `TutorialHintZone.reset_shown()` from any script if you want all hints to re-trigger (e.g. for a "replay tutorial" option).

### RoomExit (room transition trigger)
**Scene:** `scenes/room_exit.tscn`

| Property | Purpose |
|---|---|
| `exit_size` | Width x height of the detection zone |
| `target_room` | Room ID to load (e.g. `"room_02"`) |
| `target_entry` | Entry point name in target room (e.g. `"left"`) |
| `exit_direction` | Which edge: `"left"`, `"right"`, `"up"`, `"down"` |

---

## What NOT to Edit Directly

- **CollisionShape2D** children — synced automatically from the parent's size property.
- **Visual** Polygon2D children — synced automatically from the parent's size + color properties.
- **DoorBody** StaticBody2D — created/managed by the door script.

If you need to replace placeholder art, replace the **Visual** child node entirely (swap Polygon2D for Sprite2D / AnimatedSprite2D / NinePatchRect). The script type-checks before touching it, so non-Polygon2D visuals are left alone.

---

## Interaction Categories: Terrain vs Gameplay

Understanding this split is critical for how the reverse-mode player behaves.

### Always active (work in both forward and reverse)

These interactions work regardless of time direction:

| Element | Why it's always active |
|---|---|
| Floor, walls, ceiling (TerrainBlock) | Physics collision (layer 1) |
| Moving platforms (MovingPlatform) | Physics collision (layer 1) |
| One-way platforms | Physics collision (layer 1) |
| CrumbleBlock (standing on it) | Physics collision (layer 1) |
| Doors (closed) | Physics collision (layer 2) |
| **Hazards** | **Direct overlap check, NOT gated — player can die while reversing** |

The player physically collides with terrain and can be killed by hazards even while reversing time.

### Mechanism / Puzzle (gated by `is_player_interactable()`)

These interactions are manual overlap checks. They are **disabled** when the player is reversing time:

| Element | What the gate prevents |
|---|---|
| Switches / TimedSwitches | Player can't press them while reversing |
| GoalZone | Player can't complete level while reversing |
| RoomExit | Player can't change rooms while reversing |
| CrumbleBlock (crumble trigger) | Player can't start the crumble timer while reversing |

**Echoes are unaffected** — they follow their own recorded paths and interact with mechanisms according to their own rules.

---

## Room-Local Tick and Mechanisms

Each room has its own tick counter (`room_tick`) that advances by `+1` when time moves forward and `-1` when time reverses.

- **TimeScheduledDoor** uses room_tick for its schedule windows. A door set to open at tick 60 will "un-open" if the player reverses time past tick 60.
- **TimedSwitch** uses room_tick for its hold timer. The hold naturally "un-counts" during reversal.
- **room_tick resets to 0** on room restart (player death).
- **room_tick freezes** when the player is in a different room.

### Converting real time to ticks
At 60 FPS: `ticks = seconds * 60`
- 0.5 seconds = 30 ticks
- 1 second = 60 ticks
- 2 seconds = 120 ticks

---

## Replacing Placeholder Art

All placeholder visuals are Polygon2D nodes named "Visual" under their parent component.

**To replace with real art:**
1. Delete the "Visual" Polygon2D child.
2. Add a Sprite2D, AnimatedSprite2D, or NinePatchRect as a child (name it anything).
3. The parent script's `_sync_placeholder_visual()` type-checks for Polygon2D — it won't touch your replacement.
4. You are now responsible for sizing/positioning the art node yourself.

**For animated replacements:**
1. Add an AnimatedSprite2D or AnimationPlayer as the visual.
2. Add a **TimeAwareAnimator** child node to the parent for direction-aware playback.
3. The animator auto-detects the animation node and handles forward/reverse playback.

---

## Editor Visual Indicators

In the 2D editor, components draw helpful overlays:

| Component | What you see |
|---|---|
| SwitchTrigger / TimedSwitch | Dashed cyan outline when trigger_size differs from visual_size |
| DoorReceiver | Brown outline + trigger count label |
| TimeScheduledDoor | Purple outline + schedule range label |
| MovingPlatform | Green line + ghost rectangle showing travel path to point_b |
| Hazard | Red outline with hatch pattern + "HAZARD" label |
| GoalZone | Gold outline + "GOAL" label |
| RoomExit | Green outline + directional arrow + "EXIT -> room_id" label |

These overlays only appear in the editor (guarded by `Engine.is_editor_hint()`).

---

## Common Puzzle Patterns

> For more puzzle patterns including multi-echo puzzles, see `BEGINNER_GUIDE.md` Section 11.

### Echo cooperation (switch + door)
1. Place a SwitchTrigger where the player will stand.
2. Place a DoorReceiver blocking the path, wire its `triggers` to the switch.
3. The player stands on the switch, presses R to reverse, and the echo holds the switch open.

### Timed elevator ride
1. Place a TimedSwitch with `hold_ticks` = desired duration.
2. Place a MovingPlatform wired to the TimedSwitch.
3. The player (or echo) activates the switch, then rides the platform before the timer expires.

### Scheduled door timing
1. Place a TimeScheduledDoor with `schedule = [(open_tick, close_tick)]`.
2. The door opens/closes based on room_tick — the player must time their approach.
3. During reversal, the door un-opens/un-closes as room_tick rewinds.

### Crumble bridge
1. Place CrumbleBlock(s) in a row to form a bridge.
2. The player must cross before the blocks crumble.
3. Echoes can also trigger crumble — plan echo paths carefully.

### Dash-gated platforming
1. Place platforms or gaps that require a dash to cross (wider than normal jump distance).
2. The player gets one dash per airborne period (refills on landing or wall jump).
3. Combine with wall jumps for vertical challenges: wall jump → dash → wall jump chains.

### Wall jump ascent
1. Place two parallel walls with a gap too high to normal-jump.
2. The player wall-jumps between them to ascend.
3. Each wall jump refills the dash, enabling dash+wall jump sequences.

---

## Templates vs Components

> For the full class hierarchy and how to extend it, see `BEGINNER_GUIDE.md` Sections 7 and 13.

The project has two kinds of reusable scenes:

### Component scenes (`scenes/`)

Ready-to-instance in rooms. Drag from the FileSystem into a room scene.

| Scene | Use it for |
|---|---|
| `scenes/switch.tscn` | Pressure plate trigger |
| `scenes/timed_switch.tscn` | Hold-timer trigger |
| `scenes/door.tscn` | Trigger-driven gate |
| `scenes/time_scheduled_door.tscn` | Time-driven gate |
| `scenes/moving_platform.tscn` | Trigger-driven elevator |
| `scenes/hazard.tscn` | Kill zone |
| `scenes/goal_zone.tscn` | Level completion zone |
| `scenes/room_exit.tscn` | Room transition trigger |
| `scenes/terrain_block.tscn` | Floor/wall/platform |
| `scenes/crumble_block.tscn` | Breakable platform |

### Template scenes (`templates/`)

Starting points for creating **new entity types**. Never instance these directly in rooms.

| Template | When to use |
|---|---|
| `templates/placeable.tscn` | New spatial entity (BasePlaceable) |
| `templates/terrain_block.tscn` | New physics-body terrain variant |
| `templates/mechanism_trigger.tscn` | New trigger type (extends BaseMechanismTrigger) |
| `templates/mechanism_receiver.tscn` | New receiver type (extends BaseMechanismReceiver) |
| `templates/hazard.tscn` | New hazard variant (extends BaseHazard) |
| `templates/time_aware_entity.tscn` | New animated/time-reversible entity |

### Workflow: creating a new entity type

1. **Duplicate** the matching template (e.g., `templates/mechanism_trigger.tscn`).
2. **Save** as a new scene in `scenes/` (e.g., `scenes/laser_trigger.tscn`).
3. **Create** a new script extending the base class (e.g., `scripts/laser_trigger.gd extends BaseMechanismTrigger`).
4. **Attach** the new script to the scene root.
5. **Add exports** for the new behavior.
6. **Test** by instancing the new scene in a room.

---

## Animation Workflow

> See also `BEGINNER_GUIDE.md` Section 9 for an overview of the animation system.

The project uses **TimeAwareAnimator** — a component node that handles direction-aware animation playback and echo state recording.

### Adding animations to an entity

1. Replace the entity's `Visual` Polygon2D with an `AnimatedSprite2D` or add an `AnimationPlayer`.
2. Add a `TimeAwareAnimator` node as a sibling of the animation node.
3. TimeAwareAnimator auto-detects the first `AnimatedSprite2D` or `AnimationPlayer` sibling.

### What TimeAwareAnimator does

- **Forward time:** Normal playback (AnimatedSprite2D plays normally; AnimationPlayer speed_scale = 1).
- **Reverse time:** AnimatedSprite2D frames decrement manually; AnimationPlayer speed_scale = -1.
- **Echo recording:** `get_animation_state()` captures animation name, frame, and flip for each tick.
- **Echo replay:** `apply_animation_state()` restores exact animation state from recorded frames.

### Player/Echo animations

The player and echo automatically create `AnimatedSprite2D` with placeholder SpriteFrames at runtime (idle, run, jump, fall animations). The `TimeAwareAnimator` child in `player.tscn` and `echo_player.tscn` handles direction and recording.

### Mechanism animations

Mechanisms can also use TimeAwareAnimator. The GoalZone has an AnimationPlayer-driven pulse that reverses with time direction. To add animation to any mechanism:

1. Create an `AnimationPlayer` child with your animations.
2. Add a `TimeAwareAnimator` child sibling.
3. Play animations from your mechanism script (e.g., in `_on_open_close()`).
4. TimeAwareAnimator automatically handles direction-aware speed.

**Note:** Mechanism animation state is NOT recorded in branch frame data — it's deterministic from trigger/schedule state. Only player/echo animation state is recorded.

---

## Texture Workflow

### Applying textures to terrain blocks

1. Import a texture (e.g., a 16x16 `.png`) into the project.
2. Select a TerrainBlock in the inspector.
3. Set `block_texture` to your texture.
4. Set `block_color` to `Color(1, 1, 1, 1)` (WHITE) for full-brightness textures. (The color tints the texture.)
5. The texture tiles automatically based on UV mapping (a 16x16 texture on a 128x32 block tiles 8x2).

### Applying textures to placeables

Same workflow using `base_texture` and `base_color` on any BasePlaceable subclass.

### Generating test textures

The script `scripts/generate_test_textures.gd` is a @tool utility that generates `textures/test_grid.png` and `textures/test_checker.png` when attached to any node in the editor. Use these for verifying tiling behavior.

### How tiling works

- `Visual` Polygon2D UVs map `(0,0)` to `(width, height)`.
- `texture_repeat` is set to `TEXTURE_REPEAT_ENABLED`.
- A 16x16 texture on a 64x32 block tiles 4x2 times.
- Resizing re-generates UVs, so tiling updates automatically.
