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
| 5 | feature/win-lose-reset | 4 | ✅ | (head of branch) | 26/26 new + FULL suite (12 files, 437 checks) |
| 6 | feature/paintball-gun | 5 | ⏳ | — | — |
| 7 | feature/seeker-splatter | 6 | ⏳ | — | — |
| 8 | feature/seeker-cooldown | 7 | ⏳ | — | — |
| 9 | feature/spectator-mode | 8 | ⏳ | — | — |
| 10 | feature/map1-house-graybox | 9 | ⏳ | — | — |
| 11 | feature/map1-npc-spawn-markers | 10 | ⏳ | — | — |
| 12 | feature/map1-prop-slots | 11 | ⏳ | — | — |
| 13 | feature/map1-kenney-dressing | 12 | ⏳ | — | — |
| 14 | feature/web-export-smoke-test | 13 | ⏳ | — | — |
| 15 | feature/itch-playtest-build | 14 | ⏳ | — | — |
| 16 | planning/playtest-protocol | 15 | ⏳ | — | — |
| 17 | feature/clones | 16 | ⏳ | — | — |
| 18 | feature/clone-death-link | 17 | ⏳ | — | — |
| 19 | feature/clone-swap-teleport | 18 | ⏳ | — | — |

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
