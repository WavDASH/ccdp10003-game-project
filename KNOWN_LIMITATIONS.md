# Known Limitations

Current state of the prototype — what works, what has rough edges, and what isn't implemented.

---

## Working Well

- **Core time-branch loop**: forward play, reverse, echo spawning, multi-echo coexistence.
- **State machine movement**: acceleration-based horizontal, dash (8-dir), wall jump, wall slide, corner correction.
- **Edge-leniency systems**: coyote time, jump buffer, edge jump grace, wall jump grace frames.
- **Echo replay**: position + animation state faithfully replayed from recorded data, including dash trail VFX.
- **Reversal cycle lock**: READY → REVERSING → LOCKED prevents degenerate reversal spam.
- **Mechanism system**: switches, timed switches, doors, moving platforms, scheduled doors — all with editor wiring visualization.
- **Room transitions**: RoomManager loads scenes, places player at named entries, discovers exits.
- **Editor experience**: @tool scripts with `_get_configuration_warnings()` on most components, editor overlays for bounds/wiring/paths.
- **Hazard system**: kills active player on contact (forward and reverse), triggers level restart.
- **Crush detection**: player dies if physically trapped inside solid geometry by moving platforms or closing doors. Works in both forward and reverse mode.
- **Echo collapse**: geometry overlap and hazard overlap detection with visual collapse animation.
- **Per-room timeline sandbox**: each room has fully independent timeline state. Room transitions reset tick, branches, echoes, VFX, and reversal cycle.

## Known Edge Cases

- **BranchTrack.frames grows unbounded** for very long sealed branches. In practice this is bounded by session length and number of reversals. No eviction is implemented because echoes need full frame data for replay.
- **Collapsed-branch echoes** are freed by `queue_free()` during the collapse animation. If many echoes collapse simultaneously, there may be a brief frame stutter from bulk node removal.
- **Wall jump detection** relies on Godot's `is_on_wall()` (with a grace counter), which requires the player to press into a wall for `move_and_slide()` to register contact. This is intentional but can feel unresponsive on very thin walls.
- **Corner correction** uses `test_move()` which queries the physics server. On very complex collision geometry (many overlapping shapes), this could be slower than expected.
- **Echo VFX (dash trails)** on echoes use global aging — they play forward/backward with the game clock. If an echo's dash trail event is near the edge of the playback range, the ghost may pop in/out abruptly.
- **Moving platforms** do not record their position in frame data. Echo passengers riding a platform are replayed at their recorded global position, which may visually drift if the platform's trigger state differs on replay.
- **Crush detection** uses a 2px-per-side shrink on the player's collision shape. In extremely tight spaces (less than 4px clearance but technically passable), the player won't be crushed. This is intentional to avoid false positives from normal wall/floor contact.

## Not Implemented

- **Save/load system**: no persistence between sessions.
- **Settings/config**: no audio, video, or keybind settings menu.
- **Enemies or AI**: no hostile NPCs.
- **Dialogue/story**: no narrative system.
- **Art pipeline**: all visuals are placeholder rectangles generated from code.
- **Audio**: no sound effects or music.
- **Multiple rooms in a run**: room transitions work, but there is no overworld, map, or progression system.
- **Echo cooperation puzzles beyond switches**: echoes can stand on switches, but more complex cooperation (carrying objects, chain reactions) is not implemented.
- **Crumble block + echo interaction**: crumble blocks respond to the active player only; echoes cannot trigger crumbling.
- **One-way platforms**: `TerrainBlock` has a `one_way` export but it's not tested with echoes or reverse time.

## Performance Notes

- Echo validation (`_validate_echo_at_tick`) uses a cached `RectangleShape2D` to avoid per-frame allocation.
- `RoomTickContext.tick_history` is trimmed when echoes collapse, evicting entries older than any live branch.
- The F3 debug overlay redraws every frame when visible — disable it (F3) during performance-sensitive testing.
- `TimelineBar` redraws every frame via `queue_redraw()` in `_process`. This is lightweight but could be optimized to only redraw on state changes.
