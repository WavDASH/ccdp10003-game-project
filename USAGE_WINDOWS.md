# USAGE_WINDOWS.md

This folder contains a simple two-step workflow for using Claude Code on this Godot prototype project.

## Files in this pack

- `CLAUDE.md` — persistent project rules and expectations
- `GAME_SPEC.md` — the game design target and MVP spec
- `CLAUDE_PROMPT_1_PLAN.txt` — use this first to make Claude create `IMPLEMENTATION_PLAN.md`
- `CLAUDE_PROMPT_2_BUILD.txt` — use this after the plan is reviewed and adjusted

## Recommended workflow

### Step 0 — put these files in the project root
Place these files in the root of your Godot project repository.
That way Claude can read them immediately.

### Step 1 — start Claude Code in the repo root
Open your terminal in the project root, then launch Claude Code from there.
If you normally work through WSL, you can run Claude Code from the WSL-side project directory.
If you work directly in Windows, just make sure Claude is operating in the correct repository root.

### Step 2 — planning pass
Open `CLAUDE_PROMPT_1_PLAN.txt`, copy its full contents, and paste it into Claude Code.

Expected result:
- Claude reads `CLAUDE.md` and `GAME_SPEC.md`
- Claude inspects the repo
- Claude creates `IMPLEMENTATION_PLAN.md`
- Claude stops and waits for review

### Step 3 — review and edit the plan
Read `IMPLEMENTATION_PLAN.md` carefully.
Discuss or revise the plan until you are happy with it.
You can edit the plan manually if needed.

### Step 4 — build pass
After the plan is approved, open `CLAUDE_PROMPT_2_BUILD.txt`, copy its full contents, and paste it into Claude Code.

Expected result:
- Claude reads the spec and approved plan
- Claude builds the Godot 4.6 MVP
- Claude leaves a project structure you can open in Godot
- Claude summarizes what works and what remains

### Step 5 — open in Godot 4.6
After Claude finishes the build, open the project in Godot 4.6 and test the main scene.

## Suggested follow-up workflow

If something is broken or incomplete, do focused follow-up requests such as:
- fix only scene reference issues
- fix only echo collapse behavior
- improve only the forward/reverse visual readability
- refactor only the timeline manager
- add only a small debug overlay for branch / reversal state

Keeping follow-up requests narrow usually produces cleaner results.

## Practical tips

- Do not ask for final art too early.
- Keep the first level tiny.
- Ask for a robust prototype before asking for polish.
- Prefer placeholder visuals and strong mechanics.
- If Claude proposes a simplification that preserves the intended feel, it is often worth considering.

## What success looks like

You should end up with:
- a Godot 4.6 project
- GDScript-based gameplay scripts
- a minimal test level
- branch / echo mechanic working in a playable form
- a generated `IMPLEMENTATION_PLAN.md`
- possibly a `BUILD_NOTES.md` after implementation
