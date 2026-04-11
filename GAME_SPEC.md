# GAME_SPEC.md

## Project summary

This project is a **2D mechanics-driven puzzle / action-platformer** built in **Godot 4.6** with **GDScript**.

The core mechanic is **time inversion with branch echoes**.
The player can reverse their temporal direction and leave behind visible, replaying echoes from previous timeline branches.
Those echoes can be used to solve puzzles.

This should feel inspired by the *experience* of overlapping temporal passes in a way reminiscent of **TENET**, but it should be implemented as a clear and playable game mechanic rather than as vague cinematic flavor.

## High-level fantasy

The player should feel:
- “I am not just undoing time.”
- “I am layering multiple versions of my own traversal.”
- “I can cooperate with my previous selves.”
- “If I damage the conditions that keep an echo valid, I may lose that echo and fail the puzzle later.”

## Core input / loop

The prototype should support at least:
- move left/right
- jump
- press **R** to switch temporal direction
- press **R** again to switch again
- create multiple timeline branches across a run
- display multiple echoes from older branches when appropriate
- solve a puzzle using an echo

## Intended on-screen effect

### Forward time
- screen looks normal
- active player is fully opaque and clearly readable

### Reverse time
- active player is still the controlled character
- screen should have a clear reverse-time visual treatment, such as a blue tint / cool filter
- previously recorded branches should appear as semi-transparent echoes

### After switching direction again
- the active player enters a new branch
- older branches remain as visible echoes where relevant
- the player should be able to see multiple temporal passes coexisting

## Core design rules

### 1. This is branch-based time, not simple rewind
Do not implement the concept as a trivial restore-to-old-save-state feature.
Instead, think in terms of:
- branch creation
- timeline segments
- replaying previous branches as echoes
- one currently active branch being written now

### 2. Only one active player is controlled
- one player instance is active and controllable
- other versions are echoes / replays from previous branches

### 3. Echoes are useful
Echoes should not be purely decorative.
They should help solve puzzles.

Example target puzzle:
- a door opens only when two pressure plates are held at once
- the active player stands on one plate
- a replaying echo stands on the other plate

### 4. Echoes and active player should not block each other
- active player and echoes should not physically collide with one another
- they should visually overlap / pass through each other
- echoes should look transparent or tinted

### 5. Echo path failure should collapse the echo
If an echo can no longer validly replay its path in the current world state, the echo should collapse / disappear.

Examples of invalid replay conditions:
- a static obstacle now blocks the route
- the expected ground is missing
- the echo would be forced into an impossible physical continuation
- the echo touches a lethal hazard and is destroyed

Important:
- echo collapse should **not** instantly fail the level
- it only removes that echo's future usefulness
- therefore the player must protect the conditions that keep useful echoes alive

### 6. Only active player death fails the level
- if the active player dies, the level restarts from the beginning
- this should feel quick and clean, similar in spirit to a fast puzzle-platformer reset

### 7. Multiple reversals should be supported
The architecture should support:
- multiple reversals in one run
- multiple echoes
- configurable limits such as:
  - max reversals per level
  - max rewind duration per reversal
  - max simultaneous persistent echoes

### 8. Visual readability matters a lot
The player must easily distinguish:
- active player
- forward vs reverse mode
- older echoes
- different echo generations if possible

Possible visual language:
- normal colors during forward time
- blue / cool tint during reverse time
- each echo with lower opacity
- optional different tint per echo generation
- transition effect when pressing R
- optional collapse flicker / glitch before echo disappears

## Recommended MVP scope

### Must-have
- one small test level
- simple left/right movement and jump
- press R to change time direction
- timeline branching / echo system
- at least one puzzle needing an echo
- at least one hazard
- restart on active player death
- placeholder visuals only

### Nice-to-have if simple
- small screen flash or tween on time-direction change
- simple collapse flicker before echo disappears
- small on-screen display for reversals remaining

### Out of scope for the first version
- story / cutscenes
- final art
- advanced enemy AI
- combat systems
- inventory / upgrades
- large content pipeline

## Suggested implementation direction

These are suggestions, not hard requirements. Claude should think independently and improve them if needed.

### Time model
A good approach may be:
- maintain a current timeline tick or time pointer
- record active player states by fixed ticks
- treat each temporal pass as a branch / segment
- old branches can be sampled at the current tick to display echoes
- the current active branch is the one receiving input and writing new states

### Echo model
A good approach may be:
- echoes replay recorded state rather than running full AI
- echoes can interact with selected puzzle elements
- echoes do not collide with the active player
- if an echo cannot validly continue replaying in the current world state, it collapses

### Collision model
A good approach may be:
- separate collision layers / masks for:
  - world static geometry
  - active player
  - echoes
  - puzzle interaction elements
  - hazards

### Visual model
A good approach may be:
- use `CanvasModulate`, shaders, or a simple tint controller for forward / reverse mode
- lower opacity for echoes
- generation-based tint variation for multiple echoes
- a short transition when time direction changes

## Acceptance criteria for the first build

A successful first build should let me:
- open the project in Godot 4.6
- run the main scene
- move and jump
- press R to change time direction
- see at least one earlier branch as an echo
- use an echo to help open a door via a puzzle element
- observe an echo collapse when its path becomes invalid
- die from a hazard and restart the level
- clearly tell whether I am in forward or reverse mode

## Desired developer mindset

When planning and implementing, optimize for:
1. mechanic clarity
2. stable architecture
3. easy testing in Godot 4.6
4. future expandability
5. minimal initial scope
