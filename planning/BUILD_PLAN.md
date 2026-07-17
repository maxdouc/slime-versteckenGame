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
- Complete (chain) = implemented, tested and manually validated on the
  stacked Phase 5–9 branch chain (head: fix/phase-5-9-manual-validation);
  merge into main via reviewed PRs is still pending
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
- feature/project-build-plan is merged into main.
- feature/enet-lobby-ui (1A) is merged into main.
- feature/gray-room-capsules (1B) is merged into main.
- feature/basic-player-sync (1C) is merged into main.
- feature/web-mp-transport (1D) is merged into main: WebRTC + signaling server is the primary transport with real room codes; manual two-machine test over Tailscale passed (2026-07-12).
- Phase 1 (Multiplayer foundation) is complete and fully merged into main.
- feature/player-movement-camera is merged into main.
- feature/slime-placeholder is merged into main.
- Phase 2 (Player feel) is complete; exit criteria tested successfully.
- feature/transform-white-props is merged into main.
- feature/prop-speed-tiers is merged into main.
- feature/network-transform-state is merged into main.
- Phase 3 (Transform system) is complete. Manual tests passed: local transformation, speed tiers, two local instances, late join, and two real machines over ENet and Tailscale.
- Note: native WebRTC on macOS was not tested successfully because the repository currently lacks the macOS webrtc_native framework. This is tracked as a separate platform setup issue, not a Phase 3 gameplay failure.
- feature/paint-prototype is merged into main.
- feature/eyedropper-and-colorpicker is merged into main.
- feature/grundieren-button is merged into main.
- feature/paint-event-sync is merged into main.
- Phase 4 (Paint system) is complete. Manual tests passed: local painting, camera orbit while painting, eyedropper and HSV color picker, Grundieren and Alles-Löschen, paint persistence while moving, paint reset when returning to slime, two local instances, paint event synchronization, independent player paint state, late join, and two real machines over ENet and Tailscale.

- Phases 5–9 (Round loop, Seeker kit, Map 1, Web build, Clones) are
  **Complete (chain)** — implemented as one stacked branch chain (owner:
  Travis), ending in fix/phase-5-9-manual-validation. Evidence:
  - automated suite: 28 test files / 681 checks, all green;
  - Windows↔MacBook two-machine WebRTC validation over Tailscale
    (browser client on the Mac) — full Phase 5–9 gameplay pass;
  - hidden itch build `20260717-ac79b75` deployed and smoke-tested
    (channel web-playtest, page draft/hidden);
  - final manual visual review by Travis + Maxim: rotation drip,
    splatter look, Map 1 walkthrough — accepted for V1.
  Details per branch: planning/PHASE_5_9_STATUS.md.
- **V1 gameplay / foundation is COMPLETE.** Public internet multiplayer
  deployment and the community playtest rollout are explicitly NOT part
  of this and remain pending (see Next).

### In progress

- None.

### Next

- Merge the Phase 5–9 branch chain into main via reviewed PRs
  (Travis + Maxim — no automated merges).
- Post-foundation deployment task, BEFORE any external tester wave:
  public WSS/TLS signaling hosting + TURN-relay decision.
- Community playtest rollout per planning/PLAYTEST_PROTOCOL.md
  (Phase 8 waves) once the deployment task is done.
- Cosmetic backlog: ✓/✗ HUD glyphs render as boxes in the web build
  (missing font glyph).

## Development roadmap

### Phase 0 — Project setup and workflow

Goal: Make sure both developers can use the repo safely.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/travis-workflow-test | Travis | Done | Add workflow diagram and practice branch/commit/push/PR |
| feature/project-build-plan | Travis | Done | Add Claude instructions and build plan |

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

Status: Completed. All Phase 1 branches are done; the WebRTC transport passed a manual two-machine test over Tailscale (2026-07-12).

Branches:

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 1A | feature/enet-lobby-ui | Travis | Done | Minimal host/join UI using current ENet scaffold |
| 1B | feature/gray-room-capsules | Travis | Done | Gray room scene and basic player capsule |
| 1C | feature/basic-player-sync | Travis | Done | Multiple clients see synced capsule movement |
| 1D | feature/web-mp-transport | Travis | Done | Replace ENet test transport with WebRTC/signaling path when ready |

Important:

- ENet is currently only a test transport.
- Do not pretend the 6-character room code is a real web lobby until WebRTC/signaling exists.
- Do not add WebRTC before the ENet capsule sync is proven.
- Network features must be tested on two real machines.

---

### Phase 2 — Player feel

Goal: Make basic movement feel good before adding complex mechanics.

Status: Completed. Both Phase 2 branches are merged into main; exit criteria tested successfully.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/player-movement-camera | Maxim | Done | CharacterBody3D movement and third-person camera |
| feature/slime-placeholder | Maxim | Done | Replace capsule with simple slime placeholder |

Exit criteria (tested successfully):

- Player can move comfortably.
- Camera follows cleanly.
- Other connected players can see movement.

---

### Phase 3 — Transform system

Goal: Let players transform from slime into white placeholder props.

Status: Completed. All Phase 3 branches are done and merged into main.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/transform-white-props | Travis | Done | Transform into white props |
| feature/prop-speed-tiers | Travis | Done | Slime 100%, small 80%, medium 60%, large 40% |
| feature/network-transform-state | Travis | Done | Other players see transform state |

Manual tests passed:

- Local transformation.
- Speed tiers.
- Two local instances.
- Late join.
- Two real machines over ENet and Tailscale.

Known platform issue (not a Phase 3 gameplay failure):

- Native WebRTC on macOS was not tested successfully because the repository
  currently lacks the macOS webrtc_native framework. This is a platform setup
  gap to resolve separately, tracked outside Phase 3 gameplay scope.

Rules:

- Props always spawn neutral white.
- Skins must never create camouflage advantage.
- Do not add advanced props before placeholder props work.

---

### Phase 4 — Paint system

Goal: Build the core identity of the game: sampling and painting props.

Status: Completed. All Phase 4 branches are done and merged into main.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/paint-prototype | Travis | Done | Basic raycast paint onto one prop |
| feature/eyedropper-and-colorpicker | Travis | Done | Sample color and choose color |
| feature/grundieren-button | Travis | Done | One-click base coat |
| feature/paint-event-sync | Travis | Done | Sync strokes as events, never whole textures |

Manual tests passed:

- Local painting.
- Camera orbit while painting.
- Eyedropper and HSV color picker.
- Grundieren and Alles-Löschen.
- Paint persistence while moving.
- Paint reset when returning to slime.
- Two local instances.
- Paint event synchronization.
- Independent player paint state.
- Late join.
- Two real machines over ENet and Tailscale.

Known platform issue (not a Phase 4 gameplay failure):

- Native WebRTC on macOS remains untested because the repository still lacks
  the macOS webrtc_native framework. This is the same separate platform setup
  issue already tracked since Phase 3.

Rules:

- Brush strokes sync as events.
- Never sync whole textures.
- Keep paint textures small for web performance.
- Test early in browser later.

---

### Phase 5 — Round loop

Goal: Turn the mechanics into an actual game round.

Status: Complete (chain) — implemented, tested (28-file suite) and
manually validated (two-machine Tailscale pass; rotation-drip feel
accepted in the final review). See planning/PHASE_5_9_STATUS.md.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/round-phases | Travis | Complete (chain) | Lobby -> Prep -> Hunt -> End |
| feature/npc-slimes-feeding | Travis | Complete (chain) | NPC slimes and feeding interaction |
| feature/eat-progression-table | Travis | Complete (chain) | 0-3 eaten slimes unlock forms/clones |
| feature/rotation-timer | Travis | Complete (chain) | 60s room rotation rule and drip penalty |
| feature/win-lose-reset | Travis | Complete (chain) | Win, death, spectators, reset |

Rules:

- Fressen only in Prep phase.
- Rotation only in Hunt phase.
- Room change counts only after 5 seconds in the new room.
- No persistent power progression.

---

### Phase 6 — Seeker kit

Goal: Give seekers their core gameplay.

Status: Complete (chain) — implemented, tested and manually validated
(two-machine seeker duel; splatter look accepted in the final review).

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/paintball-gun | Travis | Complete (chain) | Paintball projectile and hit elimination |
| feature/seeker-splatter | Travis | Complete (chain) | Missed shots leave splatter on map |
| feature/seeker-cooldown | Travis | Complete (chain) | 4s cooldown default |
| feature/spectator-mode | Travis | Complete (chain) | Eliminated players spectate |

Rules:

- Exactly one weapon for V1.
- Weapon skins are post-launch/backlog.
- Missed shot splatter changes camouflage surfaces.

---

### Phase 7 — Map 1

Goal: Build the first playable map: Wohnhaus.

Status: Complete (chain) — 9 rooms, 30 NPC markers, decoy slots, Kenney
Furniture-Kit dressing; walkthrough (scale, doorways, layout, furniture,
plausibility) accepted in the final review by Travis + Maxim.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/map1-house-graybox | Travis | Complete (chain) | 9-room graybox house |
| feature/map1-npc-spawn-markers | Travis | Complete (chain) | Around 30 NPC spawn markers |
| feature/map1-prop-slots | Travis | Complete (chain) | Plausible large/medium/small prop positions |
| feature/map1-kenney-dressing | Travis | Complete (chain) | Replace graybox with Kenney assets after core works |

Rules:

- Each room should have at least 2 exits.
- Room count roughly 1.5x hider count.
- Do not build Map 2 before Map 1 survives playtesting.

---

### Phase 8 — Web build and playtest

Goal: Let people test through a browser link.

Status: Complete (chain) for the BUILD PIPELINE — web export works, the
hidden itch channel serves build `20260717-ac79b75` (smoke-tested in the
itch iframe), the playtest protocol is written, and a real browser
client on a second machine passed the Tailscale validation. The PUBLIC
rollout is explicitly still pending: public WSS/TLS signaling + TURN
decision first, then the tester waves.

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/web-export-smoke-test | Travis | Complete (chain) | Export simple web build |
| feature/itch-playtest-build | Travis | Complete (chain) | Upload playtest build to itch.io (hidden channel) |
| planning/playtest-protocol | Travis | Complete (chain) | Metrics, survey, Discord rollout |

Rules:

- Web is V1.
- Steam is V2.
- Use browser tests early once web export exists.
- Measure performance before the end.

---

### Phase 9 — Clones and polish

Goal: Add advanced mechanics only after the core game works.

Status: Complete (chain) — implemented, tested and validated on two real
machines (paint fidelity through the swap, death link, swap escapes).

Branches:

| Branch | Owner | Status | Scope |
|---|---|---|---|
| feature/clones | Travis | Complete (chain) | Static clone copy of current prop and paint |
| feature/clone-death-link | Travis | Complete (chain) | Destroyed clone kills owner |
| feature/clone-swap-teleport | Travis | Complete (chain) | Teleport to clone and consume it |

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

## Parallel work rules

- Dependent branches must be completed sequentially.
- Two branches may run in parallel only when they do not depend on each other and do not modify the same central files.
- Before parallel work begins, both Claude Code sessions must list the files they expect to modify.
- If both branches may modify the same files, the branches must be completed sequentially.
- Central files such as project.godot, scenes/main.tscn, scripts/main.gd, scripts/game_state.gd and net/net.gd should not be edited by two branches at the same time.
- For the first phases, work sequentially and use the other developer for review and testing.

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

## Current branch details

### feature/transform-white-props

Owner: Travis
Status: Done — merged into main. Manual tests passed: local transformation,
two local instances, late join, and two real machines over ENet and Tailscale.

Goal:

Let a player transform from slime into a white placeholder prop and back (Phase 3, SPEC.md 9.1).

Scope:

- Small set of simple white placeholder props (e.g., one large, one medium, one small shape).
- Player input to transform into a prop form and to transform back to slime at any time.
- Props always spawn neutral white — never colored, never textured.
- Works locally in the existing gray room with the current slime placeholder.

Out of scope (separate branches):

- No speed tiers per form (feature/prop-speed-tiers).
- No network sync of transform state (feature/network-transform-state).
- No paint system (Phase 4).

### feature/paint-prototype

Owner: Travis
Status: Done — merged into main. Phase 4 continued with
feature/eyedropper-and-colorpicker, feature/grundieren-button, and
feature/paint-event-sync, all merged into main.

Goal:

Basic raycast paint onto one prop — the first step of the Phase 4 paint system (SPEC.md 9.3).

Scope:

- Raycast-based paint application onto a single placeholder prop.
- Minimal proof of concept; no eyedropper, color picker, Grundieren button, or event-sync yet.

Out of scope (separate branches):

- No eyedropper/color picker (feature/eyedropper-and-colorpicker).
- No Grundieren one-click base coat (feature/grundieren-button).
- No network sync of paint strokes (feature/paint-event-sync).

### feature/web-mp-transport (1D)

Owner: Travis
Status: Done — manual two-machine WebRTC test over Tailscale passed (2026-07-12).

Goal:

Make WebRTC with real room-code signaling the primary transport, behind the
existing Net seam.

Scope:

- Headless WebSocket signaling server in /server (GDScript, runs on the Godot binary).
- WebRTCMultiplayerPeer mesh built from server-relayed offers/answers/ICE candidates.
- Real room codes issued by the signaling server; join by code in the lobby UI.
- ENet kept as an explicit developer fallback (lobby dropdown). No automatic
  fallback: WebRTC/signaling failures show a clear error.
- Official webrtc-native GDExtension pinned and committed (Windows x86_64 +
  licenses, see addons/webrtc_native/VERSION.md).
- Automated smoke test: server/smoke_test.gd.
- Remote two-PC desktop test runs over Tailscale (no router port forwarding).

Out of scope (deferred to the web-export/deployment phase):

- No public hosting of the signaling server, no WSS/TLS, no TURN relay.
- No web export / browser testing yet.
- No gameplay changes — scripts/main.gd and scripts/player_capsule.gd stay untouched.
