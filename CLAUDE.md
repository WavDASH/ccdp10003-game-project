# CLAUDE.md

This repository is for a **Godot 4.6 + GDScript** prototype of a 2D time-branch / echo puzzle-platformer.

Before doing anything important, always read:
1. `GAME_SPEC.md`
2. `IMPLEMENTATION_PLAN.md` if it exists
3. the current user prompt

## Core development rules

- Target engine: **Godot 4.6**
- Target language: **GDScript**
- Prefer a **code-driven architecture** with relatively thin scenes and most logic in scripts.
- Prioritize a **robust playable MVP** over polish.
- Use **placeholder visuals only** unless explicitly asked otherwise.
- Do **not** add external plugins unless absolutely necessary.
- Prefer deterministic or tick-friendly logic using `_physics_process()` where practical.
- Keep code readable, modular, and easy to continue later.
- Do not over-engineer.

## The intended game feel

This is **not** a simple rewind-to-checkpoint game.
The core fantasy is:
- the player inverts time direction,
- previous temporal passes remain visible as transparent **echoes**,
- the player can cooperate with those echoes to solve puzzles,
- echoes can collapse if their recorded path is no longer physically valid,
- only the active player's death should fail the level.

## Important design constraints

- Only **one active player** is directly controlled at a time.
- Previous timeline passes become **echoes**.
- Echoes should be useful for puzzles.
- Echoes and the active player should **not block each other physically**.
- Echoes may interact with selected puzzle systems.
- If an echo's path becomes invalid, the echo should **collapse/disappear**, not fail the level.
- If the active player dies, the level should restart quickly from the beginning.
- Multiple reversals / multiple echoes should be supported by the architecture.
- Visual clarity is critical: forward, reverse, active player, and different echoes must be easy to tell apart.

## Scope discipline

For the first playable prototype, stay focused on:
- one small test level
- one controllable player
- reversal / branching / echo playback
- one puzzle that requires cooperation with at least one echo
- one or more hazards that kill the active player
- restart on active player death
- placeholder visuals

Avoid adding unrelated systems such as:
- story / dialogue systems
- inventory systems
- save/load systems
- full menus/settings
- final art pipelines
- enemies with complex AI

## Workflow rules

### If the task is planning
- Do **not** jump into coding.
- Inspect the project structure first.
- Think carefully about architecture, risks, edge cases, and implementation order.
- Write a clear `IMPLEMENTATION_PLAN.md`.
- Stop and wait for approval or revisions before building.

### If the task is building
- Read `GAME_SPEC.md`, `CLAUDE.md`, and `IMPLEMENTATION_PLAN.md` first.
- Implement the approved plan faithfully, while improving details if needed.
- If some planned detail is flawed, fix it carefully and document the change.
- Keep the result directly usable in Godot 4.6.
- After building, summarize what works, what is incomplete, and the controls.

## Code style / project structure preferences

Suggested structure:
- `scenes/`
- `scripts/`
- `assets/placeholder/`
- optional `fx/` or `ui/` subfolders if helpful

Suggested systems to consider:
- `TimelineManager`
- `TimelineBranch` or `BranchTrack`
- `FrameState`
- `ActivePlayer`
- `EchoPlayer`
- `PressurePlate`
- `Door`
- `Hazard`
- visual tint / transition controller

## Verification expectations

When building:
- verify node paths and scene references
- check for obvious GDScript parse issues
- make sure the project opens coherently in Godot 4.6
- keep placeholder assets and setup simple
- document controls clearly

## Final priority order

1. Core mechanic clarity
2. Playability
3. Code structure
4. Visual readability
5. Extra polish
