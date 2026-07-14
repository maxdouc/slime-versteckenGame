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
| 1 | feature/round-phases | 0 | ✅ | (head of branch) | 42/42 new + full regression |
| 2 | feature/npc-slimes-feeding | 1 | ⏳ | — | — |
| 3 | feature/eat-progression-table | 2 | ⏳ | — | — |
| 4 | feature/rotation-timer | 3 | ⏳ | — | — |
| 5 | feature/win-lose-reset | 4 | ⏳ | — | — |
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
