# Phase 5–9 Status — Slime-Verstecken

Owner of every branch: **Travis**. Plan: `planning/PHASE_5_9_EXECUTION.md`.

Legend: ⏳ not started · 🔨 in progress · ✅ implemented + automated checks
green (pushed) · ⛔ blocked. **No branch here is "Done" in the BUILD_PLAN
sense** — that requires Travis' manual validation (two-machine tests,
gameplay approval). This file records what automation actually did, with
evidence. Manual/external validation is never claimed.

## Chain overview

| # | Branch | Parent | Status | SHA | Tests |
|---|--------|--------|--------|-----|-------|
| 0 | planning/phase-5-9-execution | main | ✅ | bd82bbe | n/a (docs) |
| 1 | feature/round-phases | 0 | ✅ | dbbe7d4 | 42/42 new + full regression |
| 2 | feature/npc-slimes-feeding | 1 | ✅ | df5973e | 25/25 new + full regression |
| 3 | feature/eat-progression-table | 2 | ✅ | ad51c77 | 39/39 new + full regression |
| 4 | feature/rotation-timer | 3 | ✅ | b4425f8 | 24/24 new + full regression |
| 5 | feature/win-lose-reset | 4 | ✅ | 2837358 | 26/26 new + FULL suite (12 files, 437 checks) |
| 6 | feature/paintball-gun | 5 | ✅ | 1ba2783 | 19/19 new + FULL suite (13 files, 456 checks) |
| 7 | feature/seeker-splatter | 6 | ✅ | 474d114 | 15/15 new + FULL suite (14 files, 471 checks) |
| 8 | feature/seeker-cooldown | 7 | ✅ | 953f07e | 13/13 new + FULL suite (15 files, 484 checks) |
| 9 | feature/spectator-mode | 8 | ✅ | 271f549 | 17/17 new + FULL suite (16 files, 501 checks) |
| 10 | feature/map1-house-graybox | 9 | ✅ | abcaa17 | 15/15 new + FULL suite (17 files, 516 checks) |
| 11 | feature/map1-npc-spawn-markers | 10 | ✅ | e0e1ae1 | 7/7 new + FULL suite (18 files, 523 checks) |
| 12 | feature/map1-prop-slots | 11 | ✅ | b0b8549 | 10/10 new + FULL suite (19 files, 533 checks) |
| 13 | feature/map1-kenney-dressing | 12 | ✅ | 7e62b90 | 9/9 new + FULL suite (20 files, 542 checks) + import clean |
| 14 | feature/web-export-smoke-test | 13 | ✅ | cf76dba | CLI export exit 0 + Chrome smoke incl. browser-WebRTC hosting |
| 15 | feature/itch-playtest-build | 14 | ✅* | 1692a0d | pipeline proven to the API gate; upload blocked: itch email unverified (Travis) |
| 16 | planning/playtest-protocol | 15 | ✅ | 698101d | n/a (docs) |
| 17 | feature/clones | 16 | ✅ | b6c5678 | 19/19 new + FULL suite (21 files, 561 checks) |
| 18 | feature/clone-death-link | 17 | ✅ | 9fb2fbe | 15/15 new + FULL suite (22 files, 576 checks) |
| 19 | feature/clone-swap-teleport | 18 | ✅ | (head of branch) | 13/13 new + CHAIN EXIT SUITE (23 files, 589 checks + import + boot) |

## Preflight evidence (2026-07-14, operator Travis)

- `main` clean and up to date with origin (359d067), baseline headless boot:
  exit 0, "Boot OK — Godot 4.7-stable".
- Godot console binary:
  `C:\Users\tthoe\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`.
- Web export templates 4.7.stable installed (all `web_*.zip` variants);
  `export_presets.cfg` preset "Web": GL Compatibility project, extensions
  off, threads on, `export/web/index.html`; `/export/` gitignored.
- Kenney root `C:\Projects\Prophunt_External\Kenney` → `FurnitureKit/`,
  `BuildingKit/` present.
- butler `C:\Tools\butler\butler.exe` authenticated; target
  `ttravis17/slime-verstecken-playtest:web-playtest` reachable — **channel
  does not exist yet** ("No channel web-playtest found"), so Phase 8 is a
  first push onto the (expected hidden) page.
- Chrome extension responding (tab group created).

## Per-branch evidence

### 0 · planning/phase-5-9-execution — ✅ bd82bbe

- Scope: this file + `planning/PHASE_5_9_EXECUTION.md`. No code.
- SHA convention: a branch's own SHA lands in this table with the NEXT
  branch's update (a commit cannot contain its own hash); the final report
  lists every SHA from git directly.

### 1 · feature/round-phases — ✅

- Changed: `scripts/game_state.gd` (host-authoritative phase machine +
  player registry + role assignment + late-join snapshot + disconnect
  cleanup), `scripts/round/round_locator.gd` (new — ancestor-walk resolver
  so test worlds carry their own GameState at the autoload's relative
  path), `scripts/round/round_hud.gd` + `scenes/round_hud.tscn` (new),
  `scenes/gray_room.tscn` (sealed SeekerSpawnRoom at x=+20 + spawn-marker
  groups), `scenes/main.tscn` (RoundHud instance),
  `scripts/player_capsule.gd` (role/phase teleport hooks),
  `tests/round_phases_test.gd` (new).
- Tests (2026-07-14, all exit 0):
  - `tests/round_phases_test.gd` — PASS 42/42 (TDD: first run red — 3
    scene-contract FAILs + missing `end_seconds` script error, then green).
  - Regression: transform 80, speed_tiers 21, network_transform 36,
    paint_prototype 52, eyedropper 26, grundieren 25, paint_sync 41 — all
    PASS; headless boot exit 0 "Boot OK"; `git diff --check` clean.
- Decisions recorded: mid-round joiners = spectators until next round;
  solo round = 1 hider / 0 seekers (dev sandbox); offline (no real peer)
  runs the same code path without RPCs.
- Manual (Travis): two-machine phase flow, HUD readability, seeker box
  blindness.

### 2 · feature/npc-slimes-feeding — ✅

- Changed: `scripts/round/npc_manager.gd` + `scripts/npc_slime.gd` +
  `scenes/npc_slime.tscn` (new), `scripts/round/round_locator.gd`
  (locate_named + has_real_peer helpers), `scripts/game_state.gd`
  (npcs_per_hider, eaten_of/record_eaten/hider_ids, npc_eaten via registry
  diff, public is_round_authority), `scenes/gray_room.tscn` (6 npc_spawn
  markers), `scripts/player_capsule.gd` (E-hold-1s feeding + prompt push,
  "fressen" action), `scripts/round/round_hud.gd` + `scenes/round_hud.tscn`
  (eat prompt + progress + eaten count), `scenes/main.tscn`
  (Npcs/NpcSpawner/NpcManager), `tests/npc_feeding_test.gd` (new).
- Tests (2026-07-14, all exit 0): new test PASS 25/25 (TDD red first:
  missing markers + missing manager script). Caught a real bug mid-branch:
  host-as-eater used rpc_id at itself (illegal without call_local) — fixed
  with a direct host path; test extended to force BOTH host-as-hider and
  client-as-hider eats. Full regression (7 suites + round_phases 42) PASS;
  boot exit 0; `git diff --check` clean.
- Host validates phase (PREP only), role (hider), liveness, NPC existence,
  and real distance (2.5 m); spoofed eater ids rejected via sender check.
- Manual (Travis): slurp/prompt feel, poof visibility, two-machine feeding.

### 3 · feature/eat-progression-table — ✅

- Changed: `scripts/round/progression.gd` (new — pure SPEC.md 8 table incl.
  clone budget for Phase 9), `scripts/game_state.gd` (record_eaten caps at
  3; 4th NPC still consumable, buys nothing — recorded decision),
  `scripts/player_capsule.gd` (transform gate: hiders limited by unlocks
  mid-round, seekers never transform mid-round, LOBBY sandbox),
  `scripts/round/round_hud.gd` + `scenes/round_hud.tscn` (unlock overview
  line + self-clearing denial notice), `tests/progression_test.gd` (new).
- Tests (2026-07-14, all exit 0): new test PASS 39/39 (red first: missing
  progression.gd, then ungated transform). Full regression (9 suites),
  boot, `git diff --check` — clean.
- Manual (Travis): unlock-loop feel on two machines, HUD wording.

### 4 · feature/rotation-timer — ✅

- Changed: `scripts/round/room_volume.gd` (new — math-based contains_global,
  convention: group room_volume + BoxShape3D child),
  `scripts/round/rotation_tracker.gd` (new — owner-side timer: room entry
  starts it, 5 s dwell confirms changes while the old timer keeps running,
  grace drives the drip 0→1, then request_elimination("rotation")),
  `scenes/gray_room.tscn` (RoomVolumeWest/East halves so the mechanic tests
  pre-Map-1), `scenes/player_capsule.tscn` (+DripPuddle, +RotationTracker,
  +rotation_drip in the replication config), `scripts/player_capsule.gd`
  (replicated rotation_drip drives the puddle on every peer),
  `scripts/game_state.gd` (dwell/grace settings, SETTINGS BROADCAST at round
  start + late join — trackers on client machines run the host's values —
  elimination data layer: request_elimination victim-side, eliminate_player
  host-side, player_eliminated broadcast), round HUD rotation line,
  `tests/rotation_timer_test.gd` (new).
- Tests (2026-07-14, all exit 0): new test PASS 24/24 — idle expiry
  eliminates on both peers with replicated drip, confirmed room change
  resets (alive 0.3 s past the old deadline), door-sill bounce does NOT
  reset (death on the original schedule, 1.42 s), PREP is rotation-free,
  seekers untouched, reset_timer() hook present for Phase 9. Full
  regression (10 suites) + boot + `git diff --check` clean.
- Overlap resolution honored: this branch stops at the DATA layer
  (alive=false + signal); death behavior lands in feature/win-lose-reset.
- Manual (Travis): drip readability at distance, warning feel, two-machine.

### 5 · feature/win-lose-reset — ✅  (PHASE 5 COMPLETE — implementation)

- Changed: `scripts/game_state.gd` (end_result payload, win checks — all
  hiders dead → seekers win, hunt expiry → each surviving hider wins
  individually, hider disconnect can end the round; reset_round() clears
  the registry and broadcasts round_reset; END→LOBBY runs the reset),
  `scripts/player_capsule.gd` (derived ghosting from the replicated
  registry: eliminated players AND mid-round joiners are invisible,
  non-colliding, input-dead on every peer; round_reset re-slimes, dries
  the drip, respawns), `scripts/round/round_hud.gd` + `scenes/round_hud.tscn`
  (END screen with winner + personal outcome, "Du bist raus" banner),
  `tests/win_lose_reset_test.gd` (new).
- Test-infrastructure fix in the same commit: my five Phase 5 test files
  treated a TIMEOUT as PASS when every ran check succeeded — timeouts now
  count as failures (exit 1). Also made the npc_feeding HUNT-gate check
  timing-robust: the new (correct) complete reset wipes the registry at
  round end, which the old 1.2 s hunt window could race.
- Tests (2026-07-14): new test PASS 26/26 (red first: round_reset signal
  missing). PHASE 5 EXIT SUITE: all 12 test files green (437 checks
  total), boot exit 0, `git diff --check` clean.
- Manual (Travis): full two-machine round — phases, feeding, unlocks,
  rotation drip, elimination ghosting, END screen, reset. HUD wording.

### 6 · feature/paintball-gun — ✅

- Changed: `scripts/seeker/seeker_combat.gd` + `scripts/seeker/paintball.gd`
  + `scenes/paintball.tscn` (new — host-validated fire requests, RAY-SWEPT
  host-side flight so 35 m/s never tunnels 0.2 m walls, direct hit on an
  alive hider = elimination via the Phase 5 entry, one ball in flight per
  seeker, shot_hit/shot_missed for the splatter + cooldown branches),
  `scenes/main.tscn` (Projectiles/ProjectileSpawner/SeekerCombat),
  `scripts/player_capsule.gd` (LMB fire for armed seekers + crosshair
  state), round HUD crosshair, `tests/paintball_test.gd` (new).
- ALSO in this branch — ghost-collider hardening after a real bug hunt:
  the rotation test flaked (~40 %) because capsules parked on a previous
  round's exact death spot got depenetration-launched by residual physics
  state in the shared-space test harness. Evidence trail: phantom collider
  named by shape query (`ClientWorld/Players/1` body at the death spot
  while its node showed the seeker box). Production hardenings shipped:
  (1) ghosts disable their collision SHAPE (walk-through corpses, clean
  re-registration), (2) remote copies pin their collider to the synced
  transform every physics tick — protects host-side paintball raycasts
  too. Phase 3's transform test updated to assert the copy contract
  behaviorally (no self-simulation) instead of is_physics_processing().
  Residual harness artifact avoided by parking each test round at fresh
  coordinates; real-machine ghost/reset behavior stays on Travis' manual
  checklist (it always was).
- Tests (2026-07-14): paintball 19/19 (red first: missing combat script;
  then a test-geometry fix — the wall shot originally flew through the
  hider's parking spot). rotation_timer 12/12 + 3/3 consecutive green
  after the fix. FULL suite: 13 files, 456 checks, all exit 0; boot ok;
  `git diff --check` clean.
- Manual (Travis): aim feel, projectile speed/arc, two-machine hit
  registration, crosshair readability.

### 7 · feature/seeker-splatter — ✅

- Changed: `scripts/seeker/splatter_manager.gd` + `scripts/seeker/splatter.gd`
  + `scenes/splatter.tscn` (new — event-synced {pos, normal, seed}, seeded
  identical blob clusters on every peer, bounded history with late-join
  replay, round-reset clear), `scripts/seeker/paintball.gd` (map miss →
  splatter; mid-air fizzle leaves nothing), `scripts/player_capsule.gd`
  (apply_splatter_spray — near-miss spray routed through the OWNER's own
  PaintSync stroke events, exactly-once, late-join safe),
  `scenes/main.tscn` (Splatters + SplatterManager),
  `tests/splatter_test.gd` (new).
- Events-only rule upheld: splatter = 1 RPC with 3 small values; prop spray
  = normal int64 paint events; no texture ever crosses the wire.
- Tests (2026-07-14): new test PASS 15/15 (red first: missing manager; one
  test fix — the cap is a built-in bound and must shrink on every peer).
  FULL suite: 14 files, 471 checks, boot, diff — all green.
- Manual (Travis): splatter look/size on surfaces, spray readability on
  props, two-machine.

### 8 · feature/seeker-cooldown — ✅

- Changed: `scripts/seeker/seeker_combat.gd` (host cooldown ledger keyed on
  MISSES only — spec-literal "Fehlschuss = 4-s-Cooldown"; a hit re-arms
  instantly; value from GameState.paintball_cooldown; per-shooter HUD
  notify; cleared with projectiles on phase change/reset), round HUD
  ("Nachladen… n.n s" countdown), `tests/cooldown_test.gd` (new, 3 peers
  so a hit doesn't end the round). Earlier Phase 6 tests updated to shrink
  the host cooldown setting and wait it out between shots (they predate
  the mechanic).
- Note for playtest (SPEC.md 11 Rechenbasis): hit-⇒-no-cooldown is the
  literal reading; if it proves too generous, the ledger keys on
  report_hit too — one-line change.
- Tests (2026-07-14): new test PASS 13/13 (red first: cooldown_left
  missing). FULL suite: 15 files, 484 checks, boot, diff — green.
- Manual (Travis): reload feel at the real 4 s, HUD readability.

### 9 · feature/spectator-mode — ✅  (PHASE 6 COMPLETE — implementation)

- Changed: `scripts/round/spectator_camera.gd` + `scenes/spectator_camera.tscn`
  (new — local-only free-fly rig: WASD camera-relative, Space/Ctrl
  rise/sink, mouse look; spawned next to the corpse), `scripts/round/dead_chat.gd`
  (new — host-relayed dead-only chat: dead-sender gate + dead-only fan-out
  server-side, never in the UI), `scripts/player_capsule.gd` (ghosting on
  the OWNING machine now hands the view to the rig; reset restores the
  player camera; _exit_tree never strands a rig), round HUD (Totenchat box
  + log while dead), `scenes/main.tscn` (DeadChat), `tests/spectator_test.gd`
  (new).
- Tests (2026-07-14): new test PASS 17/17 (red first: dead_chat.gd
  missing) — rig only on the dead machine, chat isolation verified in both
  directions, END-screen chat between two dead peers, reset cleanup.
  PHASE 6 EXIT SUITE: 16 files, 501 checks, boot, diff — all green.
- Manual (Travis): fly feel, chat usability, END-screen flow, two-machine.

### 10 · feature/map1-house-graybox — ✅

- Changed: `maps/map1_house.tscn` (new — Wohnhaus graybox: 3×3 grid of
  6×6 m rooms with the Flur as the central hub, 12 doorways ≥ 1.6 m so
  EVERY room has ≥ 2 exits (SPEC.md 13 anti-death-trap rule), one flat
  repaintable floor color per room, 9 RoomVolumes on the Phase 5
  convention, doorway markers so exits are machine-checkable, sealed
  seeker box north of the house, spawn markers by group; scene generated
  via a one-shot script and committed as canonical data),
  `scenes/main.tscn` (GrayRoom → Map1House), `scripts/main.gd` (spawn
  marker found by GROUP, not path — maps decide spawns now),
  `tests/map1_graybox_test.gd` (new). gray_room.tscn stays for tests.
- Tests (2026-07-14): new test PASS 15/15 (red first: scene missing).
  FULL suite incl. boot on the new map: 17 files, 516 checks — green.
- Manual (Travis): walkthrough scale/camera-in-doorways judgment, room
  color readability, two-machine roam.

### 11 · feature/map1-npc-spawn-markers — ✅

- Changed: `maps/map1_house.tscn` (30 npc_spawn markers: 3 per room + one
  extra in Küche/Flur/Wohnzimmer, floor height, none in the seeker box —
  regenerated via the same one-shot generator; the diff includes some
  serializer reordering, structure verified by the graybox test),
  `tests/map1_npc_markers_test.gd` (new).
- Tests (2026-07-14): new test PASS 7/7 (red first: 0 markers) — placement
  rules + an OFFLINE NpcManager integration spawn on the real map (distinct
  marker positions, no reuse). FULL suite: 18 files, 523 checks green.
- Manual (Travis): marker plausibility once furniture exists (corners,
  under tables) — expected to shift during the dressing pass.

### 12 · feature/map1-prop-slots — ✅

- Changed: `scripts/props/static_prop.gd` + three colored decoy scenes
  (`scenes/props/static_prop_{carton,bucket,cup}.tscn` — StaticBody3D,
  NEVER pure white, dims mirror the player prop forms),
  `maps/map1_house.tscn` (31 decoys: a LARGE spot in EVERY room per
  SPEC.md 13, 10 medium + 12 small scatter, all with ≥ 0.8 m NPC-marker
  clearance), `tests/map1_prop_slots_test.gd` (new).
- ALSO: root-caused the cooldown/rotation flake for real this time —
  frame-level tracing caught a capsule being DRAGGED 7.6 m in one frame:
  CharacterBody3D treats a neighbor capsule it stands on as a MOVING
  PLATFORM and inherits its teleport displacement. Production fix:
  `platform_floor_layers = 0` / `platform_wall_layers = 0` on the capsule
  (players never ride players; also fixes real-game drag on Phase 9's
  swap-teleport). The cooldown test also gained all-three-world phase
  gating and deterministic cooldown-expiry predicates.
- Tests (2026-07-15): new test PASS 10/10 (red first), cooldown 12/12
  consecutive after the fix. FULL suite: 19 files, 533 checks green.
- Manual (Travis): decoy plausibility/readability judgment.

### 13 · feature/map1-kenney-dressing — ✅  (PHASE 7 COMPLETE — implementation)

- External assets (per LOCAL_OPERATOR policy): copied ONLY the 8 Furniture
  Kit GLBs actually placed on Map 1 (cardboardBoxClosed, bookcaseClosed,
  kitchenFridge, trashcan, pottedPlant, books, lampSquareTable, radio) +
  the kit's License.txt into `assets/kenney/furniture_kit/`. No ZIPs, no
  unused files. RECORDED DECISION: the Building Kit was inspected and NOT
  used — it is a textured urban kit whose look clashes with the flat-color
  Furniture Kit; SPEC.md 14's one-ecosystem style rule wins (authorization
  to use a pack is not an obligation). Zero Building Kit files committed.
- Changed: 8 dressed decoy scenes `scenes/props/kenney_*.tscn` (Kenney
  models probed for AABB — the kit is ~¼ scale, so each scene carries its
  own scale + centering offset + fitted collision), the 3 primitive decoy
  scenes DELETED (replaced — that is this branch's purpose),
  `maps/map1_house.tscn` regenerated with room-appropriate furniture
  (fridge in the Küche, bookcases in living/office/bed/dining rooms,
  cardboard boxes elsewhere; trashcans/plants medium; books/lamps/radios
  small), `tests/map1_prop_slots_test.gd` construction check now searches
  nested GLB meshes, `tests/map1_dressing_test.gd` (new). The `--import`
  run generated the .gd.uid sidecars for every script of this chain —
  committed per repo convention (Phase 1-4 scripts have theirs).
- Tests (2026-07-15): dressing test PASS 9/9 (red first: no assets).
  PHASE 7 EXIT SUITE: 20 files, 542 checks + headless import (0 errors)
  + boot — all green.
- Manual (Travis): the LOOK (dressing judgment is the point of this
  branch); Kenney-vs-Synty stays open until the playtest gate.

### 14 · feature/web-export-smoke-test — ✅

- Changed: `tools/serve_web.ps1` (new — COOP/COEP static server on
  HttpListener; per-request fault isolation, HEAD support; PowerShell
  because this machine has no Python) + `tools/README.md` (export → serve
  → test pipeline). Build artifacts NOT committed (`/export/` ignored).
- Evidence (2026-07-15, Chrome on localhost:8060):
  - CLI export: `--headless --export-release "Web"` exit 0 → index.html,
    38.8 MB wasm, 1.5 MB pck.
  - Headers verified on GET and HEAD: COOP same-origin + COEP require-corp.
  - Startup: page title Slime-Verstecken, the DRESSED Map 1 renders with
    the lobby UI + round HUD (screenshots taken).
  - Browser-WebRTC HOSTING WORKS (stretch goal): local signaling server →
    room code EC6E6K issued, slime capsule spawned, third-person camera on.
  - Controls: W moved the slime (visual delta across screenshots); Esc
    freed the mouse; "Runde starten" ran a solo round — HUD flipped to
    "Vorbereitung 1:00 / Verstecker / Gefressen: 0" with the unlock line,
    and a live "[E] Fressen" prompt proved NPC spawning on the web build.
  - Console: no app errors. One benign "pointer lock" exception under
    automated input (watch item for the itch embed). No failing network
    requests observed after tracking started; full asset load evidenced by
    the running game.
  - First Host attempt timed out client-side while the tab was throttled
    by Chrome (background-tab rAF stall) — retried focused, worked. Real
    players keep the tab focused; noted as playtest-instructions material.
- Two-tab WebRTC join was NOT completed (single automated session drove
  one tab; joining needs a second focused tab — Chrome throttles the
  unfocused one). Honest status: hosting proven from the browser, browser
  ↔ browser join remains on the manual two-machine checklist (it always
  was — README rule).
- Manual (Travis): performance judgment, second real browser/machine.

### 15 · feature/itch-playtest-build — ✅* (honest attempt; upload blocked externally)

- Changed: `tools/push_playtest.md` (new — the binding upload procedure:
  fresh export → anonymous visibility pre-check → versioned butler push →
  status verify → in-page browser check; plus the attempt log).
- Evidence (2026-07-15):
  - Fresh export exit 0.
  - Anonymous fetch of https://ttravis17.itch.io/slime-verstecken-playtest
    → HTTP 404: the page is draft/hidden ✓ (upload would stay private).
  - `butler push --help` inspected: NO visibility flag exists — the
    goal's "create it hidden" is carried by the page's draft state, which
    only the itch dashboard can change. Recorded.
  - `butler push export/web …:web-playtest --userversion 20260715-cf76dba`
    → **REFUSED by itch.io API (400): "Please verify your account's email
    address before uploading a build."** This is an account-state gate
    only Travis can clear (verification link in his inbox). Butler auth
    itself is fine (the same credentials read the project). No retry
    spamming; no workaround attempted (none is legitimate).
- Morning action (Travis): verify the itch account email, then rerun the
  four commands in tools/push_playtest.md — everything up to the API gate
  is proven working. Then set the page's browser-embed options.

### 16 · planning/playtest-protocol — ✅  (PHASE 8 COMPLETE — implementation)

- `planning/PLAYTEST_PROTOCOL.md` (new, German for the community): 3-wave
  Discord rollout (4-6 → ~20 → ~100), per-session metrics (join success,
  disconnects, FPS feel + one real measurement, elimination causes split
  rotation/paintball/clone, eats, Grundieren usage), a 10-question survey,
  and the three decision gates: Kenney-vs-Synty (SPEC.md 14), cooldown
  tuning (SPEC.md 11), clone cut (SPEC.md 10). Closes the SPEC.md 16 open
  point. Also lists the real preconditions: itch email verification,
  public signaling host + WSS before wave B, browser↔browser join check.
- Docs only — suite unaffected.
- Manual (Travis+Maxim): adopt/adjust, schedule wave A.

### 17 · feature/clones — ✅

- Changed: `scripts/clones/clone.gd` + `scenes/clone.tscn` (new — static
  copy: prop scene by form id, registry collision, paint replayed from the
  owner's compacted event snapshot), `scripts/clones/clone_manager.gd`
  (new — host-validated placement: sender identity, round active, alive
  hider, real prop form, budget from the eat table, claimed position vs
  the host's copy; destroy_clone for 9.2/9.3; round-reset clear; paint
  snapshot rides IN the spawn data so the spawner's late-join replay
  carries the identical image for free), `scripts/paint/paint_sync.gd`
  (history_snapshot), `scripts/player_capsule.gd` (place_clone + KEY_C),
  round HUD ("Klone: n/m [C]"), `scenes/main.tscn` (Clones/CloneSpawner/
  CloneManager), `tests/clones_test.gd` (new).
- Tests (2026-07-15): new test PASS 19/19 (red first: manager missing) —
  pixel-accurate paint on both peers AND on a late joiner, static after
  owner repaints, budget 2-at-2-eaten with the third rejected, no decay,
  reset clear. FULL suite: 21 files, 561 checks, boot, diff — green.
- Manual (Travis): clone indistinguishability from a player prop,
  placement feel, two-machine.

### 18 · feature/clone-death-link — ✅

- Changed: `scripts/seeker/paintball.gd` (clone impact branch — destroy
  the clone via the manager's single despawn path; an ALIVE owner dies
  through the Phase 5 entry with reason "clone" and the shot counts as a
  HIT (no cooldown — it downed a player); a dead owner's leftover clone is
  debris: despawn + MISS with splatter), `tests/clone_death_link_test.gd`
  (new). The Todes-Link stays exactly as spec'd — SPEC.md 10 calls it a
  deliberate, twice-confirmed decision; no softening.
- Tests (2026-07-15): new test PASS 15/15 (red first: 5 link behaviors
  missing). FULL suite: 22 files, 576 checks, boot, diff — green.
- Manual (Travis): fairness FEEL of the death link (playtest-watch item
  per the protocol's clone gate).

### 19 · feature/clone-swap-teleport — ✅  (PHASE 9 + CHAIN COMPLETE — implementation)

- Changed: `scripts/clones/clone_manager.gd` (request_swap host path:
  sender identity, active round, alive hider; consumes the MOST RECENTLY
  placed clone — recorded V1 target selection — through the single
  despawn path, then sends the owner its landing spot; only the owner's
  machine moves the capsule), `scripts/player_capsule.gd` (request_swap +
  swap_teleport_to: land, zero velocity, and RotationTracker.reset_timer()
  IMMEDIATELY — SPEC.md 10 defines the jump as a room change, no 5 s
  dwell; KEY_T), `tests/clone_swap_test.gd` (new).
- Tests (2026-07-15): new test PASS 13/13 ×3 consecutive (red first:
  request_swap missing; one test fix — the no-op check now compares
  horizontal drift, a settling capsule sinks). CHAIN EXIT SUITE on this
  final branch: 23 test files / 589 checks, headless import 0 errors,
  boot exit 0, `git diff --check` clean — ALL GREEN.
- Manual (Travis): escape-anchor feel, two-machine, and the protocol's
  clone-cut gate (clones stay the first cut candidate — SPEC.md 10).

## Risks / open items (running list)

- Native WebRTC on macOS still untested (missing macOS webrtc_native
  framework) — pre-existing platform gap, unchanged by this chain.
- itch page visibility can only be verified, never changed, by automation;
  browser-embed settings on the page are manual (Travis).

## Manual validation checklist for Travis (grows per branch)

- [ ] Phase 5: full round on two real machines (phases, feeding, unlocks,
      rotation drip, win/reset).
- [ ] Phase 6: seeker duel on two machines (hit reg, splatter look,
      cooldown feel, spectating + dead chat).
- [ ] Phase 7: house walkthrough (scale, doorways, prop plausibility,
      dressed look).
- [ ] Phase 8: browser build on a second real browser/machine; itch page
      embed settings; decide when/how testers get the hidden link.
- [ ] Phase 9: clone rounds on two machines (paint fidelity, death link
      fairness, swap escapes).
- [ ] Only after the above: mark phases Done in BUILD_PLAN.md (via PR).
