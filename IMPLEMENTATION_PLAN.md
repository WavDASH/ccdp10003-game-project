# IMPLEMENTATION_PLAN.md — v3: Framework Refactor + Animation, Room Tick, Templates

---

## 1. Analysis of the Current Project

### 1.1 What exists

| Area | State | Notes |
|---|---|---|
| **Core time mechanic** | Working | Global tick, branches, pivot-tick protocol, echo replay |
| **Echo system** | Working but wrong model | Currently spawns echoes for both forward AND reverse branches; uses a hard "max 3 selves" cap (`reversal_phase`) |
| **Mechanism framework** | Functional base | `MechanismTrigger`/`MechanismReceiver` base classes, `SwitchTrigger`, `DoorReceiver` |
| **Level layout** | Scene-based but fragile | `level_01.tscn` has instanced scenes; geometry is manual StaticBody2D + Polygon2D pairs |
| **Component scenes** | Exist | `switch.tscn`, `door.tscn`, `hazard.tscn`, `goal_zone.tscn` |
| **HUD / timeline bar** | Exists | Custom-drawn timeline bar, direction labels, phase status |
| **Screen tint** | Exists | Red forward / blue reverse overlay tint |
| **Player** | Working | CharacterBody2D, white color, records state every tick |

### 1.2 File inventory (20 files)

**Scripts (14):**
`main.gd`, `timeline_manager.gd`, `active_player.gd`, `echo_player.gd`, `branch_track.gd`, `mechanism_trigger.gd`, `mechanism_receiver.gd`, `switch_trigger.gd`, `door_receiver.gd`, `hazard.gd`, `goal_zone.gd`, `hud.gd`, `timeline_bar.gd`

**Scenes (8):**
`main.tscn`, `level_01.tscn`, `player.tscn`, `echo_player.tscn`, `switch.tscn`, `door.tscn`, `hazard.tscn`, `goal_zone.tscn`

---

## 2. What Is Wrong or Limiting

### 2.1 Visual/collision misalignment (HIGH — most painful editing problem)

Every level-geometry node is a StaticBody2D with two manually-synced children:
- `CollisionShape2D` (RectangleShape2D — the truth for physics)
- `Polygon2D` named "Visual" (the truth for rendering)

When you resize the collision shape by dragging handles in the editor, the visual polygon does NOT update. When you move the Visual child, the collision doesn't follow. The user-edited `level_01.tscn` shows this: walls have `position` offsets and `scale` factors on their Visual children, meaning the geometry was dragged in the editor and the visual/collision are already drifting apart.

**Root cause:** No `@tool` script binds these two representations together.

### 2.2 Mechanism components ignore editor size changes

`SwitchTrigger`, `Hazard`, and `GoalZone` all have exported size properties (`trigger_size`, `hazard_size`, `zone_size`) that rebuild their visual polygon in `_ready()`. But:
- Changing the size in the editor inspector has no visible effect until you run the game
- The interaction zone (used by `is_actor_in_zone()` / `get_hazard_rect()`) is an invisible Rect2 — not represented in the editor at all
- The user cannot see what they're editing

`DoorReceiver` partially handles this (syncs DoorBody shape and Visual polygon to `door_size` in `_ready()`), but also has no editor-time feedback.

### 2.3 Echo persistence model is wrong

The current system spawns echoes for **every** sealed branch — forward and reverse. It then enforces a hard `reversal_phase` cap (max 2 reversals, max 3 visible selves) to prevent clutter.

The user's intended model is fundamentally different:
- Only **forward-recorded** branches should become persistent visible echoes (RED)
- **Reverse traversal** is a temporary navigation state — it does NOT leave behind persistent blue echo actors
- There should be NO hard cap on the number of visible selves — echo visibility should follow timeline logic, not an arbitrary number
- Multiple forward echoes can accumulate across multiple reversal cycles

The current `reversal_phase` system, `ECHO_COLOR_REVERSE`, and the "Locked - Wait for Echoes" HUD status are all artifacts of the wrong model.

### 2.4 No room-based structure

Everything lives in a single 960×640 scene. There is no concept of:
- Multiple connected rooms
- Room transitions
- Room loading/unloading
- Camera boundaries per room
- Entry/exit points

The user wants a Celeste-like room-based architecture where progression moves through discrete screens.

### 2.5 Single-scene monolithic orchestration

`main.gd` handles everything: input setup, level loading, player spawning, echo container, screen FX, HUD, wiring, signal handling. There is no separation between "game framework" (persistent across rooms) and "level content" (room-specific).

### 2.6 Mechanism system has only two concrete types

Only `SwitchTrigger` and `DoorReceiver` exist. The base classes (`MechanismTrigger`, `MechanismReceiver`) are sound but untested with other use cases. The architecture plan should include at least 2-3 more concrete types to validate extensibility.

### 2.7 Hazard/goal detection uses stale Rect2 snapshots

`TimelineManager._discover_level()` reads `hazard.get_hazard_rect()` and `goal.get_goal_rect()` once at level load and stores the results as raw `Rect2` values. If a hazard or goal moved (e.g., a moving-platform hazard in a future level), the detection rects would be stale.

**Fix:** Store references to the hazard/goal nodes and call `get_rect()` each frame, or use physics queries instead.

---

## 3. Proposed New Architecture

### 3.1 Layered separation

```
┌──────────────────────────────────────────┐
│  Game Shell  (main.gd / main.tscn)       │  Input, ScreenFX, HUD, player lifecycle
├──────────────────────────────────────────┤
│  Timeline Core  (TimelineManager)        │  Tick, branches, echo spawning, validation
├──────────────────────────────────────────┤
│  Room Manager  (room_manager.gd)         │  Room loading, transitions, camera
├──────────────────────────────────────────┤
│  Room Content  (room_*.tscn)             │  Geometry, mechanisms, hazards, goals, exits
├──────────────────────────────────────────┤
│  Component Library  (@tool scenes)       │  TerrainBlock, Switch, Door, Hazard, Goal,
│                                          │  RoomExit, PlayerSpawn, etc.
└──────────────────────────────────────────┘
```

**Game Shell** is persistent. **Room Content** is loaded/unloaded as the player moves. **Timeline Core** is persistent and room-aware. **Component Library** is the set of reusable building blocks for level design.

### 3.2 Key principles

1. **Single source of truth for size**: Every component has one exported size property. Collision shape and visual polygon are both derived from it — in the editor (`@tool`) and at runtime.
2. **Art-replaceable visual nodes**: Every component's visual representation uses a standard, well-identified child node (`Polygon2D` named "Visual" for placeholders) whose texture, material, and color are exposed as `@export` properties. Placeholder visuals (solid-color polygons) can be swapped for real art (textured sprites, animated sprites, nine-patches) directly in the Godot editor without changing any script code. Collision sync is driven by size exports, not by the visual node's type or content.
3. **Forward-only echo persistence**: Only forward-recorded branches create persistent echo actors. Reverse is navigation, not recording.
4. **No hard caps**: Echo visibility follows timeline logic. If the tick is in an echo's range and the echo hasn't collapsed, it shows.
5. **Room-aware recordings**: Frame state includes a `room_id` and `room_tick`. Echoes only display in the room they were recorded in.
6. **Room-local tick**: Each room has its own tick counter that advances by `time_direction` while the player is present. Mechanisms (especially time-scheduled ones) use room-local tick, not global tick. Global tick remains the master clock for branch management and echo frame lookup.
7. **Entity template hierarchy**: A `BasePlaceable` class provides the shared foundation for all editor-placed level entities (`@tool`, size sync, art-replaceable visuals). Mechanisms, hazards, goals extend it. New entity types are created by duplicating template scenes and configuring exports — not by writing from scratch.
8. **Time-aware animation**: Animations on any entity are handled by a `TimeAwareAnimator` component node that respects time direction (forward/reverse) and records animation state for echo replay. This is not a cosmetic layer — it is part of the framework architecture.
9. **Group-based discovery**: Level elements register themselves via groups. No manual wiring.

---

## 4. Scene Structure Proposal

### 4.1 Top-level tree (runtime)

```
Main (Node2D)                              [scenes/main.tscn]
├── TimelineManager (Node)                 [scripts/timeline_manager.gd]
├── RoomManager (Node2D)                   [scripts/room_manager.gd]
│   └── [CurrentRoom] (instanced .tscn)    — swapped on room transitions
├── ActivePlayer (CharacterBody2D)         [scenes/player.tscn]
│   ├── CollisionShape2D
│   ├── Visual (Polygon2D)
│   └── Camera2D
├── EchoContainer (Node2D)                 — echo instances spawned here
├── ScreenFX (CanvasLayer, layer=100)
│   ├── TimeTint (ColorRect)
│   └── Flash (ColorRect)
└── HUD (CanvasLayer, layer=101)
    ├── TimelineBar (Control)              [scripts/timeline_bar.gd]
    ├── StatusLabels
    ├── DebugPanel
    └── LevelCompleteBanner
```

### 4.2 Room scene template

```
Room_XX (Node2D)                           [scenes/rooms/room_XX.tscn]
├── Geometry (Node2D)
│   ├── Floor (TerrainBlock instances)
│   ├── Walls (TerrainBlock instances)
│   └── Platforms (TerrainBlock instances)
├── Mechanisms (Node2D)
│   ├── Switches (SwitchTrigger instances)
│   ├── Doors (DoorReceiver instances)
│   └── [Future mechanism instances]
├── Hazards (Node2D)
│   └── Hazard instances
├── Goals (Node2D)
│   └── GoalZone instances (if any)
├── Spawns (Node2D)
│   └── PlayerSpawn (Marker2D, group "player_spawn")
└── Exits (Node2D)
    ├── ExitRight (RoomExit, group "room_exits")
    └── ExitLeft (RoomExit, group "room_exits")
```

### 4.3 Component scene library

| Scene | Script | Type | Purpose |
|---|---|---|---|
| `terrain_block.tscn` | `terrain_block.gd` (`@tool`) | StaticBody2D | Resizable floor/wall/platform with synced visual |
| `switch.tscn` | `switch_trigger.gd` (`@tool`) | Node2D | Pressure switch with visible zone |
| `door.tscn` | `door_receiver.gd` (`@tool`) | Node2D | Blocking gate with synced body+visual |
| `hazard.tscn` | `hazard.gd` (`@tool`) | Node2D | Lethal zone with synced visual |
| `goal_zone.tscn` | `goal_zone.gd` (`@tool`) | Node2D | Level completion zone |
| `room_exit.tscn` | `room_exit.gd` | Node2D | Room transition trigger |
| `player.tscn` | `active_player.gd` | CharacterBody2D | Player character |
| `echo_player.tscn` | `echo_player.gd` | CharacterBody2D | Echo replay puppet |

---

## 5. Room-Based Structure

### 5.1 Room data model

Each room is a standalone `.tscn` scene. Room connections are defined by `RoomExit` nodes inside the room scene, each specifying:

```gdscript
## RoomExit — trigger zone at a room edge.
class_name RoomExit
extends Node2D

@export var target_room: String = ""         ## e.g. "room_02"
@export var target_entry: String = "left"    ## entry point name in the target room
@export var exit_direction: String = "right"  ## which edge: left, right, up, down
@export var exit_size: Vector2 = Vector2(16, 200)
```

Each room also has `Marker2D` entry points (e.g., `EntryLeft`, `EntryRight`) in the `"room_entries"` group.

### 5.2 RoomManager

```gdscript
## RoomManager — loads/unloads rooms, handles transitions.
extends Node2D

var current_room_id: String = ""
var current_room_node: Node2D = null
var room_registry: Dictionary = {}   # room_id → scene path

func load_room(room_id: String, entry_name: String) -> void
func unload_current_room() -> void
func _on_room_exit_triggered(exit: RoomExit) -> void
```

The RoomManager:
1. Holds a registry mapping `room_id → PackedScene` (or scene path)
2. Loads/instantiates the room scene as a child
3. On room exit: unloads old room, loads new room, positions player at the target entry point
4. Tells TimelineManager the new `room_id` so recordings are tagged
5. Updates camera limits to match the new room's bounds

### 5.3 Timeline interaction with rooms

**Frame recording** adds a `room_id` field:
```gdscript
{
	"position": Vector2,
	"velocity": Vector2,
	"facing": int,
	"on_floor": bool,
	"room_id": String,       # NEW — which room this frame was recorded in
}
```

**Echo display** checks `room_id`:
- If the echo's current frame's `room_id` matches `RoomManager.current_room_id`, the echo is shown
- Otherwise it is hidden (not collapsed — just not visible in this room)

**Mechanism discovery** runs per room. When a room loads, TimelineManager re-discovers switches/doors/hazards/goals from the new room's groups.

**Branch data persists** across rooms. The timeline tick continues normally. Room transitions do not reset or branch the timeline.

### 5.4 Camera

Per-room camera limits set by the RoomManager based on the room scene's size. The Camera2D on the player has smoothing enabled; on room transition, limits snap to the new room.

### 5.5 Room transition feel

For MVP: instant cut (snap camera to new room). Later: optional scroll/fade transition.

### 5.6 Room-local tick architecture

#### 5.6.1 The two clocks

The game has **two** kinds of time:

| Clock | Scope | Advances | Used by |
|---|---|---|---|
| **`global_tick`** | Entire game | Every `_physics_process`, by `time_direction` (+1/-1) | Branch management, echo frame lookup, frame dict key |
| **`room_tick`** | Per room | Only while player is in that room, by `time_direction` | Scheduled mechanisms, room-specific logic |

`global_tick` is the **master clock** — it never pauses. `room_tick` is a **derived counter** per room — it freezes when the player is elsewhere.

#### 5.6.2 RoomTickContext class

```gdscript
class_name RoomTickContext
extends RefCounted

var room_id: String = ""
var room_tick: int = 0
var tick_history: Dictionary = {}   # int global_tick → int room_tick

## Called each _physics_process when player is in this room.
func advance(global_tick: int, time_direction: int) -> void:
	tick_history[global_tick] = room_tick
	room_tick += time_direction

## Lookup room_tick for a historical global_tick (for echo replay / mechanism queries).
func room_tick_at(global_tick: int) -> int:
	return tick_history.get(global_tick, -1)

## Called on room restart (player death).
func reset() -> void:
	room_tick = 0
	tick_history.clear()
```

`TimelineManager` owns a `Dictionary[String → RoomTickContext]` and exposes:
- `get_current_room_tick() -> int` — reads the current room's context
- `get_room_tick_at(global_tick: int, room_id: String) -> int` — for historical lookup

#### 5.6.3 How room_tick advances

1. Player enters Room A at `global_tick=50`. `RoomTickContext` for Room A: `room_tick = 0`.
2. Each physics frame in Room A: `ctx.advance(global_tick, time_direction)` records `tick_history[global_tick] = room_tick`, then `room_tick += time_direction`.
3. After 60 frames forward: `room_tick = 60`, `tick_history` has 60 entries mapping `global_tick 50..109 → room_tick 0..59`.
4. Player leaves Room A at `global_tick=110`. `room_tick` freezes at 60.
5. Player re-enters Room A at `global_tick=200`. `room_tick` resumes at 60, continues advancing.

#### 5.6.4 Reversal behavior

When time reverses while in a room, `time_direction` flips to -1. `room_tick` decrements each frame:

- Forward ticks 0..59 → room_tick 0..59
- Player reverses at global_tick=109 (room_tick=59)
- Reverse ticks: room_tick 59, 58, 57, ... decreasing
- A scheduled mechanism at room_tick=40 was open during forward, "un-opens" as room_tick drops below 40 during reverse

**Room_tick can go negative** if the player reverses past the point they entered the room. Scheduled mechanisms with positive-tick windows simply don't trigger at negative ticks — this is correct behavior (nothing was happening before the room was first entered).

#### 5.6.5 Frame recording with room_tick

```gdscript
{
	"position": Vector2,
	"velocity": Vector2,
	"facing": int,
	"on_floor": bool,
	"room_id": String,          # which room
	"room_tick": int,           # room-local tick at this frame
	"anim_name": String,        # animation state (see §9)
	"anim_frame": int,          # animation frame (see §9)
}
```

Frames are keyed by `global_tick` in the branch's `frames` dictionary. The `room_tick` field enables mechanisms and echo validation to query room-local time.

#### 5.6.6 Echo replay and room_tick

When an echo replays in a room, the `tick_history` for that room maps the echo's `global_tick` to the `room_tick` that was active when the echo was originally recorded. This allows:
- Scheduled mechanisms to be evaluated at the historically-correct `room_tick` during echo validation
- Echo collapse detection to account for time-scheduled door states

#### 5.6.7 Room restart and room_tick

When the player dies and restarts the current room:
- `room_tick` resets to 0
- `tick_history` is cleared (fresh start for the room)
- Global timeline state (branches, echoes) may optionally persist across room restarts — see §17 Ambiguity F

---

## 6. Timeline / Echo Persistence Redesign

### 6.1 New rule: forward-only echo persistence

| Event | Echo created? | Color |
|---|---|---|
| Player seals a **forward** branch (was going forward, presses R to reverse) | **YES** — persistent RED echo | Red |
| Player seals a **reverse** branch (was going reverse, presses R to go forward again) | **NO** — reverse was temporary navigation | — |

**Why this is correct:**
- The "main timeline" moves forward. Forward passes are the player's actions on the timeline.
- Reverse is rewinding to an earlier time — like scrubbing a tape. You don't leave a recording when you rewind.
- Multiple forward passes (separated by reverse navigations) each leave their own persistent RED echo.
- This produces cleaner visual language: all past selves are RED, current self is WHITE, blue is only the screen tint during reverse mode.

### 6.2 Implementation changes

In `TimelineManager.reverse_time()`:
```gdscript
# Only spawn an echo if the sealed branch was forward-recorded
if old_branch and old_branch.direction == 1:
	_spawn_echo(old_branch)
```

Remove:
- `reversal_phase` and `_check_phase_reset()` / `_reset_phase()`
- `ECHO_COLOR_REVERSE` constant
- The "Locked - Wait for Echoes" HUD status
- Hard cap logic in `can_reverse()`

`can_reverse()` simplifies to just the cooldown check:
```gdscript
func can_reverse() -> bool:
	return ticks_since_last_reversal >= reversal_cooldown_ticks
```

### 6.3 Echo lifecycle under the new model

1. Player starts forward (branch 0, direction +1).
2. Player presses R at tick 100 → branch 0 sealed, RED echo spawned, player now reverse (branch 1, direction -1).
3. Player navigates backward in time. RED echo replays in the background.
4. Player presses R at tick 40 → branch 1 sealed, **no echo** (reverse branch), player now forward (branch 2, direction +1).
5. Player goes forward again. RED echo from branch 0 is visible for ticks 0..100.
6. Player presses R at tick 160 → branch 2 sealed, RED echo spawned, player now reverse.
7. Now: 2 RED echoes visible (branch 0 for ticks 0..100, branch 2 for ticks 40..160), plus the white player.

**No hard cap.** Echo count is bounded naturally by the player's gameplay pattern. Typically 1-3 echoes are visible at any given tick.

### 6.4 Visual language summary

| Element | Color | Meaning |
|---|---|---|
| Active player | **White** | Currently controlled character |
| Forward echo | **Red** (semi-transparent) | Persistent recorded forward-motion self |
| Screen tint (forward mode) | Subtle warm red | Time is flowing forward |
| Screen tint (reverse mode) | Subtle cool blue | Time is flowing backward (temporary) |
| Timeline bar forward segment | Red | Forward-recorded branch |
| Timeline bar reverse segment | Blue | Reverse-navigation branch |

Note: reverse branches still appear in the timeline bar (they're part of the timeline history) but they do NOT have on-screen echo actors.

---

## 7. Entity Template Hierarchy

### 7.1 Design goal

New entity types should be created by **duplicating a template scene and configuring exports in the Inspector**, not by writing code from scratch each time. The hierarchy provides reusable base classes with shared behavior (size sync, visual replacement, group registration, time awareness) so that concrete entities only define what's unique to them.

### 7.2 Class hierarchy

```
Node2D
  └── BasePlaceable                          @tool, entity_size, base_color/texture/material
      │                                      _sync_size(), _sync_placeholder_visual(), _runtime_ready()
      │                                      get_entity_rect() → Rect2
      │
      ├── BaseHazard                         hazard_size, group "hazards", get_hazard_rect()
      │   └── Hazard                         concrete: static spike pit / lava
      │
      ├── GoalZone                           zone_size, group "goals", get_goal_rect()
      │
      ├── RoomExit                           exit_size, target_room, target_entry, group "room_exits"
      │
      ├── BaseMechanismTrigger               trigger_size, activated, set_pressed(), is_actor_in_zone()
      │   ├── SwitchTrigger                  pressure plate (pressed/unpressed colors)
      │   ├── TimedSwitch                    holds for N ticks after release
      │   └── ToggleSwitch                   flips state each activation
      │
      └── BaseMechanismReceiver              triggers[], require_all, latching, evaluate_triggers()
          ├── DoorReceiver                   blocking gate (open/close collision toggle)
          ├── TimeScheduledReceiver          opens/closes on room_tick schedule (see §10.5)
          └── MovingPlatformReceiver         moves between two points when triggered

StaticBody2D
  └── TerrainBlock                           @tool, block_size/color/texture/material
      └── CrumbleBlock                       crumble_delay_ticks, resets on room restart

CharacterBody2D
  ├── ActivePlayer                           player-controlled, records frame state
  └── EchoPlayer                             replay puppet, restores frame state
```

Note: `TerrainBlock` extends `StaticBody2D` (physics body), not `BasePlaceable` (spatial anchor). Both follow the same `@tool` + visual-export pattern independently. This is intentional — terrain blocks ARE the physics body, while mechanisms/hazards/goals are spatial anchors with optional collision children.

### 7.3 BasePlaceable — the shared foundation

```gdscript
@tool
class_name BasePlaceable
extends Node2D

## ── Size (drives collision in subclasses, drives placeholder visual) ──
@export var entity_size: Vector2 = Vector2(64, 64):
    set(value):
        entity_size = value
        _sync_size()
        _sync_placeholder_visual()

## ── Visual properties (editable in Inspector, applied to placeholder Polygon2D) ──
@export_group("Visuals")
@export var base_color: Color = Color(0.5, 0.5, 0.5, 1.0):
    set(value):
        base_color = value
        _sync_placeholder_visual()

@export var base_texture: Texture2D = null:
    set(value):
        base_texture = value
        _sync_placeholder_visual()

@export var base_material: Material = null:
    set(value):
        base_material = value
        _sync_placeholder_visual()

func _ready() -> void:
    _sync_size()
    _sync_placeholder_visual()
    if not Engine.is_editor_hint():
        _runtime_ready()

## Override in subclasses for runtime-only initialization (group registration, etc.)
func _runtime_ready() -> void:
    pass

## Override in subclasses that have collision shapes.
func _sync_size() -> void:
    _sync_placeholder_visual()

## Applies visual properties to the "Visual" child if it is still a Polygon2D.
## Safe no-op if the user has replaced the Visual with Sprite2D, etc.
func _sync_placeholder_visual() -> void:
    var visual = get_node_or_null("Visual")
    if visual is Polygon2D:
        var hw = entity_size.x / 2.0
        var hh = entity_size.y / 2.0
        visual.polygon = PackedVector2Array([
            Vector2(-hw, -hh), Vector2(hw, -hh),
            Vector2(hw, hh), Vector2(-hw, hh),
        ])
        visual.color = base_color
        visual.texture = base_texture
        visual.material = base_material

## Utility: get the world-space bounding rect for this entity.
func get_entity_rect() -> Rect2:
    return Rect2(global_position - entity_size / 2.0, entity_size)
```

### 7.4 How subclasses use BasePlaceable

**BaseMechanismTrigger** (refactored from current `MechanismTrigger`):
```gdscript
@tool
class_name BaseMechanismTrigger
extends BasePlaceable

@export var trigger_size: Vector2 = Vector2(80, 24):
    set(value):
        trigger_size = value
        entity_size = trigger_size   # delegate to parent for visual sync

var activated: bool = false
signal state_changed(is_activated: bool)

func is_actor_in_zone(actor_pos: Vector2, actor_size: Vector2) -> bool:
    var my_rect := Rect2(global_position - trigger_size / 2.0, trigger_size)
    var actor_rect := Rect2(actor_pos - actor_size / 2.0, actor_size)
    return my_rect.intersects(actor_rect)

func set_pressed(value: bool) -> void:
    if activated != value:
        activated = value
        _on_state_change()
        state_changed.emit(activated)

func _on_state_change() -> void:
    pass  # Override in concrete triggers
```

**BaseMechanismReceiver** (refactored from current `MechanismReceiver`):
```gdscript
@tool
class_name BaseMechanismReceiver
extends BasePlaceable

@export var triggers: Array[NodePath] = []
@export_group("Behavior")
@export var require_all: bool = true
@export var latching: bool = false

var trigger_nodes: Array = []
var is_open: bool = false

func _runtime_ready() -> void:
    call_deferred("_resolve_triggers")

# ... evaluate_triggers(), force_close() same as current MechanismReceiver ...
```

**BaseHazard**:
```gdscript
@tool
class_name BaseHazard
extends BasePlaceable

@export var hazard_size: Vector2 = Vector2(92, 50):
    set(value):
        hazard_size = value
        entity_size = hazard_size

func _runtime_ready() -> void:
    add_to_group("hazards")

func get_hazard_rect() -> Rect2:
    return Rect2(global_position - hazard_size / 2.0, hazard_size)
```

### 7.5 Template scenes (`templates/` directory)

Templates are `.tscn` files designed for **duplication**, not direct instancing. They provide the correct node structure and base script as a starting point for new entity types.

| Template | Root Type | Script | Children | Purpose |
|---|---|---|---|---|
| `templates/placeable.tscn` | Node2D | BasePlaceable | Visual (Polygon2D) | Generic placeable starting point |
| `templates/terrain_block.tscn` | StaticBody2D | TerrainBlock | CollisionShape2D, Visual (Polygon2D) | Floor/wall/platform starting point |
| `templates/mechanism_trigger.tscn` | Node2D | BaseMechanismTrigger | Visual (Polygon2D) | New trigger type starting point |
| `templates/mechanism_receiver.tscn` | Node2D | BaseMechanismReceiver | ReceiverBody (StaticBody2D > CollisionShape2D), Visual (Polygon2D) | New receiver type starting point |
| `templates/hazard.tscn` | Node2D | BaseHazard | Visual (Polygon2D) | New hazard type starting point |
| `templates/time_aware_entity.tscn` | Node2D | BasePlaceable | Visual (Polygon2D), TimeAwareAnimator (Node) | Animated entity starting point |

### 7.6 Template vs Component scene distinction

| Aspect | Template (`templates/*.tscn`) | Component Scene (`scenes/*.tscn`) |
|---|---|---|
| **Purpose** | Starting point for new entity types | Ready-to-use instancable entity |
| **Script** | Base class (e.g., `BaseMechanismTrigger`) | Concrete class (e.g., `SwitchTrigger`) |
| **Usage** | Duplicate → rename → change script → configure | Instance directly in levels |
| **Customization** | Change everything | Change exports in Inspector |

### 7.7 Workflow: creating a new entity type

Example: creating a "Laser Emitter" mechanism trigger.

1. Duplicate `templates/mechanism_trigger.tscn` → `scenes/laser_emitter.tscn`
2. Create `scripts/laser_emitter.gd`:
   ```gdscript
   @tool
   class_name LaserEmitter
   extends BaseMechanismTrigger
   @export var beam_length: float = 200.0
   @export var beam_color: Color = Color.RED
   func _on_state_change() -> void:
       pass  # custom visual feedback
   ```
3. Open `scenes/laser_emitter.tscn`, attach `laser_emitter.gd` to the root
4. Optionally replace the Visual child with a custom sprite
5. Instance `scenes/laser_emitter.tscn` in room scenes

### 7.8 Workflow: creating a new entity variant (no new script)

Example: creating a "wide switch" that's just a bigger SwitchTrigger.

1. Instance `scenes/switch.tscn` in your room
2. In the Inspector: set `trigger_size = Vector2(160, 24)`, `unpressed_color = Color.GREEN`
3. Done. No new script, no new scene.

---

## 8. Editor-Friendly & Art-Replaceable Component Strategy

### 8.0 Core architectural rule: visual replaceability

> **This rule is implemented by the `BasePlaceable` class hierarchy (§7) and the `TerrainBlock` class. Both expose color/texture/material as `@export` properties and use `_sync_placeholder_visual()` to safely apply them only to Polygon2D visuals.**

**Every reusable level component must be built so that its visual representation can be edited, resized, retextured, re-materialed, or fully replaced in the Godot editor — with zero code changes.**

This means:
- All visual properties (color, texture, material, size) are exposed as `@export` properties with setters
- Collision sync is driven by the component's **size export**, never by the visual node's content or type
- The placeholder visual (a solid-color `Polygon2D`) is a starting point, not a permanent fixture
- A level designer can later swap the `Polygon2D` for a `Sprite2D`, `AnimatedSprite2D`, `NinePatchRect`, or any other `CanvasItem` — the script doesn't care what the visual node is, only that the size export controls collision
- No visual constants are buried in code where the editor can't reach them

**The contract:** If you can change it in the Inspector or by swapping a child node in the scene tree, the component still works. If you have to edit `.gd` to change how something looks, the component is broken.

### 8.1 The `@tool` + visual-export pattern

Every placeable level component follows this pattern:

```gdscript
@tool
class_name ComponentName
extends BaseType

## ── Size (drives collision — the source of truth for physics) ──
@export var component_size: Vector2 = Vector2(64, 64):
	set(value):
		component_size = value
		_sync_size()

## ── Visual properties (drive appearance — editable in inspector) ──
@export_group("Visuals")
@export var color: Color = Color(0.5, 0.5, 0.5, 1.0):
	set(value):
		color = value
		_sync_visuals()

@export var texture: Texture2D = null:
	set(value):
		texture = value
		_sync_visuals()

@export var material_override: Material = null:
	set(value):
		material_override = value
		_sync_visuals()

func _sync_size() -> void:
	# Update CollisionShape2D size from component_size
	# Update placeholder polygon points from component_size (if still a Polygon2D)
	# Collision is ALWAYS derived from the size export

func _sync_visuals() -> void:
	# Apply color, texture, material to the Visual child node
	# If Visual is a Polygon2D: set .color, .texture, .material
	# These are no-ops if the user has replaced the Visual with a custom node
```

**Key separation:** `_sync_size()` handles physics (always runs). `_sync_visuals()` handles appearance (applies to the default placeholder; harmless if the user replaces the Visual node).

### 8.2 Visual node conventions

Every component scene has a child node named **"Visual"** that handles rendering:

```
ComponentRoot (StaticBody2D / Node2D)   ← script with @tool + exports
├── CollisionShape2D                     ← sized by _sync_size()
└── Visual (Polygon2D)                   ← placeholder, user-replaceable
```

**Placeholder mode** (what we ship now):
- `Visual` is a `Polygon2D` with `color` set to placeholder gray/red/etc.
- Polygon points are derived from the size export
- `Polygon2D` natively supports `.texture`, `.texture_offset`, `.texture_scale`, `.texture_rotation` — so the user can assign a texture in the inspector without even swapping the node type

**Art replacement mode** (what the user does later):
- **Option A — texture on the Polygon2D:** Assign a texture in the Inspector on the existing Polygon2D. Set `color = Color.WHITE` so the texture renders at full color. The polygon shape still tiles/stretches the texture.
- **Option B — swap for Sprite2D:** Delete the Polygon2D "Visual", add a `Sprite2D` named "Visual" (or any name). The script's `_sync_size()` still controls collision. The sprite is positioned/sized manually or via `region_rect`.
- **Option C — swap for NinePatchRect / AnimatedSprite2D / custom node:** Same principle. Collision is driven by the size export. Visual is whatever node the designer places.

The script's `_sync_visuals()` uses `has_node("Visual")` and checks the node type before applying properties. If the Visual node is not a Polygon2D (i.e., the user replaced it), the function skips placeholder-specific logic. Collision sync always works regardless.

### 8.3 TerrainBlock — the core building block

```gdscript
@tool
class_name TerrainBlock
extends StaticBody2D

@export var block_size: Vector2 = Vector2(128, 32):
	set(value):
		block_size = value
		_sync_size()

@export_group("Visuals")
@export var block_color: Color = Color(0.32, 0.32, 0.38, 1.0):
	set(value):
		block_color = value
		_sync_visuals()

@export var block_texture: Texture2D = null:
	set(value):
		block_texture = value
		_sync_visuals()

@export var block_material: Material = null:
	set(value):
		block_material = value
		_sync_visuals()

@export var one_way: bool = false:
	set(value):
		one_way = value
		_sync_size()

func _sync_size() -> void:
	# CollisionShape2D.shape.size = block_size
	# If Visual is Polygon2D: update polygon = rect(block_size)
	# If one_way: set collision shape one_way flag

func _sync_visuals() -> void:
	var visual = get_node_or_null("Visual")
	if visual is Polygon2D:
		visual.color = block_color
		visual.texture = block_texture
		visual.material = block_material
	# If Visual was replaced by the user (Sprite2D, etc.), skip — they manage it
```

**Why this works for art replacement:**
- Today: solid gray block. Change `block_color` in inspector → instant.
- Tomorrow: assign a tileable stone texture to `block_texture` → Polygon2D renders it.
- Later: delete the Polygon2D, drop in a `NinePatchRect` with a 9-slice border sprite → collision still works from `block_size`.

### 8.4 Updated mechanism components

All mechanism components get the same `@tool` + visual-export treatment:

- **SwitchTrigger**: `trigger_size` (collision), `visual_size` (appearance), `unpressed_color`/`pressed_color`/`texture`/`material` exports. Placeholder: colored Polygon2D that changes color on press. Art replacement: swap Visual for animated sprite with press/release frames.
- **DoorReceiver**: `door_size` (collision), `closed_color`/`open_color`/`texture`/`material` exports. Placeholder: brown Polygon2D that hides on open. Art replacement: swap for sprite with open/closed states or an `AnimatedSprite2D`.
- **Hazard**: `hazard_size` (detection rect), `hazard_color`/`texture`/`material` exports. Placeholder: red Polygon2D. Art replacement: swap for spike sprite, animated lava, etc.
- **GoalZone**: `zone_size` (detection rect), `zone_color`/`texture`/`material` exports. Placeholder: golden Polygon2D. Art replacement: swap for flag sprite, portal animation, etc.
- **RoomExit**: `exit_size` (trigger rect), `debug_color` export (only visible in editor via `@tool` draw, hidden at runtime). No art needed — invisible trigger zone.

### 8.5 Export group organization

Every component organizes its Inspector properties into groups for clarity:

```gdscript
@export var component_size: Vector2       # top-level — always visible

@export_group("Visuals")
@export var color: Color
@export var texture: Texture2D
@export var material_override: Material

@export_group("Behavior")                 # component-specific
@export var one_way: bool                  # TerrainBlock
@export var latching: bool                 # DoorReceiver
@export var hold_ticks: int               # TimedSwitch
```

This gives level designers a clean, organized Inspector panel.

### 8.6 Level editing workflow

After this refactor, building a room in Godot looks like:
1. Create a new room scene (Node2D root)
2. Instance `terrain_block.tscn` for each floor/wall/platform
3. Select a terrain block → change `block_size` in inspector → visual updates live
4. Change `block_color` or assign `block_texture` → appearance updates live
5. Drag it to the right position
6. Instance `switch.tscn`, `door.tscn`, `hazard.tscn`, `goal_zone.tscn` as needed
7. Resize any component via its size export → collision and visual stay synced
8. Configure mechanism connections (door `triggers` array → NodePaths to switches)
9. Add a `Marker2D` in group `"player_spawn"` for spawn point
10. Add `RoomExit` nodes at edges for room connections

**Later, for art replacement:**
11. Select any component → assign a texture/material in the Visuals group, OR
12. Replace the "Visual" child node with a Sprite2D/AnimatedSprite2D/NinePatchRect
13. Collision still works — it reads from the size export, not the visual node

---

## 9. Time-Aware Animation Architecture

### 9.1 Why this is not a cosmetic layer

Animations must respect the time system. If position/state rewinds but visuals/animation don't match, the game feels broken. Time-aware animation is part of the framework architecture, not polish added later.

**Requirements:**
- Forward time → animations play forward
- Reverse time → animations play backward
- Echo replay must restore the correct animation state per frame
- Works for: player, echoes, doors, switches, platforms, hazards, future entities

### 9.2 TimeAwareAnimator — component node

A standalone `Node` added as a child of any entity that has animations. It wraps either `AnimatedSprite2D` or `AnimationPlayer` and handles direction-aware playback + state recording.

```gdscript
class_name TimeAwareAnimator
extends Node

@export var target_path: NodePath = ""   # auto-detected if empty

var _target: Node = null
var _current_animation: String = ""
var _current_frame: int = 0
var _current_progress: float = 0.0
var timeline_manager: Node = null

func _ready() -> void:
    if target_path != NodePath(""):
        _target = get_node_or_null(target_path)
    else:
        # Auto-detect AnimatedSprite2D or AnimationPlayer sibling
        for child in get_parent().get_children():
            if child is AnimatedSprite2D or child is AnimationPlayer:
                _target = child
                break
    timeline_manager = _find_timeline_manager()

func _physics_process(_delta: float) -> void:
    if _target == null or timeline_manager == null:
        return
    if Engine.is_editor_hint():
        return

    var dir: int = timeline_manager.time_direction

    if _target is AnimatedSprite2D:
        _update_animated_sprite(dir)
    elif _target is AnimationPlayer:
        _update_animation_player(dir)

func _update_animated_sprite(dir: int) -> void:
    var sprite: AnimatedSprite2D = _target
    if dir == 1:
        if not sprite.is_playing():
            sprite.play()
        sprite.speed_scale = 1.0
    else:
        # AnimatedSprite2D has no native reverse — manual frame stepping
        sprite.speed_scale = 0.0
        var frame_count = sprite.sprite_frames.get_frame_count(sprite.animation)
        if frame_count > 0:
            sprite.frame = (sprite.frame - 1) % frame_count
            if sprite.frame < 0:
                sprite.frame = frame_count - 1
    _current_animation = sprite.animation
    _current_frame = sprite.frame

func _update_animation_player(dir: int) -> void:
    var player: AnimationPlayer = _target
    if player.current_animation == "":
        return
    player.speed_scale = float(dir)  # +1.0 forward, -1.0 reverse (native support)
    _current_animation = player.current_animation
    _current_progress = player.current_animation_position

## Returns animation state for inclusion in frame recording.
func get_animation_state() -> Dictionary:
    if _target is AnimatedSprite2D:
        return {"anim_name": _current_animation, "anim_frame": _current_frame}
    elif _target is AnimationPlayer:
        return {"anim_name": _current_animation, "anim_progress": _current_progress}
    return {}

## Restores animation state from a recorded frame (for echo replay).
func apply_animation_state(state: Dictionary) -> void:
    if _target == null:
        return
    var anim_name: String = state.get("anim_name", "")
    if anim_name == "":
        return
    if _target is AnimatedSprite2D:
        var sprite: AnimatedSprite2D = _target
        if sprite.animation != anim_name:
            sprite.animation = anim_name
        sprite.frame = state.get("anim_frame", 0)
        sprite.speed_scale = 0.0  # freeze during echo replay
    elif _target is AnimationPlayer:
        var player: AnimationPlayer = _target
        if player.current_animation != anim_name:
            player.play(anim_name)
        player.seek(state.get("anim_progress", 0.0), true)
        player.speed_scale = 0.0  # freeze during echo replay

func _find_timeline_manager() -> Node:
    return get_tree().root.find_child("TimelineManager", true, false)
```

### 9.3 Integration with frame recording

In `ActivePlayer._physics_process()`:
```gdscript
var frame_state := {
    "position": global_position,
    "velocity": velocity,
    "facing": facing,
    "on_floor": is_on_floor(),
    "room_id": current_room_id,
    "room_tick": timeline_manager.get_current_room_tick(),
}
# Include animation state if animator exists
var animator = get_node_or_null("TimeAwareAnimator")
if animator:
    frame_state.merge(animator.get_animation_state())
```

In `EchoPlayer.apply_frame()`:
```gdscript
func apply_frame(frame: Dictionary) -> void:
    global_position = frame.get("position", global_position)
    var animator = get_node_or_null("TimeAwareAnimator")
    if animator:
        animator.apply_animation_state(frame)
```

### 9.4 Mechanism animations (deterministic, not recorded)

Mechanisms (doors, moving platforms) can have `TimeAwareAnimator` children, but their animation state is **not** recorded in branch frame data. Mechanism animation is deterministic from inputs:
- A door's animation state is determined by `is_open` (from triggers or schedule)
- A moving platform's position is determined by trigger state + elapsed time
- `TimeAwareAnimator` handles direction-aware playback (open→forward, close→reverse)

This works because mechanism state is recalculated each frame from the same inputs. Given the same `room_tick` and trigger states, the mechanism is in the same state. No recording needed.

### 9.5 Opting in to time-aware animation

An entity becomes time-aware by adding a `TimeAwareAnimator` child node:

```
MyEntity (Node2D)
├── Visual (AnimatedSprite2D)       ← has actual sprite frames
└── TimeAwareAnimator (Node)        ← handles direction + recording
```

Entities without a `TimeAwareAnimator` are animation-free (placeholder mode). The `get_node_or_null("TimeAwareAnimator")` checks in ActivePlayer/EchoPlayer gracefully return null, and no animation data is recorded or restored.

### 9.6 What animation data is recorded per frame

| Field | Type | Present when | Source |
|---|---|---|---|
| `anim_name` | String | AnimatedSprite2D or AnimationPlayer exists | Current animation name |
| `anim_frame` | int | AnimatedSprite2D | Current frame index |
| `anim_progress` | float | AnimationPlayer | Current playback position in seconds |

These fields are optional. Old frame dicts without them work fine via `.get()` with defaults.

---

## 10. Mechanism System Strategy

### 10.1 Current base classes (refactor to extend BasePlaceable)

- `MechanismTrigger` → becomes `BaseMechanismTrigger extends BasePlaceable` (see §7.4)
- `MechanismReceiver` → becomes `BaseMechanismReceiver extends BasePlaceable` (see §7.4)

These are solid. The refactor changes the extends chain (Node2D → BasePlaceable) and adds `@tool`, but preserves the API.

### 10.2 Current concrete types (keep + upgrade to @tool)

- `SwitchTrigger` → add `@tool`, size setter, extends `BaseMechanismTrigger`
- `DoorReceiver` → add `@tool`, size setter, extends `BaseMechanismReceiver`

### 10.3 New concrete types to add

| Type | Base | Behavior | Phase | Why it validates the framework |
|---|---|---|---|---|
| **TimedSwitch** | BaseMechanismTrigger | Stays active for N ticks after actor leaves the zone | Phase 4 | Tests temporal interaction — echo can "preload" it |
| **ToggleSwitch** | BaseMechanismTrigger | Flips state each time an actor enters | Phase 4 | Tests non-pressure-based activation |
| **TimeScheduledReceiver** | BaseMechanismReceiver | Opens/closes on a room_tick schedule | Phase 4 | Tests time-driven mechanisms (see §10.5) |
| **MovingPlatform** | BaseMechanismReceiver | Moves between two positions when triggered | Phase 4 | Tests a receiver that changes geometry |
| **CrumbleBlock** | TerrainBlock | Collapses after player stands on it | Phase 4 | Tests destructible geometry |
| **OneWayGate** | Standalone (@tool) | Passage in one direction only | Phase 5 | Directional physics |

### 10.4 What should be scene-based vs script-based vs data-driven

- **Scene-based**: Every concrete mechanism type gets a `.tscn` scene for instancing. The scene contains the node structure (body, visual, shape). The script provides behavior. The "Visual" child node ships as a placeholder Polygon2D but can be replaced with any CanvasItem in the editor for art replacement (see §8.2).
- **Script-based**: Behavior (trigger logic, receiver logic, visual feedback) lives in GDScript classes. Base classes define the API; subclasses implement specifics. Visual feedback (e.g., color changes on switch press) uses the `_sync_placeholder_visual()` pattern inherited from `BasePlaceable` that gracefully skips non-Polygon2D visual nodes.
- **Data/config driven**: Connection wiring (which triggers feed which receivers) is done via `@export var triggers: Array[NodePath]` set in the editor. Latching/require_all/timing parameters are exports. Visual properties (colors, textures, materials) are exports in the "Visuals" group. No code changes needed to create new puzzle configurations or replace placeholder art.

### 10.5 Time-scheduled mechanisms (room-local tick)

A new receiver type: `TimeScheduledReceiver extends BaseMechanismReceiver`. Opens/closes based on room_tick time windows, independent of triggers.

```gdscript
@tool
class_name TimeScheduledReceiver
extends BaseMechanismReceiver

## Each Vector2i = one time window: (open_room_tick, close_room_tick).
## The receiver is open when room_tick falls within ANY window.
@export var schedule: Array[Vector2i] = []

## -1 = no loop. >0 = schedule repeats every N room_ticks.
@export var loop_period: int = -1

func evaluate_schedule(room_tick: int) -> void:
    var effective_tick := room_tick
    if loop_period > 0 and room_tick >= 0:
        effective_tick = room_tick % loop_period

    var should_be_open := false
    for window in schedule:
        if effective_tick >= window.x and effective_tick < window.y:
            should_be_open = true
            break

    if is_open != should_be_open:
        is_open = should_be_open
        _on_state_change(is_open)
```

**Editor authoring:**
- In the Inspector, `schedule` is an expandable `Array[Vector2i]`
- Each entry is one time window: `x` = open tick, `y` = close tick (in room-local ticks)
- Example: `[(60, 120), (180, 240)]` with `loop_period = 300` → cyclic gate that opens for 60 ticks, closes for 60, opens for 60, closes for 60, repeats

**Integration with TimelineManager:**
- Registered in `"scheduled_receivers"` group
- `TimelineManager._update_mechanisms()` calls `receiver.evaluate_schedule(get_current_room_tick())` each frame
- Uses room-local tick so schedules are relative to room activity, not global time

**Interaction with echoes:**
- When validating echo collision against a scheduled door, the door's state at the echo's historical moment is computed from `room_tick_at(echo_global_tick)` via the room's `RoomTickContext.tick_history`
- If the door was open when the echo originally passed through but is now closed, the echo collapses — this is correct game behavior (the player's actions changed the timeline)

---

## 11. Collision / Visual Alignment Strategy

### 11.1 The problem

The current level has 7 StaticBody2D geometry nodes, each with a separate CollisionShape2D and Polygon2D. These were created by code with matching sizes, but once the user edits them in the Godot editor (dragging, scaling), they drift apart. The user-edited `level_01.tscn` shows this: walls have position offsets and scale factors on Visual children that no longer match the collision shapes.

Mechanism components (Switch, Door, Hazard, Goal) have the same issue: the exported size rebuilds the visual in `_ready()`, overwriting any editor edits to the polygon, but the result isn't visible until runtime.

### 11.2 The solution: size-driven collision, decoupled visuals

**Rule:** The `@export var size` property is always the single source of truth for **collision**. The collision shape is derived from it. The visual node is a **separate concern** — it can be the default Polygon2D placeholder, a textured Polygon2D, a Sprite2D, or any other node. The script syncs the placeholder visual as a convenience but does not require any specific visual node to function.

**For TerrainBlock** (static geometry):
```
TerrainBlock (StaticBody2D) — @tool script
├── CollisionShape2D        — shape.size = block_size  (always synced)
└── Visual (Polygon2D)      — placeholder: polygon = rect(block_size), color = block_color
							  art mode: user replaces with Sprite2D, NinePatchRect, etc.
```
Changing `block_size` in the inspector always updates the CollisionShape2D. If the Visual is still a Polygon2D, its polygon points also update. If the user replaced it, collision still works.

**For DoorReceiver** (dynamic obstacle):
```
DoorReceiver (Node2D) — @tool script
├── DoorBody (StaticBody2D)
│   └── CollisionShape2D   — shape.size = door_size  (always synced)
└── Visual (Polygon2D)     — placeholder: rect(door_size), color = closed_color
							  art mode: user replaces with sprite sheet
```

**For Hazard, Switch, GoalZone** (zones):
```
Hazard (Node2D) — @tool script
└── Visual (Polygon2D)     — placeholder: polygon = rect(hazard_size), color = red
							  art mode: user replaces with animated sprite
```
(No collision shape — detection is via Rect2 checks from the exported size, which always works regardless of visual node type.)

### 11.3 What this looks like in practice

**Today (placeholder visuals):**
1. Instance a `terrain_block.tscn` into your room
2. In the Inspector, set `block_size = Vector2(400, 32)` → the block visually resizes to a 400×32 platform
3. Drag it to position → collision and visual move together (they're children)
4. Change `block_color` → visual updates instantly
5. Assign `block_texture` → Polygon2D renders the texture, tiled/stretched

**Later (art replacement):**
6. Select the terrain block → in the scene tree, delete the "Visual" Polygon2D
7. Add a `Sprite2D` (or `NinePatchRect`, `AnimatedSprite2D`) as a child, name it anything
8. Assign your real art asset to the sprite
9. Collision **still works** — `block_size` still drives the CollisionShape2D
10. Resize via `block_size` export → collision updates, you manually adjust sprite to match (or use region_rect)

**The guarantee:** Collision sync never breaks because it reads from the size export, not from the visual node. Swapping, deleting, or modifying the visual child has zero effect on physics.

### 11.4 Why _sync_visuals() is safe with replaced nodes

```gdscript
func _sync_visuals() -> void:
    var visual = get_node_or_null("Visual")
    if visual is Polygon2D:
		# Only touches the node if it's still the placeholder Polygon2D
		visual.color = block_color
		visual.texture = block_texture
		visual.material = block_material
	# If the user replaced Visual with a Sprite2D → this block is skipped
	# If the user deleted Visual entirely → get_node_or_null returns null → safe
```

This pattern means the script never fights against the user's art changes.

---

## 12. Timeline UI / Color Language Strategy

### 12.1 Screen tint (keep current, minor adjustments)

The current red/blue tint system in `main.gd` is correct:
- Forward: `TINT_FORWARD = Color(0.55, 0.08, 0.04, 0.06)` — very subtle warm red
- Reverse: `TINT_REVERSE = Color(0.04, 0.1, 0.55, 0.14)` — noticeable cool blue
- Smooth tween transition on reversal

This should be kept. The only change: because reverse no longer creates persistent blue echoes, the blue is ONLY the screen tint + timeline bar segments. This makes the blue language cleaner.

### 12.2 Timeline bar (keep + update for new model)

The current `timeline_bar.gd` is solid:
- Multi-lane horizontal bar showing all branches
- Red segments for forward branches, blue for reverse
- White pivot markers at reversal points
- White current-tick marker with direction arrow
- Direction chevrons inside segments

Changes needed:
- Branches that did NOT produce echoes (reverse branches) should be drawn slightly dimmer or with a different style (dashed? lower alpha?) to visually distinguish "this was navigation" from "this left an echo"
- Active forward branches should be the brightest
- Consider adding a small icon or marker on branches that have active echoes

### 12.3 HUD status (simplify for new model)

Remove:
- "Locked - Wait for Echoes" status (no hard cap)
- `reversal_phase` display

Add/update:
- Direction: `">> FORWARD"` (red) or `"<< REVERSE"` (blue)
- Tick counter
- Reversal availability: `"R: Reverse"` (green if available, grey if on cooldown)
- Visible echo count
- Debug panel (F3): branch list, echo states, room_id

### 12.4 Color legend

Update to match the new model:
```
WHITE = You    RED = Forward Echo    BLUE = Reverse Time
```

(No longer "BLUE = Reverse Echo" since reverse echoes don't exist.)

---

## 13. Celeste-Inspired Foundational Systems

### 13.1 Goal

Identify foundational systems that make the framework stronger as a Celeste-quality 2D platformer base. Not "copy Celeste" — rather, plan the right abstractions early so they don't need painful retrofitting later.

### 13.2 Phase 1 additions: player feel (lightweight, no architecture changes)

These are small additions to `ActivePlayer._physics_process()` with `@export` controls. They only affect input→velocity mapping. The recorded frame state (position/velocity) captures their effects. No timeline system changes needed.

**1. Coyote time:**
```gdscript
@export var coyote_frames: int = 6
var _coyote_counter: int = 0

# In _physics_process:
if is_on_floor():
    _coyote_counter = coyote_frames
elif _coyote_counter > 0:
    _coyote_counter -= 1

if Input.is_action_just_pressed("jump") and (is_on_floor() or _coyote_counter > 0):
    velocity.y = JUMP_VELOCITY
    _coyote_counter = 0
```

**2. Jump buffering:**
```gdscript
@export var jump_buffer_frames: int = 6
var _jump_buffer_counter: int = 0

# In _physics_process:
if Input.is_action_just_pressed("jump"):
    _jump_buffer_counter = jump_buffer_frames
elif _jump_buffer_counter > 0:
    _jump_buffer_counter -= 1

if is_on_floor() and _jump_buffer_counter > 0:
    velocity.y = JUMP_VELOCITY
    _jump_buffer_counter = 0
```

**3. Variable jump height:**
```gdscript
@export var jump_cut_multiplier: float = 0.4

# In _physics_process:
if Input.is_action_just_released("jump") and velocity.y < 0:
    velocity.y *= jump_cut_multiplier
```

### 13.3 Phase 2 additions: room system improvements

**4. Room restart from entry point:** On death, restart only the current room (not the entire level). Player respawns at the room's entry point. Room-local tick resets. Global timeline state optionally persists (see §17 Ambiguity F).

**5. Camera snap to room bounds:** `RoomManager` sets `Camera2D` limits from the room scene's dimensions. On room transition, limits snap to the new room. Smoothing only applies within a room.

### 13.4 Phase 4 additions: platforming content types

**6. Moving platforms** — `MovingPlatformReceiver extends BaseMechanismReceiver`:
- Uses `AnimatableBody2D` (Godot's preferred type for solids that carry the player)
- `@export var point_a: Vector2`, `@export var point_b: Vector2`, `@export var travel_speed: float`
- Moves toward `point_b` when triggered (open), `point_a` when untriggered (closed)
- Can also respond to time-scheduled triggers for predictable movement patterns

**7. Crumble blocks** — `CrumbleBlock extends TerrainBlock`:
- `@export var crumble_delay_ticks: int = 30`
- Timer starts when player touches the top surface
- After delay: collision disables, visual fades/disappears
- Resets on room restart
- Works with time system: during reversal, crumble timer "un-ticks" (restoring the block)

**8. One-way platforms** — `@export var one_way: bool` on `TerrainBlock`:
- Sets Godot's built-in `one_way_collision` on the `CollisionShape2D`
- Player falls through from below, lands normally from above
- No additional script logic — Godot handles the physics natively

### 13.5 Phase 5 considerations (not built now, but architecture should not block)

| System | Notes |
|---|---|
| **Dash mechanic** | Needs a velocity-override state; can be an ActivePlayer state machine extension |
| **Wall slide / wall jump** | Needs wall detection raycasts on ActivePlayer; exports for slide speed, wall jump velocity |
| **Spring/bounce pads** | A new `BaseMechanismTrigger` subclass that applies impulse to actors in zone |
| **Conveyor belts** | A TerrainBlock variant that applies horizontal velocity to actors standing on it |
| **Animated room transitions** | RoomManager hooks for scroll/fade/wipe transitions between rooms |
| **Particle effects** | Echo collapse particles, reversal flash — use Godot GPUParticles2D, not custom |

These do NOT need to be designed now, but the entity hierarchy (§7), animation system (§9), and room architecture (§5) should not make them difficult to add later. The current architecture supports all of these as either new entity subclasses or extensions to existing systems.

### 13.6 What to plan now vs later

| System | Plan now? | Build now? | Why |
|---|---|---|---|
| Coyote time, jump buffer, variable jump | Yes | Yes (Phase 1) | Trivial, huge feel improvement |
| Room restart from entry | Yes | Yes (Phase 2) | Essential for playtesting |
| Camera per room | Yes | Yes (Phase 2) | Part of room system |
| Moving platforms | Yes | Phase 4 | Validates mechanism system |
| Crumble blocks | Yes | Phase 4 | Validates TerrainBlock extensibility |
| One-way platforms | Yes | Phase 4 | One export, free from Godot |
| Dash, wall mechanics | Not yet | Phase 5+ | Needs movement state machine first |
| Spring pads, conveyors | Not yet | Phase 5+ | Entity subclasses, straightforward later |

---

## 14. Migration Strategy

### 14.1 What to keep

| File | Keep? | Notes |
|---|---|---|
| `branch_track.gd` | **Keep as-is** | Data model is correct |
| `player.tscn` | **Keep as-is** | White player, correct layers |
| `echo_player.tscn` | **Keep as-is** | Correct structure |
| `project.godot` | **Keep, update as needed** | May add input actions |

### 14.2 What to refactor

| File | Change | Reason |
|---|---|---|
| `mechanism_trigger.gd` | Rename class → `BaseMechanismTrigger`, extend `BasePlaceable`, add `@tool` | Entity hierarchy (§7) |
| `mechanism_receiver.gd` | Rename class → `BaseMechanismReceiver`, extend `BasePlaceable`, add `@tool` | Entity hierarchy (§7) |
| `switch_trigger.gd` | Extend `BaseMechanismTrigger`, add `@tool`, size setter | Editor-friendly + hierarchy |
| `door_receiver.gd` | Extend `BaseMechanismReceiver`, add `@tool`, size setter | Editor-friendly + hierarchy |
| `hazard.gd` | Extend `BaseHazard` (or `BasePlaceable`), add `@tool`, size setter | Editor-friendly + hierarchy |
| `goal_zone.gd` | Extend `BasePlaceable`, add `@tool`, size setter | Editor-friendly + hierarchy |
| `active_player.gd` | Add room_id/room_tick/animation in frame recording, coyote time, jump buffer, variable jump | Room tick (§5.6), animation (§9), Celeste (§13) |
| `echo_player.gd` | Add room_id filtering, animation state restoration via TimeAwareAnimator | Room-aware + animation |
| `timeline_manager.gd` | Add room_tick_contexts, forward-only echoes, scheduled mechanism evaluation, room-aware discovery, remove reversal_phase | Echo model (§6), room tick (§5.6), scheduled mechanisms (§10.5) |
| `main.gd` | Extract room management to RoomManager, thin out | Layered separation |
| `hud.gd` | Simplify for new model, remove phase display | No more hard cap |
| `timeline_bar.gd` | Dim reverse-only branches, add echo indicators | Visual distinction |

### 14.3 What to create new

| File | Type | Phase | Purpose |
|---|---|---|---|
| `scripts/base_placeable.gd` | Script (`@tool`) | 1 | Root class for all placeable entities (§7.3) |
| `scripts/base_hazard.gd` | Script (`@tool`) | 1 | Base class for hazard entities (§7.4) |
| `scripts/terrain_block.gd` | Script (`@tool`) | 1 | Resizable static geometry component |
| `scenes/terrain_block.tscn` | Scene | 1 | Instancable terrain block |
| `templates/placeable.tscn` | Template | 1 | Generic placeable starting point |
| `templates/terrain_block.tscn` | Template | 1 | Floor/wall/platform starting point |
| `templates/mechanism_trigger.tscn` | Template | 1 | New trigger type starting point |
| `templates/mechanism_receiver.tscn` | Template | 1 | New receiver type starting point |
| `templates/hazard.tscn` | Template | 1 | New hazard type starting point |
| `scripts/room_tick_context.gd` | Script | 2 | Room-local tick state (§5.6.2) |
| `scripts/room_manager.gd` | Script | 2 | Room loading, transitions, camera limits |
| `scripts/room_exit.gd` | Script (`@tool`) | 2 | Room transition trigger zone |
| `scenes/room_exit.tscn` | Scene | 2 | Instancable room exit |
| `scenes/rooms/room_01.tscn` | Scene | 2 | First room (rebuilt from level_01 geometry) |
| `scenes/rooms/room_02.tscn` | Scene | 2 | Second room (demonstrates transitions) |
| `scripts/time_aware_animator.gd` | Script | 3 | Animation component for time-aware playback (§9.2) |
| `templates/time_aware_entity.tscn` | Template | 3 | Animated entity starting point |
| `scripts/time_scheduled_receiver.gd` | Script (`@tool`) | 4 | Time-window gate mechanism (§10.5) |
| `scenes/time_scheduled_door.tscn` | Scene | 4 | Instancable time-scheduled door |
| `scripts/timed_switch.gd` | Script (`@tool`) | 4 | Hold-for-N-ticks switch |
| `scenes/timed_switch.tscn` | Scene | 4 | Instancable timed switch |
| `scripts/moving_platform.gd` | Script (`@tool`) | 4 | Moving platform receiver |
| `scenes/moving_platform.tscn` | Scene | 4 | Instancable moving platform |
| `scripts/crumble_block.gd` | Script (`@tool`) | 4 | Crumble block extending TerrainBlock |
| `scenes/crumble_block.tscn` | Scene | 4 | Instancable crumble block |

### 14.4 What to retire

| File | Reason |
|---|---|
| `scenes/level_01.tscn` | Replaced by room scenes in `scenes/rooms/` |
| `IMPLEMENTATION_NOTES.md` | Outdated (references old model); fold still-relevant notes into this plan or code comments |

---

## 15. Build Order / Implementation Phases

### Phase 1: Entity Foundation + Player Feel — HIGHEST PRIORITY

**Goal:** Establish the entity hierarchy, `@tool` editing, template system, and basic player feel.

1. **Create `base_placeable.gd`** — `BasePlaceable` class with `entity_size`, `base_color`/`base_texture`/`base_material` exports, `_sync_size()`, `_sync_placeholder_visual()`, `_runtime_ready()` (§7.3).
2. **Create `base_hazard.gd`** — `BaseHazard` extending `BasePlaceable` (§7.4).
3. **Create `terrain_block.gd`** — `@tool` StaticBody2D with `block_size`/`block_color`/`block_texture`/`block_material` exports (§8.3).
4. **Create `terrain_block.tscn`** — instance-ready scene.
5. **Refactor `mechanism_trigger.gd`** → `BaseMechanismTrigger extends BasePlaceable`, add `@tool` (§7.4).
6. **Refactor `mechanism_receiver.gd`** → `BaseMechanismReceiver extends BasePlaceable`, add `@tool` (§7.4).
7. **Upgrade `switch_trigger.gd`** — extend `BaseMechanismTrigger`, add `@tool`, size setters.
8. **Upgrade `door_receiver.gd`** — extend `BaseMechanismReceiver`, add `@tool`, size setters.
9. **Upgrade `hazard.gd`** — extend `BaseHazard`, add `@tool`, size setters.
10. **Upgrade `goal_zone.gd`** — extend `BasePlaceable`, add `@tool`, size setters.
11. **Add player feel** to `active_player.gd`: coyote time, jump buffering, variable jump height (§13.2).
12. **Create template scenes** in `templates/`: placeable, terrain_block, mechanism_trigger, mechanism_receiver, hazard (§7.5).
13. **Test** all components in Godot editor: instance them, change sizes/colors/textures, verify visual updates.

### Phase 2: Room Architecture + Room-Local Tick

**Goal:** Support multiple rooms with transitions and room-local tick.

1. **Create `room_tick_context.gd`** — `RoomTickContext` class (§5.6.2).
2. **Create `room_exit.gd`** — `@tool` Node2D extending `BasePlaceable`, registers in `"room_exits"` group.
3. **Create `room_exit.tscn`** — instance-ready scene with visual indicator.
4. **Create `room_manager.gd`** — loads/unloads rooms, handles transitions, updates camera limits, notifies TimelineManager of room changes.
5. **Integrate room_tick into `timeline_manager.gd`** — add `room_tick_contexts` dict, `_update_room_tick()`, `get_current_room_tick()`.
6. **Refactor `main.gd`** — delegate room loading to RoomManager. Keep player, EchoContainer, ScreenFX, HUD at Main level.
7. **Add `room_id` + `room_tick` to frame recording** in `active_player.gd`.
8. **Rebuild level_01 as `room_01.tscn`** — using TerrainBlock instances. Move to `scenes/rooms/`.
9. **Create `room_02.tscn`** — simple second room connected to room_01.
10. **Room restart on death** — restart current room from entry point, reset room_tick (§13.3).
11. **Camera limits per room** — RoomManager sets Camera2D limits from room bounds.
12. **Re-run mechanism discovery** on room change — `TimelineManager._discover_level()` via `call_deferred`.
13. **Test** room transitions, room-local tick advancing/freezing, camera snapping.

### Phase 3: Timeline/Echo Model + Animation System

**Goal:** Forward-only echo persistence, time-aware animation framework.

1. **Modify `timeline_manager.gd`**:
   - Remove `reversal_phase`, `_check_phase_reset()`, `_reset_phase()`
   - In `reverse_time()`: only spawn echo if `old_branch.direction == 1`
   - Simplify `can_reverse()` to cooldown-only check
   - Remove `ECHO_COLOR_REVERSE` — all echoes use `ECHO_COLOR_FORWARD`
2. **Create `time_aware_animator.gd`** — `TimeAwareAnimator` component node (§9.2).
3. **Add animation state to frame recording** in `active_player.gd` — merge `get_animation_state()` from TimeAwareAnimator (§9.3).
4. **Update `echo_player.gd`**:
   - Room_id filtering: show/hide based on `frame.room_id` match
   - Animation state restoration via TimeAwareAnimator (§9.3)
5. **Simplify `hud.gd`** — remove phase display, update legend text.
6. **Update `timeline_bar.gd`** — dim reverse-only branches, mark echo-creating branches.
7. **Create `templates/time_aware_entity.tscn`** — template with TimeAwareAnimator child.
8. **Test** full echo lifecycle: forward → reverse → forward → verify only RED echoes, animation state correct on echoes, multiple echoes accumulate.

### Phase 4: Mechanism Expansion + Celeste Mechanics

**Goal:** Validate the framework with new mechanism types and platforming content.

1. **Create `time_scheduled_receiver.gd`** — `TimeScheduledReceiver` with `schedule` and `loop_period` exports (§10.5).
2. **Create `scenes/time_scheduled_door.tscn`** — instancable time-scheduled door.
3. **Create `timed_switch.gd`** — `TimedSwitch extends BaseMechanismTrigger`, holds for N ticks.
4. **Create `scenes/timed_switch.tscn`**.
5. **Create `moving_platform.gd`** — `MovingPlatformReceiver extends BaseMechanismReceiver`, uses `AnimatableBody2D` (§13.4).
6. **Create `scenes/moving_platform.tscn`**.
7. **Create `crumble_block.gd`** — `CrumbleBlock extends TerrainBlock`, crumble delay + reset (§13.4).
8. **Create `scenes/crumble_block.tscn`**.
9. **Add one-way platform support** — `@export var one_way: bool` on TerrainBlock (§13.4).
10. **Add scheduled mechanism evaluation** to `TimelineManager._update_mechanisms()`.
11. **Build puzzles** in room_02 using timed switch, time-scheduled door, and/or moving platform.
12. **Polish** timeline bar readability, screen tint alpha values.

### Phase 5: Future (not in this refactor)

- Dash mechanic (ActivePlayer state machine extension)
- Wall slide / wall jump (wall detection raycasts)
- Spring/bounce pads (BaseMechanismTrigger subclass with impulse)
- Conveyor belts (TerrainBlock variant with horizontal velocity)
- Animated room transitions (scroll/fade/wipe)
- Sound effects
- Particle effects for echo collapse/reversal
- Complex multi-room level designs
- ToggleSwitch, OneWayGate

---

## 16. Risks and Tradeoffs

### Risk 1: `@tool` scripts running in the editor (MEDIUM)

`@tool` scripts execute in the editor. Bugs in `@tool` code can crash the editor or corrupt scenes. Mitigation: keep `@tool` logic minimal (only visual sync in setters), guard runtime-only code with `if Engine.is_editor_hint(): return`. The `BasePlaceable._runtime_ready()` pattern centralizes this guard.

### Risk 2: Room transitions and timeline state (HIGH)

When the player transitions rooms, the TimelineManager needs to re-discover level elements (switches, doors, hazards) for the new room. Timing matters — the new room's nodes must be in the tree before discovery runs. Mitigation: use `call_deferred` for discovery after room load. Test thoroughly.

### Risk 3: Echo room_id filtering (MEDIUM)

Echoes that were recorded in a different room are hidden but not collapsed. When the player returns to that room, the echoes should reappear. This requires that echo nodes are NOT freed just because they're in a different room. The current `_update_echoes()` hides echoes when `branch.has_tick(global_tick)` is false — adding room_id filtering is analogous but needs careful integration.

### Risk 4: Rebuilding level_01 as room_01 (LOW)

The current level_01.tscn has user-edited positions and sizes. Rebuilding it with TerrainBlock instances means re-creating the layout. This is straightforward but tedious. The user's editor adjustments to positions should be preserved by placing TerrainBlocks at the same coordinates.

### Risk 5: Forward-only echoes change puzzle design space (MEDIUM)

With reverse branches not creating echoes, some puzzle patterns become impossible. However, this is intentional — the user explicitly wants this model.

### Risk 6: No hard cap means potential visual clutter (LOW)

Without `reversal_phase`, a player who reverses many times could accumulate many forward echoes. In practice, echoes are only visible when the current tick is in their recorded range, so typically 1-3 are visible at once.

### Risk 7: Room-local tick complexity (MEDIUM)

`room_tick` can go negative if the player reverses past the room entry point. Scheduled mechanisms must handle negative ticks gracefully (their windows simply don't match, which is a no-op). `tick_history` grows by 1 entry per physics frame per active room (~36K entries for 10 minutes at 60fps) — lightweight `Dictionary[int→int]`, but should be monitored in long sessions.

### Risk 8: TimeAwareAnimator reverse playback (MEDIUM)

`AnimatedSprite2D` has no native reverse playback. The `TimeAwareAnimator` manually decrements the frame counter, which works but frame timing must align with physics ticks. `AnimationPlayer` supports `speed_scale = -1` natively, so prefer it for complex multi-track animations. Recommend using `AnimationPlayer` as the default for entities with reversal-sensitive animations.

### Risk 9: Entity hierarchy depth (LOW)

`BasePlaceable → BaseMechanismTrigger → SwitchTrigger` is 3 levels of inheritance. Godot handles this fine, but `@tool` + multi-level inheritance can have editor quirks (setter order, `_ready()` call order). Mitigation: keep `@tool` logic concentrated in `BasePlaceable`, override only `_sync_size()` and `_runtime_ready()` in subclasses. Test each level of the hierarchy in the editor independently.

---

## 17. Ambiguities Needing Human Confirmation

### A. Room-scoped vs global timeline state

**Question:** When the player transitions from room_01 to room_02 and then reverses time, should echoes from room_01 appear if the tick re-enters their range?

**My recommendation:** Yes — echoes persist in the room they were recorded in. When the player is in room_02, room_01 echoes are hidden (wrong room). If the player transitions back to room_01, those echoes reappear at their recorded positions for the current tick. Timeline state is global, echo display is room-local.

### B. Should room transitions be instantaneous or animated?

**My recommendation:** Start with instant transitions (snap cut). Add optional scroll/fade later as polish.

### C. How many rooms for the initial refactor?

**My recommendation:** 2 rooms. Room_01 is the existing test level rebuilt with TerrainBlocks. Room_02 is a new simple room. Enough to prove the room system works.

### D. Should reverse branches appear in the timeline bar at all?

**My recommendation:** Yes, but dimmer. Drawing them in low-alpha blue preserves context without implying they created persistent echoes.

### E. Should the `@export var max_reversals` limit return?

**My recommendation:** Keep as an optional per-level export (default -1 = unlimited). One line in `can_reverse()`.

### F. Room-local tick reset on room restart

**Question:** When the player dies and restarts the current room, should `room_tick` reset to 0? And should `tick_history` be cleared?

**My recommendation:** Yes, room_tick resets to 0. tick_history should be cleared for a fresh start. If echoes from a previous room attempt need to persist (e.g., for a "ghost replay" feature), that would require keeping old tick_history entries — but for now, clean slate is simpler and matches the "room restart = fresh attempt" mental model.

### G. Mechanism state in rooms the player is not in

**Question:** Should scheduled mechanisms in inactive rooms evaluate at their frozen room_tick, or not evaluate at all?

**My recommendation:** Don't evaluate — mechanisms are paused when the room is inactive. Echoes in inactive rooms are hidden anyway. When the player returns, mechanisms resume from the frozen room_tick. This is the simplest correct behavior and avoids phantom mechanism state updates.

### H. BasePlaceable class_name renames

**Question:** Should the existing `MechanismTrigger`/`MechanismReceiver` class names be renamed to `BaseMechanismTrigger`/`BaseMechanismReceiver`?

**My recommendation:** Yes, for consistency with the template hierarchy naming (`BasePlaceable`, `BaseHazard`, `BaseMechanismTrigger`, `BaseMechanismReceiver`). This is a breaking rename for any code referencing the old class names, but all references are internal to this project. A project-wide find-and-replace handles it.

---

## 18. Summary of Biggest Changes

1. **TerrainBlock component** replaces raw StaticBody2D + manual Polygon2D pairs for all static geometry. `@tool` script ensures visual/collision stay synced in the editor.

2. **All level components get `@tool`** so that exported size properties produce immediate visual feedback in the Godot editor.

3. **Art-replaceable visual architecture**: Every component ships with a placeholder `Polygon2D` visual, but exposes color/texture/material as `@export` properties. The "Visual" child can be swapped for any `CanvasItem` directly in the editor — no code changes. Collision is driven by the size export, completely decoupled from the visual node type.

4. **Forward-only echo persistence** replaces the current "echo everything + hard cap" model. Only forward-recorded branches create persistent RED echoes. Reverse is temporary navigation. No hard cap on echo count.

5. **Room-based architecture** with a RoomManager that loads/unloads room scenes. Room transitions at edges. Timeline state persists across rooms, echo display is room-local.

6. **Layered separation** between game shell (player, FX, HUD), timeline core, room management, and room content. main.gd becomes thinner.

7. **Room-aware frame recording** adds `room_id` and `room_tick` to each recorded frame state.

8. **Room-local tick system** (NEW in v3): Each room has its own `room_tick` counter that advances with `time_direction` while the player is present, and freezes when the player is elsewhere. Time-scheduled mechanisms use `room_tick`, not `global_tick`. A `RoomTickContext` class tracks the mapping between global and room-local ticks for echo replay.

9. **Entity template hierarchy** (NEW in v3): `BasePlaceable` base class provides shared `@tool` foundation for all editor-placed entities. `BaseMechanismTrigger`, `BaseMechanismReceiver`, `BaseHazard` extend it. A `templates/` directory with 6 template scenes enables creating new entity types by duplicating and configuring — not writing from scratch.

10. **Time-aware animation** (NEW in v3): `TimeAwareAnimator` component node handles direction-aware playback (forward/reverse) and animation state recording for echo replay. Animation state (`anim_name`, `anim_frame`) is included in frame recordings. Entities opt in by adding a TimeAwareAnimator child node.

11. **Time-scheduled mechanisms** (NEW in v3): `TimeScheduledReceiver` with editor-authored `schedule: Array[Vector2i]` time windows using room-local tick. Supports `loop_period` for cyclic patterns. Enables puzzle patterns based on timed gates that open/close on a room-local schedule.

12. **Celeste-inspired player feel** (NEW in v3): Coyote time, jump buffering, and variable jump height as `@export` parameters on ActivePlayer. Moving platforms, crumble blocks, and one-way platforms planned for Phase 4.
