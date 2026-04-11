# Beginner Guide

A practical, end-to-end guide for understanding, editing, and extending this project.

---

## 1. What This Game Is

A **2D puzzle-platformer** built in **Godot 4.6 + GDScript** where the core mechanic is **time inversion with branch echoes**. The player can reverse their temporal direction, leaving behind visible echoes from previous timeline branches. Those echoes replay their recorded movements and can cooperate with the current player to solve puzzles — holding switches, blocking paths, or standing on pressure plates. Think of it as layering multiple versions of yourself across time.

---

## 2. Project Structure

```
game2_claude/
├── project.godot              # Godot project file (960x640 viewport, canvas_items stretch)
├── CLAUDE.md                  # AI assistant instructions
├── GAME_SPEC.md               # Design spec — the "what" and "why"
├── IMPLEMENTATION_PLAN.md     # Build plan — the "how"
├── IMPLEMENTATION_NOTES.md    # Technical decisions and rationale
├── LEVEL_AUTHORING.md         # Practical room-building reference
├── BEGINNER_GUIDE.md          # This file
│
├── scenes/                    # Ready-to-use scene files
│   ├── main.tscn              # Root scene — run this to play
│   ├── player.tscn            # Active player (CharacterBody2D)
│   ├── echo_player.tscn       # Echo replay instance
│   ├── switch.tscn            # Pressure plate trigger
│   ├── timed_switch.tscn      # Hold-timer pressure plate
│   ├── door.tscn              # Trigger-driven gate
│   ├── time_scheduled_door.tscn  # Time-driven gate
│   ├── moving_platform.tscn   # Trigger-driven elevator
│   ├── hazard.tscn            # Kill zone
│   ├── goal_zone.tscn         # Level completion zone
│   ├── room_exit.tscn         # Room transition trigger
│   ├── terrain_block.tscn     # Static geometry (floor/wall/platform)
│   ├── crumble_block.tscn     # Breakable platform
│   └── rooms/
│       ├── room_01.tscn       # Tutorial room (switches + door + hazard)
│       ├── room_02.tscn       # Echo cooperation room (timed switch + elevator + goal)
│       └── room_template.tscn # Starter room — duplicate this to create new rooms
│
├── scripts/                   # All GDScript files
│   ├── main.gd                # Top-level orchestrator — builds player, HUD, wires systems
│   ├── timeline_manager.gd    # Core time-branch engine — tick, branches, echoes, mechanisms
│   ├── branch_track.gd        # Single timeline branch data structure
│   ├── room_tick_context.gd   # Per-room tick counter
│   ├── room_manager.gd        # Room loading/unloading/transitions
│   ├── active_player.gd       # Player controller (Celeste-inspired feel)
│   ├── echo_player.gd         # Echo replay logic
│   ├── player_sprite_frames.gd # Procedural placeholder animation frames
│   ├── time_aware_animator.gd # Direction-aware animation component
│   ├── hud.gd                 # On-screen info (branch, tick, reversal status)
│   ├── timeline_bar.gd        # Horizontal branch visualization bar
│   ├── base_placeable.gd      # Base class for all editor-placeable entities
│   ├── base_hazard.gd         # Base class for hazards
│   ├── base_room.gd           # Base class for room root nodes
│   ├── mechanism_trigger.gd   # Base class for triggers (switches, plates)
│   ├── mechanism_receiver.gd  # Base class for receivers (doors, platforms)
│   ├── time_scheduled_receiver.gd # Base for time-driven receivers
│   ├── switch_trigger.gd      # Pressure plate implementation
│   ├── timed_switch.gd        # Hold-timer pressure plate
│   ├── door_receiver.gd       # Trigger-driven door
│   ├── time_scheduled_door.gd # Time-driven door
│   ├── moving_platform.gd     # Trigger-driven elevator
│   ├── hazard.gd              # Kill zone implementation
│   ├── goal_zone.gd           # Level completion zone
│   ├── room_exit.gd           # Room transition trigger
│   ├── terrain_block.gd       # Static geometry with optional texture
│   ├── crumble_block.gd       # Breakable platform
│   └── generate_test_textures.gd # Editor utility for test texture generation
│
├── templates/                 # Starting points for NEW entity types (don't instance these)
│   ├── placeable.tscn         # Generic spatial entity
│   ├── terrain_block.tscn     # Physics-body terrain variant
│   ├── mechanism_trigger.tscn # New trigger type
│   ├── mechanism_receiver.tscn # New receiver type
│   ├── hazard.tscn            # New hazard variant
│   └── time_aware_entity.tscn # Animated/time-reversible entity
│
└── textures/                  # Texture assets
    ├── test_grid.png          # Generated test texture (grid pattern)
    └── test_checker.png       # Generated test texture (checkerboard)
```

---

## 3. Core Concepts

### Time branches

Time in this game is not a simple rewind. It is a **branching timeline**:

- The game maintains a **global tick** that advances forward (+1) or backward (-1).
- Each continuous segment of gameplay is a **branch** (a `BranchTrack`).
- When the player presses **R**, the current branch is **sealed** and a new branch begins.
- The sealed branch becomes an **echo** — a transparent replay of what the player did.

### Echoes

Echoes are not AI. They are **frame-accurate replays** of previously recorded branches:

- Each frame, an echo reads its position/velocity/animation from the recorded data at the current tick.
- Echoes can activate switches and trigger mechanisms — they are "real" for puzzle purposes.
- Echoes do NOT collide with the active player — they pass through each other.
- If an echo's recorded path becomes physically impossible (wall built in its path, hazard placed), the echo **collapses** (disappears). This does not fail the level.

### The reversal cycle

Reversals follow a strict 3-state cycle:

1. **READY** — Player is moving forward. Press R to start reversing.
2. **REVERSING** — Player is moving backward through time. Press R to return to forward.
3. **LOCKED** — Player is moving forward again, but R is blocked. The lock releases when `global_tick` reaches the tick where the reversal started.

This prevents rapid reversal spam. The player must "catch up" to where they reversed before they can reverse again.

### Room-local tick

Each room has its own tick counter (`room_tick`) that advances with `time_direction`. Mechanisms like TimeScheduledDoor and TimedSwitch use room_tick, not global_tick. This means:

- A door scheduled to open at room_tick 60 will "un-open" if time reverses past tick 60.
- Room_tick resets to 0 on level restart.
- Converting: `ticks = seconds * 60` (at 60 FPS). So 1 second = 60 ticks.

---

## 4. Controls

| Action | Keys |
|--------|------|
| Move left | A, Left Arrow |
| Move right | D, Right Arrow |
| Jump | Space, W, Up Arrow |
| Dash | Shift, K |
| Reverse time | R |
| Restart level | Backspace |
| Toggle debug panel | F3 |

The player has **Celeste-inspired movement feel**:
- **Acceleration-based movement**: ~9 frames to max speed, ~6 frames to stop on ground, slower air control
- **Input priority**: when both left+right held, last-pressed wins
- **Jump**: coyote time (6 frames), jump buffering (6 frames), variable height (release early for short hop), apex gravity reduction (hang time at peak)
- **Eight-direction dash**: one per airborne period, refills on landing. Shift/K to activate. Direction from held input; no input = facing direction
- **Wall slide**: press into a wall while airborne and falling — fall speed is capped for a controlled descent
- **Wall jump**: press jump while airborne and near a wall (grace window of 4 frames). Brief lock period prevents re-grab. Refills dash.
- **Corner correction**: nudges past ledge corners when barely missing (up to 6 pixels)
- **Edge jump grace**: a small spatial check (4 pixels) extends coyote time at ledge edges
- **Momentum preservation**: jumping out of a dash keeps horizontal speed, which decays naturally

---

## 5. Editor Workflow: Your First Room

### Step 1: Create the room file

1. In the FileSystem panel, right-click `scenes/rooms/`.
2. Duplicate `room_template.tscn` and rename it (e.g. `room_03.tscn`). The template has a boxed room with floor/walls/ceiling, spawn point, and the standard node structure.
3. Open the new scene.

### Step 2: Set up the root node

The root should already have `base_room.gd` attached (inherited from the duplicate). Verify:
- **Script:** `res://scripts/base_room.gd`
- **room_bounds:** `Rect2(0, 0, 960, 640)` — this controls camera limits.

### Step 3: Build geometry

Under the **Geometry** node, add terrain:

1. Instance `scenes/terrain_block.tscn` as a child of Geometry.
2. Position it in the 2D viewport.
3. In the Inspector, set `block_size` to your desired dimensions.
4. Set `resize_anchor` before changing size if you want a specific edge pinned.

Standard room shell (already present in duplicated rooms):
- **Floor:** position (480, 600), block_size (960, 80)
- **WallLeft:** position (16, 320), block_size (32, 640)
- **WallRight:** position (944, 320), block_size (32, 640)
- **Ceiling:** position (480, 16), block_size (960, 32)

### Step 4: Add spawn and entry points

Under the **Spawns** node:
1. Add a `Marker2D` named `PlayerSpawn`.
2. Add it to the `player_spawn` group (Node > Groups in the Inspector).
3. Position it where the player should start.

Under the **Entries** node:
1. Add `Marker2D` nodes for each entrance (e.g. `EntryLeft`, `EntryRight`).
2. Add each to the `room_entries` group.
3. Position them at room edges.

### Step 5: Add mechanisms

Instance component scenes from `scenes/`:
- `scenes/switch.tscn` — pressure plate
- `scenes/door.tscn` — trigger-driven gate
- `scenes/hazard.tscn` — kill zone
- `scenes/goal_zone.tscn` — level completion

Place them as children of the **Mechanisms** node.

### Step 6: Wire triggers

Select a receiver (e.g. a DoorReceiver). In the Inspector:
1. Find the **Trigger Wiring** group.
2. Click the `triggers` array and add entries.
3. For each entry, set a NodePath pointing to a trigger node (e.g. `../Switch1`).

In the 2D editor, yellow lines will draw from the receiver to each trigger, confirming the wiring.

### Step 7: Register the room

Open `scripts/main.gd` and add your room to `ROOM_REGISTRY`:

```gdscript
const ROOM_REGISTRY := {
    "room_01": "res://scenes/rooms/room_01.tscn",
    "room_02": "res://scenes/rooms/room_02.tscn",
    "room_03": "res://scenes/rooms/room_03.tscn",   # your new room
}
```

To make it the starting room, change `START_ROOM`:
```gdscript
const START_ROOM := "room_03"
```

### Step 8: Add exits (optional)

Instance `scenes/room_exit.tscn` under the **Exits** node:
1. Set `target_room` to the destination room ID (e.g. `"room_02"`).
2. Set `target_entry` to the entry point name suffix (e.g. `"left"` matches `EntryLeft`).
3. Set `exit_direction` to the edge: `"left"`, `"right"`, `"up"`, or `"down"`.
4. Position the exit at the room edge.

### Step 9: Test

Press F5 (or the Play button) to run the game. If your room is `START_ROOM`, you'll spawn there immediately.

---

## 6. Component Reference

Quick-reference table of all placeable components. See `LEVEL_AUTHORING.md` for full property tables.

| Component | Scene | Primary Size Property | Key Behavior |
|-----------|-------|-----------------------|--------------|
| TerrainBlock | `terrain_block.tscn` | `block_size` | Static collision geometry, optional texture |
| CrumbleBlock | `crumble_block.tscn` | `block_size` | Breaks after standing on it, optional respawn |
| SwitchTrigger | `switch.tscn` | `visual_size` | Pressure plate — active while actor stands on it |
| TimedSwitch | `timed_switch.tscn` | `visual_size` | Stays active for `hold_ticks` after actor leaves |
| DoorReceiver | `door.tscn` | `door_size` | Opens when wired triggers are satisfied |
| TimeScheduledDoor | `time_scheduled_door.tscn` | `door_size` | Opens/closes on room_tick schedule |
| MovingPlatform | `moving_platform.tscn` | `platform_size` | Moves from placed position to `point_b` when triggered |
| Hazard | `hazard.tscn` | `hazard_size` | Kills player and collapses echoes on contact |
| GoalZone | `goal_zone.tscn` | `zone_size` | Completes the level when player enters |
| RoomExit | `room_exit.tscn` | `exit_size` | Transitions to another room |

---

## 7. How to Create a New Entity Type

The `templates/` folder contains starting-point scenes. Never instance templates directly in rooms.

### Workflow

1. **Choose a template** based on what you're building:
   - `templates/mechanism_trigger.tscn` — new trigger type (e.g. laser tripwire)
   - `templates/mechanism_receiver.tscn` — new receiver type (e.g. moving laser)
   - `templates/hazard.tscn` — new hazard variant (e.g. timed spike)
   - `templates/placeable.tscn` — generic spatial entity
   - `templates/terrain_block.tscn` — physics-body terrain variant
   - `templates/time_aware_entity.tscn` — animated/time-reversible entity

2. **Duplicate** the template scene. Save as `scenes/my_component.tscn`.

3. **Create a script** extending the base class:
   ```gdscript
   @tool
   class_name MyComponent
   extends BaseMechanismTrigger   # or whichever base class
   ```

4. **Attach** the script to the scene root.

5. **Add exports** for behavior specific to your component. Use `@export_group()` to organize the inspector.

6. **Test** by instancing `scenes/my_component.tscn` in a room.

### Base class hierarchy

```
Node2D
└── BasePlaceable (base_placeable.gd)
    ├── BaseMechanismTrigger (mechanism_trigger.gd)
    │   ├── SwitchTrigger (switch_trigger.gd)
    │   └── TimedSwitch (timed_switch.gd)
    ├── BaseMechanismReceiver (mechanism_receiver.gd)
    │   └── DoorReceiver (door_receiver.gd)
    ├── TimeScheduledReceiver (time_scheduled_receiver.gd)
    │   └── TimeScheduledDoor (time_scheduled_door.gd)
    ├── BaseHazard (base_hazard.gd)
    │   └── Hazard (hazard.gd)
    ├── GoalZone (goal_zone.gd)
    └── RoomExit (room_exit.gd)

StaticBody2D
└── TerrainBlock (terrain_block.gd)
    └── CrumbleBlock (crumble_block.gd)

AnimatableBody2D
└── MovingPlatform (moving_platform.gd)
```

---

## 8. Textures and Materials

### Applying textures

1. Import a texture (e.g. a 16x16 `.png`) into the project.
2. Select a component in the editor.
3. Set the texture property (`block_texture`, `base_texture`, or `platform_texture`).
4. Set the color property to **WHITE** `Color(1, 1, 1, 1)` for full-brightness textures. The color tints the texture.

### How tiling works

- The Visual Polygon2D's UVs map `(0, 0)` to `(width, height)`.
- `texture_repeat` is set to `TEXTURE_REPEAT_ENABLED`.
- A 16x16 texture on a 64x32 block tiles 4x2 times.
- Resizing regenerates UVs, so tiling updates automatically.

### Test textures

Run `scripts/generate_test_textures.gd` by attaching it to any node in the editor. It generates:
- `textures/test_grid.png` — grid pattern
- `textures/test_checker.png` — checkerboard pattern

---

## 9. Animation

### TimeAwareAnimator

The project uses **TimeAwareAnimator** — a component node that handles direction-aware animation playback.

**Setup:**
1. Replace the entity's `Visual` Polygon2D with an `AnimatedSprite2D` (or add an `AnimationPlayer`).
2. Add a `TimeAwareAnimator` node as a sibling of the animation node.
3. TimeAwareAnimator auto-detects the first `AnimatedSprite2D` or `AnimationPlayer` sibling.

**What it does:**
- **Forward time:** Normal playback.
- **Reverse time:** AnimatedSprite2D frames decrement manually; AnimationPlayer `speed_scale = -1`.
- **Echo recording:** Captures animation name, frame, and flip for each tick.
- **Echo replay:** Restores exact animation state from recorded frames.

### Player/echo animations

Both `player.tscn` and `echo_player.tscn` have a TimeAwareAnimator child. At runtime, the placeholder Visual is replaced with an AnimatedSprite2D using procedural SpriteFrames (idle, run, jump, fall). The animation state machine in `active_player.gd` selects animations based on movement state.

### Mechanism animations

Mechanisms can also use TimeAwareAnimator. The GoalZone has an AnimationPlayer-driven pulse that reverses with time direction. To add animation to any mechanism:

1. Create an `AnimationPlayer` child with your animations.
2. Add a `TimeAwareAnimator` child sibling.
3. Play animations from your mechanism script.
4. TimeAwareAnimator handles direction-aware speed.

Mechanism animation state is NOT recorded in branch data — it's deterministic from trigger/schedule state.

---

## 10. Understanding the Inspector

### Export groups

All components organize their inspector properties into collapsible groups:

- **Layout** — `resize_anchor` (how the node repositions when resized)
- **Visuals** — `base_color`, `base_texture`, `base_material`, `entity_size`
- Component-specific groups like **Door**, **Switch**, **Trigger Zone**, **Schedule**, etc.

### What to edit vs. what not to edit

**Edit these** (on the parent component):
- Size properties: `block_size`, `door_size`, `hazard_size`, `platform_size`, `visual_size`, `zone_size`, `exit_size`
- Color properties: `block_color`, `closed_color`, `unpressed_color`, etc.
- Behavior: `triggers`, `schedule`, `hold_ticks`, `point_b`, `target_room`, etc.

**Never edit directly** (synced automatically from parent):
- `CollisionShape2D` children
- `Visual` Polygon2D children
- `DoorBody` StaticBody2D (managed by door script)

### Configuration warnings

Yellow triangle icons appear in the scene tree when something is misconfigured:

| Warning | Meaning |
|---------|---------|
| "Missing 'Visual' child node" | Component has no Visual — add a Polygon2D or Sprite2D |
| "entity_size has a zero or negative dimension" | Size property is invalid |
| "No triggers assigned" | Receiver has no trigger wiring — it will never open |
| "Trigger path does not resolve" | A wired NodePath points to nothing |
| "No child in 'player_spawn' group" | Room has no spawn point |
| "No entry points" | Room has no entry markers |
| "target_room is empty" | RoomExit has no destination |
| "Platform will not move" | MovingPlatform `point_b` is `(0, 0)` |
| "schedule is empty" | TimeScheduledDoor has no open/close windows |
| "room_bounds smaller than viewport" | Camera may show areas outside the room |
| "No RoomExit child found" | Player cannot leave this room |

Fix these warnings before testing.

### Debug panel (F3)

The F3 overlay shows:
- **Branches**: index, generation, tick range, direction, frame count, status (active/sealed/collapsed)
- **Cycle state**: READY/REVERSING/LOCKED, reversal count, unlock tick
- **Room**: room ID, room tick
- **Movement**: state (NORMAL/DASH/WALL_JUMP_LOCK), dash available, dash timer, coyote counter, jump buffer, wall grace, edge grace, velocity

---

## 11. Puzzle Design Patterns

### Echo cooperation (the core pattern)

The fundamental puzzle: the player needs an echo to hold something.

1. Place a **SwitchTrigger** where the player will stand.
2. Place a **DoorReceiver** blocking the goal, wire its `triggers` to the switch.
3. **Play:** The player stands on the switch, then presses R to reverse. The echo replays and holds the switch while the active player (now in a new branch) walks through the open door.

### Timed elevator ride

1. Place a **TimedSwitch** with `hold_ticks` = desired duration.
2. Place a **MovingPlatform** wired to the TimedSwitch.
3. **Play:** The player (or echo) activates the switch, then rides the platform before the timer expires.

### Scheduled door timing

1. Place a **TimeScheduledDoor** with `schedule = [(open_tick, close_tick)]`.
2. **Play:** The door opens/closes based on room_tick. During reversal, the door un-opens as time rewinds.

### Crumble bridge

1. Place **CrumbleBlock** nodes in a row.
2. **Play:** The player must cross before the blocks crumble. Echoes can also trigger crumble, so plan echo paths carefully.

### Multi-echo puzzle

More complex puzzles require multiple reversals:
1. First pass: player activates switch A.
2. Reverse + forward: echo 1 holds switch A. Player activates switch B.
3. Reverse + forward: echo 1 holds A, echo 2 holds B. Player walks through the double-gated door.

Remember: the reversal cycle (READY -> REVERSING -> LOCKED -> READY) means the player must reach the tick where they reversed before they can reverse again.

---

## 12. Troubleshooting

### Player doesn't spawn

- Check that the room has a `Marker2D` in the `player_spawn` group.
- Check that the room is registered in `main.gd`'s `ROOM_REGISTRY`.
- Look for yellow warning triangles on the room root node.

### Door doesn't open

- Select the door and check the `triggers` array in the Inspector.
- Verify trigger NodePaths resolve (no yellow warning triangle).
- Check `require_all`: if true, ALL triggers must be active simultaneously.
- If `latching` is false, the trigger must stay active while the player passes through.

### Echo collapses immediately

- The echo's recorded path may intersect geometry that wasn't there during recording.
- Check if a door closed in the echo's path.
- Check if the echo passes through a hazard zone.

### Mechanisms don't respond to the player

- During **reverse mode**, the player cannot interact with mechanisms (switches, goals, exits). This is by design. Only hazards and terrain collision work during reverse.
- The HUD shows "R: Return to Forward" when reversing — press R again to return to forward before interacting.

### R key doesn't work (reversal locked)

- The reversal cycle may be in the **LOCKED** state. The HUD shows "R: Locked (reach tick N)".
- Keep playing forward. When `global_tick` reaches the unlock tick, R becomes available again.

### Room exit doesn't work

- Check that `target_room` matches a key in `ROOM_REGISTRY`.
- Check that `target_entry` matches an entry Marker2D name suffix in the target room (e.g. `"left"` matches `EntryLeft`).
- Room exits don't work during reverse mode.

### Visual not updating when I change size

- Always edit the **parent component's size property** (e.g. `block_size`, `door_size`), never the Visual child directly.
- The Visual child is auto-synced from the parent. Direct edits will be overwritten.

### Timeline bar looks squished with many branches

- The timeline bar caps at 5 visible lanes. Older branches are collapsed into a summary lane showing "+N" at the top.
- All branches still contribute to the tick range and reversal markers.

---

## 13. Architecture Overview

### Process flow (each physics frame)

1. **ActivePlayer** (`priority 0`): reads input, runs `move_and_slide()`, records frame state to active branch via `timeline_manager.record_frame()`, checks for R press.
2. **TimelineManager** (`priority 1`): updates echo positions, evaluates mechanism triggers, checks hazard/goal overlap, validates echoes (collapse if invalid), advances tick.

### Class hierarchy

- **BasePlaceable** — root for all editor-placeable entities. Provides `entity_size`, `base_color`, `base_texture`, `base_material`, `resize_anchor`, placeholder visual sync.
- **BaseMechanismTrigger** — extends BasePlaceable with `trigger_size` and `activated` state. TimelineManager queries these each frame.
- **BaseMechanismReceiver** — extends BasePlaceable with `triggers` array, `require_all`/`latching` logic, and `evaluate_triggers()`.
- **TimeScheduledReceiver** — extends BasePlaceable with tick-based schedule evaluation.
- **TerrainBlock** — extends StaticBody2D (not BasePlaceable). Has its own texture/resize system.
- **MovingPlatform** — extends AnimatableBody2D (not BaseMechanismReceiver). Has its own trigger handling.

### Collision layers

| Bit | Layer | Used by |
|-----|-------|---------|
| 1 | World | Static geometry (floors, walls, platforms) |
| 2 | Door | Door StaticBody2D (separate for collapse query distinction) |
| 4 | ActivePlayer | The one controlled character |
| 8 | Hazard | Kill zones (detected by manual Rect2 check) |
| 16 | MechanismTrigger | Switch zones (detected by Rect2 check) |
| 32 | Echo | Echo replay instances |

**Player** masks layers 1+2 (collides with world + doors via `move_and_slide`).
**Echoes** mask layer 0 (no physics — teleported to recorded positions each frame).

### Key signals

| Signal | Emitted by | Purpose |
|--------|-----------|---------|
| `time_reversed(new_dir)` | TimelineManager | Screen tint/flash on reversal |
| `level_restart_requested` | TimelineManager | Player death restart |
| `level_completed` | TimelineManager | Goal reached |
| `room_changed(room_id)` | RoomManager | Room transition complete |
| `player_spawn_found(pos)` | RoomManager | Spawn position discovered |

### Reverse-mode interaction rule

While reversing (`time_direction == -1`), the player is a non-interactive temporal traversal entity:

- **Always works:** terrain collision, hazard death, frame recording, echo replay, pressing R again.
- **Disabled:** switch activation, goal completion, room exits, crumble triggering.

The canonical gate is `TimelineManager.is_player_interactable()` — returns `true` only when `time_direction == 1`. Any new system that checks the player for puzzle/mechanism purposes MUST call this first.
