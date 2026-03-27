# Project Memory Template

Use this when opening a new Codex thread and you want more steering than `AGENTS.md` alone provides.

## New Thread Prompt Template

```text
Working directory: C:\git\dungeonGame\dungeonGameConvertToMultplayer

Read first:
- AGENTS.md
- <add any task-specific docs or files here>

Task:
- <what you want changed or investigated>

Goal / outcome:
- <player-facing or developer-facing result>

Relevant subsystem:
- <networking | dungeon generation | encounters | UI | visuals/equipment | tools/pipeline>

Likely files:
- <list the most likely files if you know them>

Constraints:
- <things that must not break>
- <existing WIP to avoid touching>
- <performance / authority / style constraints>

Verification:
- <command to run, scenario to test, or "explain if you could not verify">

Definition of done:
- <clear finish line>

Useful current memory:
- Main scene is `res://scenes/ui/lobby_menu.tscn`
- Runtime world is `res://dungeon/game/small_dungeon.tscn`
- Multiplayer is authoritative server model
- Milestones 1-3 are done, milestone 4 combat is in progress
```

## Thread Handoff Template

Use this near the end of a thread, then copy the important parts into `AGENTS.md` if the knowledge should persist.

```text
Date:
Task:
Files touched:
Commands run:
Verification:
Behavior changes:
Architectural decisions:
Known risks:
Follow-up ideas:
Next best prompt:
```

## Focused Variants

### Bug Fix

```text
Investigate and fix:
- <bug>

Expected behavior:
- <what should happen>

Observed behavior:
- <what is happening now>

Scope guardrails:
- Do not refactor unrelated systems.
- Preserve existing local WIP.

Verify with:
- <exact repro or command>
```

### Feature Work

```text
Implement:
- <feature>

Use existing patterns from:
- <file or subsystem>

Avoid changing:
- <areas to leave alone>

Verify with:
- <playtest / command / logs>
```

### Code Review

```text
Review these files/changes:
- <paths or diff scope>

Focus on:
- bugs
- regressions
- missing tests or verification

Ignore if desired:
- style-only issues
```

## Maintenance Notes

- Keep `AGENTS.md` short enough to stay useful; move deep thread-only notes into dated summaries if needed.
- Prefer stable facts in `AGENTS.md` and volatile task state in handoff notes.
- If a thread changes core architecture, update the relevant snapshot in `AGENTS.md` before ending the task.
