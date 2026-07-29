# Post-Playtest Build Plan — Variante 1.2

## Purpose

This plan defines the next development block after the first complete two-machine playtest of Slime-Verstecken.

It does **not** replace the long-term platform naming:

- Web/HTML5 remains the current product line.
- Steam remains the later platform V2.
- “Variante 1.2” is the post-playtest expansion and stabilization block for the current web-first game.

The historical Phase 0–9 plan remains preserved in `planning/BUILD_PLAN.md`. This document is the active plan for Phase 10 onward.

## Team decisions locked for Variante 1.2

1. Development block name: **Post-Playtest Build Plan — Variante 1.2**.
2. The current house map is replaced as the active primary map by a new **two-floor Casino**.
3. The full active map and its decoration are replaced with one project-controlled visual/asset ecosystem.
4. Transformable map objects use one shared prop pipeline for map placement, scanning, transformation, painting, cloning, collision, and networking.
5. Hiders scan approved Casino objects and transform into the scanned object when their current progression tier allows it.
6. NPC slimes actively flee from hiders during Prep and must be caught before they can be eaten.
7. The seeker uses first-person view and sees a Paintball Gun viewmodel.
8. Normal gameplay and Paint Mode both support controlled zoom in/out.
9. Hiders gain jumping and surface traversal. Slimes and transformed props can climb walls.
10. The slime receives a dedicated flattened/hanging wall-climb presentation. Props preserve their current painted form and align to the climbed surface.
11. Clone charges are finite and host-authoritative. A clone/teleport cycle consumes exactly one earned charge.
12. Unsafe transformations are rejected instead of pushing players through floors or walls.
13. Room-change recognition must stop/reverse the drip danger promptly while retaining the five-second room confirmation rule.
14. Solo round start stays available only as an explicit developer/test mode. Production play requires the configured minimum player count.
15. All networked gameplay remains host-authoritative and must be validated on two real machines/browsers.

## Non-negotiable architecture rules

- Web-first remains active; no GodotSteam work in Variante 1.2.
- Gameplay continues to use Godot high-level multiplayer APIs.
- Transport-specific work remains behind the `Net` layer.
- Paint is synchronized as actions/events, never as whole textures.
- A map prop may become transformable only through the approved Prop Registry.
- The same canonical prop scene must be used for map decoration and player transformation whenever possible.
- Every approved prop must pass paint, clone, collision, scanner, late-join, and browser-performance validation.
- No direct commits to `main`; all work uses small reviewable branches and pull requests.
- Owners remain `TBD` until Travis and Maxim assign them together.

## Status legend

- Done = merged into main
- In progress = active branch/work exists
- Next = first planned work
- Not started = planned but not started
- Blocked = dependency not complete
- Decision gate = implementation pauses for team acceptance
- TBD = owner or detail not assigned

## Baseline

- Starting gameplay baseline: merged V1 foundation through PR #29 (`f3b7297`) or the newest reviewed `main` at the moment this plan is implemented.
- Current active map before this plan: House/Map 1.
- New active target map: Casino, two floors.
- Historical House assets/scenes may remain archived for regression reference but must not be the active production map.

---

# Phase 10 — Plan Lock, Version Guard and Casino Foundation

## Goal

Create the safe development foundation for Variante 1.2 and move all following work onto the new Casino environment without prematurely producing final decoration.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 10A | `planning/post-playtest-build-plan-v1-2` | TBD | Next | Add this plan, SPEC v1.2 override, README current-plan note, and decision log |
| 10B | `feature/build-protocol-version-guard` | TBD | Not started | Show build hash/protocol in lobby and reject incompatible clients |
| 10C | `feature/casino-two-floor-graybox` | TBD | Not started | Build the two-floor Casino graybox, stairs, room volumes, doors, safe spawns, and test routes |
| 10D | `feature/casino-safety-volumes` | TBD | Blocked by 10C | Add out-of-bounds recovery, kill/recovery zones, last-safe-position support, and debug markers |
| 10E | `test/casino-graybox-traversal` | TBD | Blocked by 10C–10D | Validate scale, exits, room detection, stairs, collisions, and two-machine traversal |

## Casino graybox requirements

- Two accessible floors.
- Clear seeker and hider spawns.
- Every gameplay room has at least two practical exits unless explicitly approved as a high-risk room.
- Room volumes do not overlap unpredictably at doors, stairs, or balconies.
- The graybox includes representative tight spaces, corners, stairs, railings, large floor areas, and wall surfaces for transformation and climbing tests.
- Final decoration is intentionally deferred until the prop pipeline is proven.

## Exit criteria

- Both clients display the same build/protocol version.
- Incompatible protocol versions cannot enter the same game.
- A two-player WebRTC round can load and traverse the Casino graybox on two machines.
- Falling outside the map recovers or eliminates the player predictably.
- Room detection is stable on both floors.

---

# Phase 11 — Critical Gameplay Stabilization on Casino

## Goal

Fix all high-priority playtest failures before adding large new mechanics.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 11A | `fix/round-start-authoritative-reset` | TBD | Not started | Force every player to start each round as a clean slime with reset paint, clones, progression, camera, collision, and rotation state |
| 11B | `fix/clone-charge-consumption` | TBD | Not started | Make clone charges finite, host-authoritative, and consumed exactly once per completed clone/teleport use |
| 11C | `fix/safe-transform-space-check` | TBD | Not started | Validate destination collision before any size/form change and reject unsafe transforms |
| 11D | `fix/pending-clone-activation` | TBD | Blocked by 11B | Save exact placement position/rotation, keep clone non-colliding/invisible until owner clears the activation radius, then activate |
| 11E | `fix/rotation-room-transition-response` | TBD | Not started | Pause/reverse active drip danger immediately on credible room entry while keeping five-second room confirmation |
| 11F | `feature/developer-solo-start-toggle` | TBD | Not started | Keep one-player rounds only behind explicit test mode; production mode enforces minimum players |
| 11G | `test/critical-round-regressions` | TBD | Blocked by 11A–11F | Add automated and two-machine regressions for reset, transforms, clones, rotation, and solo/production rules |

## Safe transformation contract

Before applying a transform, the host must validate:

1. requested prop exists and is unlocked;
2. canonical collision profile is available;
3. target shape fits at the current location;
4. no floor/wall/ceiling penetration occurs;
5. no invalid displacement through corners occurs;
6. if no valid placement exists in the approved small search radius, the transform is rejected with clear UI feedback.

## Clone contract

- Earned charge count is owned by the host.
- Placing a pending clone does not duplicate charges.
- Teleporting consumes the associated clone and exactly one charge.
- Cancelled/invalid placement cannot create free charges.
- Clone state includes full form, paint, orientation, and owner link.
- A destroyed active clone keeps the existing death-link rule.

## Exit criteria

- No wall/floor teleport from small-to-large transformations in the Casino test matrix.
- No infinite clone loop.
- Clone appears at the exact stored transform after the owner leaves the activation radius.
- Round start always produces a clean slime state.
- Entering another room promptly interrupts visible drip danger, then confirms/reset rules after five seconds.

---

# Phase 12 — Unified Custom Prop, Paint and Clone Pipeline

## Goal

Replace the fragile imported-gameplay-prop approach with a controlled pipeline that supports the full Casino map and every gameplay system.

## Core decision

The active Casino map and decoration will use a new project-controlled asset ecosystem. Kenney House/Furniture assets are removed from the active production map. Historical files may remain archived only when licenses and repository history require it.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 12A | `planning/custom-prop-technical-standard` | TBD | Not started | Define mesh, UV, material, pivot, scale, collision, naming, poly, texture, paint, and web budgets |
| 12B | `feature/canonical-prop-registry` | TBD | Blocked by 12A | Create stable prop IDs and metadata used by map placement, scanner, transform, paint, clone, and network sync |
| 12C | `fix/multipart-paint-surface-contract` | TBD | Blocked by 12A–12B | Make fill, brush, clear, eyedropper, and sync deterministic across every approved mesh and surface |
| 12D | `fix/clone-complete-form-paint-copy` | TBD | Blocked by 12C | Copy all mesh/surface paint state into clones and through late join |
| 12E | `feature/prop-validation-harness` | TBD | Blocked by 12B–12D | Automated/import-time validation plus a test room for paint, clone, collision, transform, scanner, and performance |
| 12F | `feature/casino-prop-pilot-set` | TBD | Blocked by 12E | Produce a small approved Casino pilot set across large/medium/small tiers |
| 12G | `review/prop-pipeline-decision-gate` | Shared | Decision gate | Travis + Maxim approve visual style, paint quality, creation workflow, and performance before mass production |

## Canonical prop definition

Each approved prop must define at least:

- stable `prop_id`;
- display name and category;
- canonical scene/mesh;
- size tier and unlock requirement;
- collision profile and ground offset;
- pivot/origin rules;
- paintable mesh/surface mapping;
- scanner target shape;
- clone compatibility;
- wall-climb compatibility;
- network serialization version;
- browser performance budget;
- source/license metadata.

## Asset creation workflow

1. Concept/reference approved.
2. Model produced through the chosen controlled workflow (manual low-poly, Blender/Godot primitives, commissioned work, or AI-assisted generation).
3. Mesh cleanup and scale normalization.
4. Clean UV unwrap and non-overlapping paint regions where required.
5. Standard materials compatible with the paint shader.
6. Collision and pivot authored.
7. Import into the canonical prop scene.
8. Registry entry created.
9. Automated validation passes.
10. Manual full-paint, partial-paint, eyedropper, clone, scanner, transform, wall-climb, and network test passes.
11. Only then may the prop be used as active Casino decoration.

## Exit criteria

- Pilot props fill/paint correctly on all intended parts without gray leftovers or corrupted brown/green artifacts.
- Clones reproduce the full painted form exactly on both clients.
- Map decoration and transformed form use the same approved canonical prop source.
- The team accepts one consistent visual style before mass Casino production.

---

# Phase 13 — Scanner Transformation System

## Goal

Let hiders scan approved Casino objects and transform into the selected object while progression, collision, and networking remain authoritative.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 13A | `feature/prop-scanner-targeting` | TBD | Blocked by 12B | Raycast approved objects, highlight valid targets, and expose stable prop ID |
| 13B | `feature/scanner-transform-ui` | TBD | Blocked by 13A | Add target name, size tier, unlock state, input hint, and failure feedback |
| 13C | `feature/scanner-host-validation` | TBD | Blocked by 11C, 13A | Host validates registry, unlock tier, round state, and safe transform space |
| 13D | `feature/scanned-prop-state-sync` | TBD | Blocked by 13C | Sync scanned form, orientation, paint state, and late join |
| 13E | `test/scanner-transform-matrix` | TBD | Blocked by 13A–13D | Test every pilot prop, tier lock, invalid target, tight space, clone, late join, and two-machine state |

## Rules

- “Every object” means every **approved and registered transformable Casino object**, not every arbitrary mesh or decoration.
- Locked size tiers remain visible but cannot be selected until enough NPC slimes have been eaten.
- Decorative objects without valid paint/collision/network definitions cannot be scanned.
- Failed transforms never move the player through geometry.

## Exit criteria

- A hider can scan an approved Casino prop and transform into that exact canonical form.
- Locked tiers are enforced by the host.
- Scanner, painting, cloning, wall climbing, and late join all agree on the same prop ID and scene.

---

# Phase 14 — Camera, Zoom and First-Person Seeker

## Goal

Improve control precision and make seeker gameplay a distinct first-person role.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 14A | `feature/gameplay-camera-zoom` | TBD | Not started | Mouse-wheel zoom with min/max distance, smoothing, and camera collision |
| 14B | `feature/paint-mode-camera-zoom` | TBD | Blocked by 14A | Closer paint-specific limits, orbit preservation, model clipping prevention, and input isolation |
| 14C | `feature/seeker-first-person-camera` | TBD | Not started | First-person seeker view, FOV rules, role transitions, and spectator compatibility |
| 14D | `feature/paintball-viewmodel-worldmodel` | TBD | Blocked by 14C | First-person weapon model plus world model visible to other players |
| 14E | `feature/seeker-aim-feedback` | TBD | Blocked by 14C–14D | Crosshair, cooldown feedback, muzzle effect, shot animation, and hit/miss readability |
| 14F | `test/camera-seeker-regression` | TBD | Blocked by 14A–14E | Test zoom, clipping, paint input, role reset, weapon origin, and two-machine shot alignment |

## Exit criteria

- Normal and Paint Mode zoom work without camera penetration or input conflicts.
- Seeker view is first person.
- The seeker sees a weapon; other players see the corresponding world model.
- Projectiles originate and resolve consistently with the visible aim direction.

---

# Phase 15 — Jumping and Wall Climbing for Slimes and Props

## Goal

Add the new traversal identity while preventing map escape, network desync, and collision exploits.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 15A | `feature/hider-jump-foundation` | TBD | Not started | Ground detection, jump input, air control, network state, and reset rules |
| 15B | `feature/surface-traversal-core` | TBD | Blocked by 10C–10D | Detect climbable surfaces, align movement to wall normals, transition floor/wall, and detach safely |
| 15C | `feature/slime-wall-climb-presentation` | TBD | Blocked by 15B | Flatten/hang slime animation or shader deformation, eye orientation, and readable movement |
| 15D | `feature/prop-wall-climbing` | TBD | Blocked by 12B, 15B | Allow every approved transformed prop to climb while preserving paint and canonical collision |
| 15E | `fix/wall-climb-corners-and-boundaries` | TBD | Blocked by 15B–15D | Prevent corner warps, ceiling/floor tunneling, out-of-map routes, stair exploits, and invalid detach states |
| 15F | `test/surface-traversal-network-matrix` | TBD | Blocked by 15A–15E | Test slime and all pilot prop tiers across walls, corners, doors, stairs, floor transitions, and two clients |

## Initial traversal rules

- Wall climbing is available to the slime and every approved transformed prop.
- Slime uses the dedicated flattened/hanging presentation.
- Props align their canonical collision and visible form to the surface and preserve their paint state.
- Ceiling traversal is not assumed; it must be separately approved after the wall prototype.
- Surface movement remains host-validated.
- Climbing cannot bypass the active Casino bounds, seeker-only spaces, or round barriers.
- Size-tier speed differences continue to apply unless a later balance branch explicitly changes them.

## Jump clarification gate

The first implementation must support hider jumping in slime form. Prop jumping is a separate balance decision inside Phase 15 and must not be silently enabled without Travis + Maxim approval.

## Exit criteria

- Slime and all approved pilot props can enter, move on, and leave climbable walls without desync.
- Paint and clone state remain correct after climbing.
- No known route allows falling through geometry or escaping the Casino.

---

# Phase 16 — Active Fleeing NPC Slimes

## Goal

Turn NPC feeding into an active Prep-phase hunt: NPC slimes detect hiders, flee, get caught, and are eaten to unlock stronger transformation tiers and clone charges.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 16A | `planning/active-npc-behavior-contract` | TBD | Not started | Lock perception, flee distance, speed, catch condition, spawn count, floor rules, and Prep timing |
| 16B | `feature/casino-npc-navigation` | TBD | Blocked by 10C | Navigation/pathing on both floors, stairs, obstacle handling, and anti-stuck recovery |
| 16C | `feature/npc-hider-detection-and-flee` | TBD | Blocked by 16A–16B | Host-authoritative detection, target selection, flee steering, and animation state |
| 16D | `feature/npc-catch-and-eat` | TBD | Blocked by 16C | Catch state, interaction, eat timing, cancellation, progression reward, and anti-double-eat protection |
| 16E | `feature/npc-round-lifecycle` | TBD | Blocked by 16C–16D | Spawn selection, Prep-only behavior, visible Hunt-start despawn, reset, and late join |
| 16F | `test/active-npc-two-floor-load` | TBD | Blocked by 16B–16E | Validate multiple NPCs, both floors, multiple hiders, network traffic, browser FPS, and progression correctness |

## Rules

- NPC simulation is host-authoritative.
- NPCs actively flee from hiders during Prep.
- NPCs are not active gameplay targets during Hunt; remaining NPCs disappear at Hunt start.
- One NPC can reward only one hider once.
- The existing cumulative progression table remains unless a dedicated balance decision changes it.
- Prep duration may require a later balance adjustment after real NPC tests.

## Exit criteria

- NPCs navigate both Casino floors without frequent stuck states.
- A hider must genuinely catch an NPC before eating it.
- Eating updates form tiers and clone charges exactly once for all clients.
- Remaining NPCs cleanly disappear at Hunt start.

---

# Phase 17 — Full Casino Asset and Decoration Replacement

## Goal

Replace the entire active map and decoration with the approved custom/project-controlled Casino ecosystem after the gameplay pipeline is proven.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 17A | `planning/casino-art-direction-and-prop-list` | TBD | Blocked by 12G | Lock visual style, room list, prop list, size tiers, paint surfaces, and production budget |
| 17B | `feature/casino-large-prop-set` | TBD | Blocked by 17A | Produce and validate large Casino props |
| 17C | `feature/casino-medium-prop-set` | TBD | Blocked by 17A | Produce and validate medium Casino props |
| 17D | `feature/casino-small-prop-set` | TBD | Blocked by 17A | Produce and validate small Casino props with fair minimum target sizes |
| 17E | `feature/casino-architecture-final` | TBD | Blocked by 17A | Replace graybox architecture with final project-controlled environment geometry/materials |
| 17F | `feature/casino-decoration-and-gameplay-dressing` | TBD | Blocked by 17B–17E | Dress both floors using canonical approved props and fair hiding/scanner layouts |
| 17G | `feature/casino-lighting-paint-surfaces` | TBD | Blocked by 17E–17F | Final lighting plus paint-friendly walls, floors, carpets, tiles, and readability |
| 17H | `test/casino-final-walkthrough` | Shared | Decision gate | Travis + Maxim accept scale, style, navigation, hiding fairness, scanner coverage, climbing, and visual quality |

## Content principles

- One visual ecosystem; do not mix incompatible pack styles.
- The active Casino contains no dependency on the old House composition.
- Map decoration uses canonical registered prop scenes wherever those objects are transformable.
- Some visual-only decorations may remain non-transformable but must still belong to the same visual ecosystem.
- Tiny objects must meet fair visibility, collision, shooting, and web-performance thresholds.
- Paint-friendly material design remains part of the core gameplay, not only an art concern.

## Exit criteria

- The House is no longer the active map.
- Both Casino floors use the accepted new art direction and project-controlled assets.
- Every transformable Casino object is registry-backed and validated.
- Final dressing does not reintroduce paint, clone, collision, scanner, or performance failures.

---

# Phase 18 — UI, Audio, Performance and Full Multiplayer Validation

## Goal

Integrate Variante 1.2 into a coherent, testable web build and prepare the next external playtest.

## Branches

| Order | Branch | Owner | Status | Scope |
|---|---|---|---|---|
| 18A | `feature/v1-2-gameplay-hud` | TBD | Not started | Scanner target, unlock tier, clone charges, room/drip state, climb/jump hints, seeker cooldown, and errors |
| 18B | `feature/v1-2-audio-feedback` | TBD | Not started | Scan, NPC flee/catch/eat, transform denied, clone, teleport, jump, wall attach/detach, drip recovery, and Paintball feedback |
| 18C | `test/v1-2-automated-regression-suite` | TBD | Blocked by Phases 11–17 | Expand automated coverage for all new contracts |
| 18D | `test/v1-2-browser-performance-budget` | TBD | Blocked by Phases 12, 16, 17 | Measure FPS, memory, load time, paint textures, NPC load, clones, and network traffic |
| 18E | `test/v1-2-two-machine-full-round` | Shared | Blocked by 18C–18D | Full Windows/Mac/browser or equivalent two-machine regression |
| 18F | `test/v1-2-multiplayer-scale-wave` | Shared | Blocked by 18E | Controlled 4-player then 6–8-player validation |
| 18G | `release/web-playtest-v1-2` | Shared | Blocked by 18E–18F and deployment | Fresh Web export, current itch build, public signaling/WSS/TURN readiness, and tester protocol |

## Required test matrix

- Lobby and build/protocol mismatch.
- Clean round start and full reset.
- Normal/Paint zoom.
- Seeker first person and visible gun.
- Scanner across every approved size tier.
- Unsafe transform rejection in corners, stairs, doors, walls, and tight objects.
- Full multi-surface painting, fill, clear, eyedropper, clone copy, and late join.
- Finite clone charges and pending activation.
- Jumping and wall climbing for slime and approved props.
- Active fleeing NPCs on both floors.
- Rotation/drip interruption and five-second room confirmation.
- Out-of-bounds recovery.
- Multiple full rounds without stale state.
- Browser performance at intended player/NPC/prop/clone load.

## Release gate

Variante 1.2 is not considered complete until:

- no known P0/P1 gameplay blocker remains;
- all network-critical systems pass two-machine validation;
- the Casino replaces the House as the active production map;
- all active transformable props pass the canonical validation contract;
- the current web build is rebuilt from the reviewed merge commit;
- public tester infrastructure and version compatibility are ready.

---

# Dependency and parallel-work rules

## Required sequence

1. Phase 10 foundation and Casino graybox.
2. Phase 11 critical fixes.
3. Phase 12 prop pipeline and pilot set.
4. Phase 13 scanner.
5. Phase 15 traversal foundation before final Casino dressing.
6. Phase 16 active NPCs before final navigation/art acceptance.
7. Phase 17 final Casino production.
8. Phase 18 integration and release validation.

## Possible controlled parallel work

- Phase 14 camera/seeker work may run alongside later Phase 12/13 work only after both branches list expected files and avoid central-file conflicts.
- Prop asset production may begin after Phase 12G acceptance while scanner or camera branches continue, provided canonical scene/registry contracts are frozen.
- UI/audio work can begin late in Phases 15–17 after event names and state contracts are stable.

## Central files requiring sequential coordination

At minimum:

- `project.godot`
- main gameplay scene(s)
- player controller/capsule scripts
- game/round state autoloads
- transform and prop registry systems
- paint/clone state systems
- map root and room detection
- network protocol/version definitions

Before any parallel work, both Claude Code sessions must list the exact files they expect to modify.

---

# Assignment session after plan merge

Owners are deliberately `TBD` in this plan.

Travis and Maxim should hold one short assignment session after the planning PR is reviewed. For each branch, decide:

- Owner: Travis, Maxim, or Shared.
- Reviewer: the other developer.
- Dependency/base branch.
- Expected files.
- Manual test owner.
- Whether a two-machine test is required before merge.

No implementation branch should start until its owner and dependency are recorded in the active plan.

---

# Explicitly deferred or separate decisions

These are not silently included:

- Steam/GodotSteam work remains later platform V2.
- Ceiling traversal is not approved by the wall-climb decision.
- Prop jumping is not automatically approved; Phase 15 contains a decision gate.
- Exact final Casino prop count and final room list are decided in Phase 17A.
- Final public hosting/WSS/TURN choice remains a deployment decision before external waves.
- Monetization, cosmetics shop, Steam price, and store launch remain outside Variante 1.2.
