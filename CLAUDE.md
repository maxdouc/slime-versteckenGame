# CLAUDE.md — Project instructions for Claude Code

@README.md
@planning/BUILD_PLAN.md

## Project identity

This repository contains the game project Slime-Verstecken by Travis and Maxim.

This is a Godot 4.7 multiplayer game project.
The project is web-first: HTML5/Web is V1, Steam is V2.
Do not add GodotSteam to V1.

## Shared team

This repository is shared by two developers:

- Travis = project partner, works on his own local machine.
- Maxim = project partner and repository owner, works on his own local machine.

Do not assume which developer is currently using Claude Code.

At the start of a task:
1. Read LOCAL_OPERATOR.md if it exists.
2. If LOCAL_OPERATOR.md does not exist, ask once whether the current operator is Travis or Maxim.
3. Only work on tasks assigned to the current operator unless the user explicitly says they are taking over another task.

LOCAL_OPERATOR.md is local-only and must never be committed.

## Source of truth

Use these files as project truth:

1. SPEC.md = gameplay and design truth.
2. README.md = setup, architecture summary, and process rules.
3. planning/BUILD_PLAN.md = development phases, branch order, task status, and team assignments.
4. Current code = actual implemented state.

If code and SPEC.md disagree, SPEC.md wins unless the user explicitly says the team changed the spec.

Before changing gameplay, networking, map logic, progression, paint, seeker logic, round flow, or monetization, read SPEC.md first.

## Core architecture rules

- Web-first. Steam is V2.
- No GodotSteam in V1.
- Gameplay must use Godot high-level multiplayer APIs.
- Gameplay code must not directly depend on the network transport.
- Transport-specific code belongs behind the Net autoload.
- Brush strokes and paint actions must sync as events, never as whole textures.
- Multiplayer features must be tested on two real machines or browsers, not only in the editor.

## Git and workflow rules

- Never commit directly to main.
- Work only on feature branches.
- Do not create, commit, push, or merge unless explicitly asked.
- Do not touch unrelated files.
- Keep branches small and reviewable.

Before changing files, summarize:
- the current branch
- the assigned operator
- the exact scope
- files likely to change

After changing files, summarize:
- files changed
- what changed
- how to test in Godot
- any risks or follow-up work

## Task ownership rules

Before starting work, check planning/BUILD_PLAN.md.

- If a branch is assigned to Travis, only Travis' local Claude Code should work on it.
- If a branch is assigned to Maxim, only Maxim's local Claude Code should work on it.
- If a branch is marked Shared, ask for confirmation before editing.
- If the current operator wants to take over a branch assigned to the other person, require explicit confirmation.

## Scope control

Do not build the full game in one task.

Build the project in layers:

1. Project setup and workflow
2. ENet test lobby
3. Gray room and synced capsules
4. Player movement
5. Slime form and transform into white props
6. Paint system
7. Round loop
8. Seeker kit
9. Map 1
10. WebRTC/Web export
11. Playtest
12. Clones and polish

If asked to implement a branch, implement only that branch.

## Local operator file

If present, read:

LOCAL_OPERATOR.md

Expected examples:

Current operator: Travis

or:

Current operator: Maxim

Never add LOCAL_OPERATOR.md to git.
