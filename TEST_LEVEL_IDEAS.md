# TEST_LEVEL_IDEAS.md

Future test level concepts that explore different facets of the time-branch / echo mechanic. These are **not implemented** in the MVP but inform the architecture.

---

## Level 1 (MVP): "First Echo"

**Already built.** Two switches at different heights, one latching door, one hazard pit. Teaches: "I can cooperate with a past version of myself." Requires one reversal and one echo.

---

## Level 2: "The Weight"

**Mechanic explored:** Multiple echoes needed simultaneously.

### Layout
- Three pressure switches spread across the level.
- One large door that requires ALL THREE switches active at the same time.
- Switches are positioned so one actor cannot reach two of them in quick succession.

### Intended solution
1. First pass: stand on Switch A for a long window.
2. Press R. Second pass: stand on Switch B, timed to overlap with echo on A.
3. Press R. Third pass: stand on Switch C, timed to overlap with echo-A on A and echo-B on B.
4. All three pressed simultaneously → door opens.

### What it tests
- Visual clarity with 3+ actors on screen.
- Player ability to plan timing across multiple reversals.
- The system's support for many simultaneous echoes.
- Debug HUD usefulness with many branches.

---

## Level 3: "Echo Shield"

**Mechanic explored:** Intentional echo collapse as a puzzle tool.

### Layout
- A corridor with a timed hazard (e.g., a laser beam that cycles on and off).
- A switch at the far end of the corridor that disables a second hazard blocking the exit.
- The laser is lethal to both the player and echoes.

### Intended solution
1. First pass: carefully time a run through the corridor, reach the switch, stand on it.
2. Press R. During reverse, the echo replays the first pass — it walks through the corridor and stands on the switch.
3. While the echo holds the switch (disabling the exit hazard), the player takes a different route to the exit.
4. Eventually the echo reaches the laser timing window and **collapses** — but by then the player has already passed the exit hazard.

### What it tests
- Echo collapse is a **feature**, not just a failure state.
- Players can intentionally use echoes as temporary tools.
- Timed hazards as a new MechanismTrigger variant (cycles on/off).
- Understanding of echo lifecycle: "this echo will collapse later, but I need it now."

### Architecture requirement
- Timed hazard: a MechanismTrigger that cycles `activated` on a timer.
- Laser emitter: a MechanismReceiver that creates/removes a hazard rect when triggered.

---

## Level 4: "Reverse Courier"

**Mechanic explored:** Long-range reverse-time echo coordination.

### Layout
- A long level. Switch near the exit (right side). Door near the start (left side).
- The door only opens while the switch is held.
- The player must go through the door to reach the actual goal, which is behind the door on the left.

### Intended solution
1. First pass (forward): traverse the entire level left-to-right, reach the switch, stand on it.
2. Press R (reverse). The echo replays the first pass — eventually it will reach the switch and stand on it.
3. While going backward through time, the player navigates back toward the left.
4. At the ticks when the echo is on the switch, the door opens. The player walks through.
5. Press R again (forward). Walk to the goal behind the door.

### What it tests
- Coordination over long time distances (many ticks between action and effect).
- Player understanding of forward/reverse echo replay direction.
- The HUD's tick counter as a planning tool.
- Door non-latching variant (requires continuous pressure — tests architecture support).

### Architecture requirement
- Non-latching door: `DoorReceiver` with `latching = false`.
- Larger level → camera follows player with limits.

---

## Level 5: "Paradox Garden"

**Mechanic explored:** Preserving echo validity as the core challenge.

### Layout
- Multiple interconnected paths, each with a door.
- Each door is controlled by a switch.
- **But** pressing Switch A closes Door B (which a previous echo needs to pass through).
- The player must find a route sequence across multiple reversals that doesn't invalidate earlier echoes.

### Intended solution
- Multiple valid solutions exist, but the player must think about which switches to press in which order.
- The wrong sequence collapses a critical echo, forcing a restart.
- The right sequence keeps all echoes alive long enough to complete the puzzle.

### What it tests
- Echo collapse as a **strategic constraint**, not just a consequence.
- Multi-branch path planning.
- Understanding of how world state changes propagate to echo validity.
- The collapse visual feedback as a learning signal.

### Architecture requirement
- "Inverse" mechanism: a receiver that CLOSES when a trigger is active (or a trigger that activates a wall instead of removing one).
- Could be implemented as a `MechanismReceiver` subclass with inverted logic (`_on_state_change` swaps open/closed meaning).

---

## Common Architecture Takeaways

All five levels use the same core systems:
- `TimelineManager` with global tick, branching, echo replay
- `MechanismTrigger` / `MechanismReceiver` framework
- `validate_echo_at_tick()` collapse pipeline
- Manual overlap queries for detection

The main additions needed for levels 2–5:
- **Timed trigger** (cycles on/off) — new `MechanismTrigger` subclass
- **Inverse receiver** (closes when trigger active) — new `MechanismReceiver` subclass or flag
- **Laser emitter** (dynamic hazard) — `MechanismReceiver` that adds/removes hazard rects
- **Non-latching door** — already supported (`latching = false`)
- **Larger levels** — camera limit adjustment, level builder data
