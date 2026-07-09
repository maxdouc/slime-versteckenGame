# Build Plan — Slime-Verstecken

## Purpose

This file tracks how we build the game step by step.

SPEC.md explains what the game is.
README.md explains setup and architecture.
CLAUDE.md explains how Claude Code must work.
This file explains the development order, branch plan, status, and task ownership.

## Team members

- Travis = project partner, works on his own PC.
- Maxim = project partner and repository owner, works on his own PC.
- Claude Code may run on either Travis' or Maxim's machine.

Claude Code must not assume which person is using it.
It must read LOCAL_OPERATOR.md if available.

## Local operator rule

Each developer creates a local-only file named LOCAL_OPERATOR.md.

Example for Travis:

    # Local operator

    Current operator: Travis

    This file is local only and must not be committed.

Example for Maxim:

    # Local operator

    Current operator: Maxim

    This file is local only and must not be committed.

This file is ignored by git and must not be committed.

## Status legend

- Done = merged into main
- In progress = branch exists or task is currently being worked on
- Next = next planned branch
- Not started = planned but not started
- Blocked = cannot continue until another task is done
- TBD = owner or details not decided yet

## Current project status

### Done

- GitHub repository exists.
- Godot 4.7 project scaffold exists.
- Project boots in Godot.
- Net autoload exists.
- GameState autoload exists.
- README and SPEC exist.
- Travis has cloned the repo locally.
- Travis tested Godot boot successfully.
- Travis completed a workflow test branch with the workflow diagram.
- Workflow diagram is merged into main.

### In progress

- feature/project-build-plan
  - Owner: Travis
  - Goal: Add CLAUDE.md, planning/BUILD_PLAN.md, and ignore local operator identity.
  - Status: In progress

### Next

- feature/enet-lobby-ui
  - Owner: Travis
  - Goal: Add a minimal ENet test lobby UI.
  - Status: Next

## Development roadmap

### Phase 0 — Project setup and workflow

Goal: Make sure both developers can use the repo safely.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/travis-workflow-test | Travis | Done | Add workflow diagram and practice branch/commit/push/PR |
| feature/project-build-plan | Travis | In progress | Add Claude instructions and build plan |

Exit criteria:

- Repo is cloned locally.
- Godot project boots.
- Workflow is understood.
- CLAUDE.md exists.
- planning/BUILD_PLAN.md exists.
- LOCAL_OPERATOR.md is ignored by git.

---

### Phase 1 — Multiplayer foundation

Goal: Prove that multiplayer works before building gameplay.

Branches:

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 1A | feature/enet-lobby-ui | Travis | Next | Minimal host/join UI using current ENet scaffold |
| 1B | feature/gray-room-capsules | TBD | Not started | Gray room scene and basic player capsule |
| 1C | feature/basic-player-sync | TBD | Not started | Multiple clients see synced capsule movement |
| 1D | feature/web-mp-transport | TBD | Not started | Replace ENet test transport with WebRTC/signaling path when ready |

Important:

- ENet is currently only a test transport.
- Do not pretend the 6-character room code is a real web lobby until WebRTC/signaling exists.
- Do not add WebRTC before the ENet capsule sync is proven.
- Network features must be tested on two real machines.

---

### Phase 2 — Player feel

Goal: Make basic movement feel good before adding complex mechanics.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/player-movement-camera | TBD | Not started | CharacterBody3D movement and third-person camera |
| feature/slime-placeholder | TBD | Not started | Replace capsule with simple slime placeholder |

Exit criteria:

- Player can move comfortably.
- Camera follows cleanly.
- Other connected players can see movement.

---

### Phase 3 — Transform system

Goal: Let players transform from slime into white placeholder props.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/transform-white-props | TBD | Not started | Transform into white props |
| feature/prop-speed-tiers | TBD | Not started | Slime 100%, small 80%, medium 60%, large 40% |
| feature/network-transform-state | TBD | Not started | Other players see transform state |

Rules:

- Props always spawn neutral white.
- Skins must never create camouflage advantage.
- Do not add advanced props before placeholder props work.

---

### Phase 4 — Paint system

Goal: Build the core identity of the game: sampling and painting props.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/paint-prototype | TBD | Not started | Basic raycast paint onto one prop |
| feature/eyedropper-and-colorpicker | TBD | Not started | Sample color and choose color |
| feature/grundieren-button | TBD | Not started | One-click base coat |
| feature/paint-event-sync | TBD | Not started | Sync strokes as events, never whole textures |

Rules:

- Brush strokes sync as events.
- Never sync whole textures.
- Keep paint textures small for web performance.
- Test early in browser later.

---

### Phase 5 — Round loop

Goal: Turn the mechanics into an actual game round.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/round-phases | TBD | Not started | Lobby -> Prep -> Hunt -> End |
| feature/npc-slimes-feeding | TBD | Not started | NPC slimes and feeding interaction |
| feature/eat-progression-table | TBD | Not started | 0-3 eaten slimes unlock forms/clones |
| feature/rotation-timer | TBD | Not started | 60s room rotation rule and drip penalty |
| feature/win-lose-reset | TBD | Not started | Win, death, spectators, reset |

Rules:

- Fressen only in Prep phase.
- Rotation only in Hunt phase.
- Room change counts only after 5 seconds in the new room.
- No persistent power progression.

---

### Phase 6 — Seeker kit

Goal: Give seekers their core gameplay.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/paintball-gun | TBD | Not started | Paintball projectile and hit elimination |
| feature/seeker-splatter | TBD | Not started | Missed shots leave splatter on map |
| feature/seeker-cooldown | TBD | Not started | 4s cooldown default |
| feature/spectator-mode | TBD | Not started | Eliminated players spectate |

Rules:

- Exactly one weapon for V1.
- Weapon skins are post-launch/backlog.
- Missed shot splatter changes camouflage surfaces.

---

### Phase 7 — Map 1

Goal: Build the first playable map: Wohnhaus.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/map1-house-graybox | TBD | Not started | 9-room graybox house |
| feature/map1-npc-spawn-markers | TBD | Not started | Around 30 NPC spawn markers |
| feature/map1-prop-slots | TBD | Not started | Plausible large/medium/small prop positions |
| feature/map1-kenney-dressing | TBD | Not started | Replace graybox with Kenney assets after core works |

Rules:

- Each room should have at least 2 exits.
- Room count roughly 1.5x hider count.
- Do not build Map 2 before Map 1 survives playtesting.

---

### Phase 8 — Web build and playtest

Goal: Let people test through a browser link.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/web-export-smoke-test | TBD | Not started | Export simple web build |
| feature/itch-playtest-build | TBD | Not started | Upload playtest build to itch.io |
| planning/playtest-protocol | TBD | Not started | Metrics, survey, Discord rollout |

Rules:

- Web is V1.
- Steam is V2.
- Use browser tests early once web export exists.
- Measure performance before the end.

---

### Phase 9 — Clones and polish

Goal: Add advanced mechanics only after the core game works.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/clones | TBD | Not started | Static clone copy of current prop and paint |
| feature/clone-death-link | TBD | Not started | Destroyed clone kills owner |
| feature/clone-swap-teleport | TBD | Not started | Teleport to clone and consume it |

Rules:

- Clones are built last.
- Clones are the first cut candidate if time is tight.
- Core game must work without clones.

## Assignment rules

- Branches assigned to Travis should be worked on by Travis' local Claude Code.
- Branches assigned to Maxim should be worked on by Maxim's local Claude Code.
- Branches marked TBD require team decision before work starts.
- Branches marked Shared require explicit coordination.
- Do not work on another person's assigned branch unless explicitly told to take it over.

## Standard branch workflow

Before starting a branch:

    git checkout main
    git pull
    git checkout -b feature/name

During work:

1. Claude Code reads CLAUDE.md, README.md, SPEC.md, and this file.
2. Claude Code confirms the current operator and branch scope.
3. Claude Code modifies only files needed for that branch.
4. Developer tests in Godot.
5. Developer checks git status.
6. Developer commits.
7. Developer pushes.
8. Developer opens PR.
9. Other developer reviews.
10. Merge into main.
11. Both developers pull latest main.

## Current next branch details

### feature/enet-lobby-ui

Owner: Travis
Status: Next

Goal:

Create a minimal ENet test lobby UI for the current scaffold.

Scope:

- Host button calls Net.host_game().
- Show generated room code as local test placeholder.
- IP input field defaults to 127.0.0.1.
- Join button calls Net.join_game(ip).
- Show connection status messages.
- Keep changes small.

Out of scope:

- No WebRTC.
- No signaling server.
- No addons.
- No player capsules.
- No gameplay.
- No real room-code joining yet.
