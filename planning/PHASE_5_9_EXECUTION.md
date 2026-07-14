# Phase 5–9 Execution Plan — Slime-Verstecken

> **For agentic workers:** execute inline, branch by branch, in the exact chain
> below (superpowers:executing-plans style — one branch, its tests, commit,
> push, then the next). Steps use checkbox syntax in PHASE_5_9_STATUS.md.

**Goal:** Implement every implementable branch of BUILD_PLAN.md Phases 5–9 as
one sequential stacked branch chain, pushed to origin, with practical automated
tests — leaving only genuinely manual validation (two-machine tests, subjective
playtesting, gameplay approval) for the team.

**Architecture:** Everything rides on the Phase 1–4 foundation: Godot 4.7
high-level multiplayer (`@rpc`, `MultiplayerSynchronizer`, `MultiplayerSpawner`)
behind the untouched `Net` transport seam. `GameState` (autoload) becomes the
host-authoritative round spine; per-feature logic lives in small preloaded
scripts under `scripts/round/`, `scripts/seeker/`, `scripts/clones/`.

**Tech stack:** Godot 4.7 (GL Compatibility), GDScript, headless SceneTree test
scripts, Kenney CC0 assets (Furniture Kit + Building Kit), butler → itch.io.

**Owner: Travis** — every branch in this plan. (BUILD_PLAN.md listed Phases 5–9
owners as TBD; the team decision assigning them to Travis is recorded here.)
Maxim reviews via PRs after the fact. **Nothing in this chain is merged to main
by agents. No PRs are opened by agents.**

---

## Global constraints (verbatim project rules — apply to every branch)

- Web-first; Steam = V2; **no GodotSteam** (SPEC overrides 1–2).
- Gameplay uses Godot high-level multiplayer only; **never touches the
  transport**; `net/net.gd` + `net/webrtc_signaling.gd` stay byte-identical.
- Brush strokes / paint actions sync **as events, never textures** (SPEC 9.3).
  This extends to seeker splatter and clone paint.
- **`project.godot` is not edited by feature branches.** Input actions are
  registered at runtime in `player_capsule.gd::_ensure_input_actions()`
  (existing convention). No new autoloads — `GameState` is the round spine.
- **No `class_name`** in gameplay scripts — preload by path (repo convention;
  headless `--script` runs can't rely on the editor's global class cache).
- Speed tiers verbatim (SPEC 9.2): slime 100 %, small 80 %, medium 60 %,
  large 40 %. Eat table verbatim (SPEC 8): 0 eaten → large, 1+ → +medium,
  2+ → +small, 3 = cap; clones 0/1/2/3.
- Defaults verbatim (SPEC 4): Prep 60 s · Hunt 4 min · Rotation 60 s ·
  Paintball-Cooldown 4 s · NPCs = 2× hider count. All host-adjustable
  variables, so tests may shrink them.
- Player-facing strings in German (existing convention: Grundieren,
  Alles-Löschen): Vorbereitung / Jagd / Fressen / Sucher / Verstecker.
- Never commit: `export/`, `.godot/`, `*.import`, `LOCAL_OPERATOR.md`,
  Kenney ZIPs, unused pack contents, credentials.
- Each branch: only its own files + `planning/PHASE_5_9_STATUS.md`.
- Commit style: existing repo style (`feat: …`, `chore: …`, imperative).

## Branch chain (exact, sequential — each branch forks from the previous)

```
main
└── planning/phase-5-9-execution          (this plan + status file)
    └── feature/round-phases              Phase 5
        └── feature/npc-slimes-feeding
            └── feature/eat-progression-table
                └── feature/rotation-timer
                    └── feature/win-lose-reset
                        └── feature/paintball-gun          Phase 6
                            └── feature/seeker-splatter
                                └── feature/seeker-cooldown
                                    └── feature/spectator-mode
                                        └── feature/map1-house-graybox     Phase 7
                                            └── feature/map1-npc-spawn-markers
                                                └── feature/map1-prop-slots
                                                    └── feature/map1-kenney-dressing
                                                        └── feature/web-export-smoke-test   Phase 8
                                                            └── feature/itch-playtest-build
                                                                └── planning/playtest-protocol
                                                                    └── feature/clones                Phase 9
                                                                        └── feature/clone-death-link
                                                                            └── feature/clone-swap-teleport
```

Rationale for stacking: every branch depends on its predecessor's systems
(BUILD_PLAN's own order), the team works sequentially per the parallel-work
rules, and central files (`scripts/game_state.gd`, `scenes/main.tscn`,
`scripts/player_capsule.gd`) are touched by many branches — stacking is the
only structure that avoids conflicts entirely.

## Overlap resolution (binding)

- **feature/win-lose-reset owns**: elimination behavior, victory/defeat
  conditions, round end, and the full round reset.
- **feature/spectator-mode owns**: the free spectator camera (and the
  dead-only text chat of SPEC 5.3).
- feature/rotation-timer (built before win-lose-reset) therefore only adds the
  elimination **data layer**: `GameState.request_elimination()` host RPC that
  flips `alive=false` in the registry and emits `player_eliminated`. The
  elimination **behavior** (ghosting the capsule, win checks, END, reset)
  arrives with win-lose-reset. Until spectator-mode lands, eliminated players
  are "ghosts": invisible, non-colliding, input-frozen, keeping their camera.

## Test + verification protocol (every branch)

1. New headless test: `tests/<topic>_test.gd` (SceneTree script, prints
   PASS/FAIL per assertion, `quit(0/1)`). Multi-peer tests use the in-process
   ENet pattern from `tests/network_transform_test.gd` (one
   `MultiplayerAPI.create_default_interface()` per "machine", port **8911**,
   worlds offset 50 m on X, teardown: free worlds → unregister APIs → close
   peers).
2. Run, from repo root, with
   `GODOT="C:/Users/tthoe/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"`:
   - `$GODOT --headless --script tests/<new>_test.gd` → exit 0
   - regression: every other `tests/*_test.gd` → exit 0
   - boot: `$GODOT --headless --quit --path .` → exit 0, prints `Boot OK`
   - `git diff --check` → clean (no whitespace errors)
3. Commit + push (`git push -u origin <branch>`) only when all of the above
   pass and `git status` shows only intended files.
4. Record in `planning/PHASE_5_9_STATUS.md`: branch, parent, SHA, changed
   files, test evidence (exact commands + exit codes), risks, remaining
   manual checks.
5. After each phase: run the **entire accumulated suite** again.

Known tooling quirks (documented in memory + addons/webrtc_native/VERSION.md):
the first import run after webrtc_native re-registration may crash at process
teardown (0xC0000005) once — rerun; work completes fine. `--check-only`
cannot resolve autoloads — use full headless boot or `--script` runs instead.

## What stays manual (never claimed by automation)

- Two-real-machine / two-real-browser network tests (README process rule).
- Subjective gameplay/balance judgment, "feels good" checks.
- Kenney-vs-Synty decision (SPEC 14 gate, after playtest).
- itch page visibility flips, publishing, pricing — **never** performed by
  agents (LOCAL_OPERATOR policy).
- Marking BUILD_PLAN.md phases *Done* — only after Travis' manual validation.

## External-resource rules (binding)

- **Kenney assets**: source only from `C:\Projects\Prophunt_External\Kenney`
  (`FurnitureKit/`, `BuildingKit/` — the packs approved in LOCAL_OPERATOR.md).
  Copy **only** models actually placed in Map 1, **GLB preferred**, plus each
  pack's license/readme, into `assets/kenney/<pack>/`. No ZIPs, no unused
  contents, no other packs.
- **Web export**: preset "Web" in `export_presets.cfg` as-is (GL
  Compatibility, `extensions_support=false`, `thread_support=true`,
  `export/web/index.html`). Builds are never committed (`/export/` ignored).
- **Butler / itch.io**: target `ttravis17/slime-verstecken-playtest:web-playtest`
  (from LOCAL_OPERATOR.md), butler at `C:\Tools\butler\butler.exe`
  (authenticated — verified 2026-07-14, channel does not exist yet → first
  push creates it). Before any push: confirm the project page is NOT publicly
  reachable (anonymous fetch of https://ttravis17.itch.io/slime-verstecken-playtest
  must not return a public page). If it is public: **do not upload**, report.
  Never unhide, publish, change pricing, or print/expose credentials.
- **Chrome**: used for localhost + hidden-build smoke tests (startup, basic
  controls, console errors, network failures). Login prompts/CAPTCHAs are
  reported for Travis, never bypassed.

---

# Phase 5 — Round loop

## Branch 5.1: feature/round-phases  (parent: planning/phase-5-9-execution)

**Scope (SPEC 4, 5.1–5.3 skeleton):** host-authoritative phase machine
LOBBY → PREP → HUNT → END → LOBBY, synced to all peers incl. late joiners;
role assignment (Sucher/Verstecker); seekers held blind in a sealed spawn box
during PREP; round HUD; host Start-Round control.

**Files:**
- Modify `scripts/game_state.gd` — the spine:
  - `enum Role { NONE, HIDER, SEEKER }`
  - `players: Dictionary` registry `peer_id -> {"role": Role, "alive": bool,
    "eaten": int}` (eaten used from 5.2 on)
  - Host-only `_process` ticking; phase transitions broadcast via
    `@rpc("authority", "call_local", "reliable") _sync_phase(phase, duration,
    registry)`; late joiners get a snapshot on `peer_connected` (host pushes
    `_sync_phase` + settings via `rpc_id`).
  - `start_round()` (host): assigns roles — seekers: 2 if player count ≥ 7
    else 1, clamped to player_count − 1 (so a solo dev round = 1 hider,
    0 seekers); everyone alive; eaten 0 → PREP.
  - END auto-returns to LOBBY after `end_seconds` (new var, default 10.0)
    — full reset behavior arrives in 5.5; here END→LOBBY only flips phase.
  - Helpers: `role_of(id)`, `is_seeker(id)`, `is_alive(id)`, `alive_hiders()`,
    `is_round_active()`. Signals: `roles_assigned`, `registry_changed`.
  - Mid-round joiners: registry entry `{role: NONE, alive: false}` —
    spectate-until-next-round policy (decision recorded here).
- Modify `scenes/gray_room.tscn` — add sealed `SeekerSpawnRoom` box (walls,
  floor, `SeekerSpawnPoint` Marker3D) at x = +20 (outside the 12×12 room).
- Create `scripts/round/round_hud.gd` + `scenes/round_hud.tscn` — phase name
  (German), countdown, own role, Start-Round button (host + LOBBY only,
  talks to `GameState.start_round()`).
- Modify `scenes/main.tscn` — instance RoundHud under `CanvasLayer`.
- Modify `scripts/player_capsule.gd` — during PREP, seekers are teleported to
  `SeekerSpawnPoint` and hiders to the normal spawn (host applies positions at
  role assignment via existing authority model: each owner repositions itself
  on `roles_assigned`); at HUNT start seekers teleport to the map spawn.
- Test `tests/round_phases_test.gd`.

**Interfaces produced (consumed by every later branch):**
`GameState.start_round()`, `GameState.players`, `GameState.Role`,
`role_of(id) -> Role`, `is_seeker(id) -> bool`, `is_alive(id) -> bool`,
`is_round_active() -> bool`, signals `roles_assigned`, `registry_changed`,
`phase_changed(Phase)`.

**Automated test:** 2 in-process peers; host `start_round()` with shrunk
timers (`prep_seconds = 0.4`, `hunt_seconds = 0.6`, `end_seconds = 0.3`):
- both peers reach PREP, exactly 1 seeker + 1 hider assigned identically;
- PREP expiry → HUNT on both; HUNT expiry → END on both; END → LOBBY;
- late joiner (3rd peer connected mid-HUNT) receives current phase + registry
  with itself as `{NONE, alive=false}`.

**Acceptance criteria:** all of the above assertions pass; boot + regression
suite + `git diff --check` clean; `net/` untouched.

**Manual (Travis):** two-machine phase flow; HUD readability; seeker box truly
blind from inside.

## Branch 5.2: feature/npc-slimes-feeding  (parent: feature/round-phases)

**Scope (SPEC 5.1, 5.2, 7):** sleeping NPC slimes spawn from hand-placed
markers at PREP start (host picks `npcs_per_hider × hiders`, capped by marker
count, random without repeat); E-hold-1s feeding, hiders only, PREP only,
proximity-gated, host-validated; slurp shrink during hold; unfed NPCs vanish
at HUNT start with a poof particle; eaten count per player in the registry.

**Files:**
- Create `scenes/npc_slime.tscn` + `scripts/npc_slime.gd` — slime model
  reuse (sphere + eyes) at 0.6× scale, eyes closed (flattened dark ovals),
  `StaticBody3D` + interaction radius, `npc_id` from spawner data.
- Create `scripts/round/npc_manager.gd` (Node in main.tscn) + a
  `MultiplayerSpawner` (`NpcSpawner`, spawn_path `../Npcs`): host spawns at
  PREP, despawns on eat / at HUNT start (broadcasting a poof-event RPC so
  every peer plays `CPUParticles3D` one-shots locally).
- Modify `scenes/gray_room.tscn` — 6 `Marker3D` in group `npc_spawn`.
- Modify `scenes/main.tscn` — `Npcs` Node3D + `NpcSpawner` + `NpcManager`.
- Modify `scripts/game_state.gd` — `npcs_per_hider: float = 2.0` (host
  setting), `eaten_of(id)`, `record_eaten(id)` (host), signal
  `npc_eaten(peer_id, count)`.
- Modify `scripts/player_capsule.gd` — "fressen" action (KEY_E, runtime-
  registered), hold tracking (1.0 s), nearest-NPC prompt ("[E] Fressen —
  halten"), progress on HUD, `request_eat(npc_id)` RPC → host validates:
  PREP + hider + alive + NPC exists + distance ≤ 2.5 m → despawn + count.
- Modify `scripts/round/round_hud.gd` — prompt + hold progress + eaten count.
- Test `tests/npc_feeding_test.gd`.

**Interfaces produced:** `GameState.eaten_of(id) -> int`, `npc_eaten` signal,
`npc_manager.living_npc_count()`, marker group name `npc_spawn`.

**Automated test:** 2 peers, 1 hider: PREP spawns `2 × 1 = 2` NPCs on both
peers; hider eats one (validated path, distance mocked by teleporting next to
it) → `eaten_of == 1` everywhere, NPC gone everywhere; eating in HUNT
rejected; at HUNT start remaining NPCs are gone on both peers.

**Acceptance criteria:** assertions pass; seekers/mid-round joiners cannot
eat; suite + boot + diff clean.

**Manual (Travis):** prompt feel, slurp readability, poof visibility,
two-machine sync of eat + vanish.

## Branch 5.3: feature/eat-progression-table  (parent: feature/npc-slimes-feeding)

**Scope (SPEC 8):** the inverted eat table as the single unlock authority —
0 eaten → large only; 1+ → +medium; 2+ → +small; cap 3; clone budget
0/1/2/3 (consumed by Phase 9). Enforced for hiders while a round is active;
LOBBY stays a free sandbox (dev/testing decision, recorded here).

**Files:**
- Create `scripts/round/progression.gd` — static, pure:
  `unlocked_sizes(eaten) -> Array[PlayerForms.Size]`,
  `is_size_unlocked(eaten, size) -> bool`, `clones_allowed(eaten) -> int`
  (= `clampi(eaten, 0, 3)`), `EAT_CAP := 3`.
- Modify `scripts/game_state.gd` — cap `record_eaten` at `EAT_CAP`.
- Modify `scripts/player_capsule.gd` — `transform_to_prop()` gate: while
  `GameState.is_round_active()` and self is HIDER, reject locked sizes (HUD
  feedback "Noch nicht freigeschaltet — friss NPC-Slimes!"); seekers may
  never transform while a round is active.
- Modify `scripts/round/round_hud.gd` — unlocked-forms line
  (e.g. "Formen: Groß ✓ · Mittel ✗ (1) · Klein ✗ (2)").
- Test `tests/progression_test.gd`.

**Interfaces produced:** `Progression.is_size_unlocked`,
`Progression.clones_allowed` (Phase 9 consumes this exact name).

**Automated test:** pure-table assertions (all 4 eaten levels × 4 sizes +
clone counts) and 2-peer: hider at 0 eaten blocked from medium in PREP;
after 1 eat medium works; large always works; in LOBBY everything works;
seeker transform rejected mid-round.

**Acceptance criteria:** table matches SPEC 8 verbatim; suite green.

**Manual (Travis):** HUD clarity; feel of the unlock loop on two machines.

## Branch 5.4: feature/rotation-timer  (parent: feature/eat-progression-table)

**Scope (SPEC 6):** per-hider 60 s room-rotation timer, HUNT only. Room
presence via Area3D volumes; a room change counts only after 5 s continuous
stay in the new room (no door-sill pendling — the old timer keeps running
during those 5 s); expiry → loss of cohesion: growing puddle under the
player (replicated), 10 s grace, then elimination request (data layer only —
see overlap resolution).

**Files:**
- Create `scripts/round/room_volume.gd` — Area3D script, `@export room_id:
  String`; group `room_volume`.
- Modify `scenes/gray_room.tscn` — two RoomVolumes ("test_west", "test_east")
  splitting the 12×12 floor, so the mechanic is fully testable pre-Map-1.
- Create `scripts/round/rotation_tracker.gd` — Node child of the capsule
  (authority-driven): tracks own overlaps, dwell confirmation (5 s,
  `GameState.rotation_dwell_seconds`), countdown
  (`GameState.rotation_seconds`), grace (`rotation_grace_seconds = 10.0`),
  drives `rotation_drip` (0..1) on the capsule, calls
  `GameState.request_elimination("rotation")` at grace end. Exposes
  `reset_timer()` (clone swap-teleport consumes this in Phase 9).
- Modify `scenes/player_capsule.tscn` — add `RotationTracker` node; add
  `rotation_drip` to the replication config (on-change); add `DripPuddle`
  MeshInstance3D (flat cylinder, dark tint, scale 0 = hidden).
- Modify `scripts/player_capsule.gd` — `rotation_drip: float` (setter drives
  puddle scale on every peer), timer HUD hookup.
- Modify `scripts/game_state.gd` — `rotation_dwell_seconds := 5.0`,
  `rotation_grace_seconds := 10.0`;
  `request_elimination(reason)` any_peer→host RPC: validates the sender is an
  alive hider in HUNT, flips `alive=false`, broadcasts registry, emits
  `player_eliminated(id, reason)`. (Behavior in 5.5.)
- Modify `scripts/round/round_hud.gd` — rotation countdown + room + warning.
- Test `tests/rotation_timer_test.gd`.

**Interfaces produced:** `GameState.request_elimination(reason)`,
`player_eliminated(id, reason)` signal, `RotationTracker.reset_timer()`,
room volume convention (`room_volume` group + `room_id`).

**Automated test:** shrunk timers (`rotation_seconds = 0.6`, dwell 0.2,
grace 0.3): hider idles in room A → drip rises → eliminated flag on both
peers with reason "rotation"; fresh round: hider crosses to room B, stays
past dwell → timer resets (no elimination after old deadline); A→B→A bounce
inside dwell → no reset; timer inactive during PREP; seekers unaffected.

**Acceptance criteria:** SPEC 6 semantics exactly (timer from room entry,
5 s confirmation, 10 s grace); drip visible cross-peer; suite green.

**Manual (Travis):** drip readability at distance; two-machine drip sync;
timing feel.

## Branch 5.5: feature/win-lose-reset  (parent: feature/rotation-timer)

**Scope (SPEC 5.3 — owns elimination/victory/round-end/reset):** real
elimination behavior (ghosting until Phase 6 spectator), win conditions —
seekers win when all hiders are eliminated before hunt end; every surviving
hider wins individually (no score); END screen; complete per-round reset
(forms, paint, eaten, registry, NPCs, projectiles/splatter later) back to
LOBBY.

**Files:**
- Modify `scripts/game_state.gd` — on `player_eliminated`: win check (host);
  hunt-expiry → hider win END; `end_result` payload broadcast with
  `_sync_phase` (winner side + survivor list); `reset_round()` (host, at
  END→LOBBY): registry wiped to `{NONE, alive:true-ish idle}`, eaten 0,
  emits `round_reset` (systems clean themselves: NPCs already, splatter/
  clones subscribe later).
- Modify `scripts/player_capsule.gd` — react to own elimination: exit
  paint/transform state → ghost (all visuals hidden incl. puddle, collision
  layer 0, physics off for movement input, camera kept); on `round_reset`:
  un-ghost, back to slime, teleport to spawn ring, `rotation_drip = 0`.
- Modify `scripts/round/round_hud.gd` — END screen overlay: "Sucher
  gewinnen!" / "Überlebende Verstecker: …" + own outcome; "Du bist raus"
  banner while ghosted.
- Test `tests/win_lose_reset_test.gd`.

**Interfaces produced:** `round_reset` signal (Phase 6 splatter + Phase 9
clones subscribe), `GameState.end_result`, ghost contract on the capsule.

**Automated test:** 2 peers (1 seeker, 1 hider):
(a) eliminate the hider mid-HUNT → END on both, seeker-win result;
(b) new round, hider survives hunt expiry → hider-win result with survivor
list; (c) after END, LOBBY on both with full reset (alive flags, eaten 0,
forms slime, drip 0, ghost off).

**Acceptance criteria:** SPEC 5.3 verbatim incl. individual hider wins and
complete per-round reset ("Keine persistenten Freischaltungen"); suite green.

**Manual (Travis):** END screen readability, reset feel, two-machine round.

**Phase 5 exit:** full accumulated suite green; phase flow + feeding +
progression + rotation + win/reset all demonstrably synced in tests.

---

# Phase 6 — Seeker kit

## Branch 6.1: feature/paintball-gun  (parent: feature/win-lose-reset)

**Scope (SPEC 11):** the one seeker weapon. Visible projectile, host-
authoritative flight + hit detection, direct hit on an alive hider =
immediate elimination (reason "paintball"). Seekers aim third-person with a
crosshair; fire = LMB (`fire` action). Fire requests are host-validated
(seeker, HUNT, alive). One projectile in flight per seeker (recorded
implementation decision — prevents pre-cooldown spam and reads better).

**Files:**
- Create `scenes/paintball.tscn` + `scripts/seeker/paintball.gd` —
  Area3D-based projectile (bright magenta sphere, ~35 m/s, light gravity,
  3 s lifetime), host moves it, `MultiplayerSynchronizer` syncs position;
  host resolves first overlap: player capsule → eliminate (if alive hider);
  world → despawn (splatter event in 6.2); reports result to
  `seeker_combat.gd`.
- Create `scripts/seeker/seeker_combat.gd` (Node in main.tscn) +
  `ProjectileSpawner` MultiplayerSpawner (spawn_path `../Projectiles`):
  `request_fire(origin, dir)` any_peer→host RPC, validation, spawn;
  tracks in-flight per seeker; signals `shot_missed(seeker_id)` /
  `shot_hit(seeker_id)` (6.3 consumes).
- Modify `scenes/main.tscn` — `Projectiles` node + spawner + `SeekerCombat`.
- Modify `scripts/player_capsule.gd` — `fire` action (LMB) when seeker in
  HUNT: ray from camera center → `request_fire`; crosshair visibility.
- Modify `scripts/round/round_hud.gd` — crosshair for seekers (HUNT).
- Test `tests/paintball_test.gd`.

**Interfaces produced:** `SeekerCombat.request_fire`, `shot_missed(id)` /
`shot_hit(id)` signals, elimination reason "paintball".

**Automated test:** 2 peers (seeker + hider) in HUNT: host-side fire at the
hider's position → projectile spawns on both peers, hider eliminated
(reason "paintball") on both; fire during PREP rejected; hider's fire
request rejected; second fire while one is in flight rejected.

**Acceptance criteria:** direct hit = sofortige Elimination; all gating
host-side; suite green.

**Manual (Travis):** aim feel, projectile visibility/speed, two-machine hit
registration.

## Branch 6.2: feature/seeker-splatter  (parent: feature/paintball-gun)

**Scope (SPEC 11):** missed shots leave permanent paint splatter on the map
— the seeker himself changes the camouflage surfaces. Splatter syncs as
events (never textures). If a miss lands next to a transformed alive hider,
the spray also marks that hider's prop — routed through the owner's own
PaintSync stroke events so late joiners replay it correctly.

**Files:**
- Create `scripts/seeker/splatter_manager.gd` (Node in main.tscn): host
  broadcasts `_spawn_splatter(pos, normal, seed)` (`call_local` reliable);
  every peer deterministically spawns a flat splatter disc (2–4 blob
  meshes from `seed`, magenta family) under `Splatters`; bounded history
  (512) for late joiners (host pushes on peer_connected); clears on
  `round_reset`.
- Create `scenes/splatter.tscn` — the disc/blob visual (no collision).
- Modify `scripts/seeker/paintball.gd` — world hit → host calls
  splatter_manager.
- Modify `scripts/paint/paint_sync.gd` — add
  `apply_external_spray(world_pos, color, seed)` (authority-side only):
  maps nearby surface points to own-prop UVs and emits N normal
  `local_stroke` events (deterministic offsets from seed).
- Modify `scripts/player_capsule.gd` — on splatter event within 1.5 m while
  transformed + alive + authority: call `apply_external_spray`.
- Modify `scenes/main.tscn` — `Splatters` node + `SplatterManager`.
- Test `tests/splatter_test.gd`.

**Interfaces produced:** `SplatterManager.splatter_count()`, splatter clear
on `round_reset`.

**Automated test:** 2 peers: miss into the floor → identical splatter node
transforms on both peers; late-joining 3rd peer receives existing
splatters; miss adjacent to a transformed hider → that hider's paint image
is non-white at matching pixels on both peers; `round_reset` clears all
splatters everywhere.

**Acceptance criteria:** events only (no texture ever crosses the wire —
code-inspectable + test asserts history entries are int64 events); suite
green.

**Manual (Travis):** splatter look/size, readability as camouflage damage.

## Branch 6.3: feature/seeker-cooldown  (parent: feature/seeker-splatter)

**Scope (SPEC 11):** miss penalty = cooldown only, default 4 s
(`GameState.paintball_cooldown`, host-adjustable). Spec-literal: the
cooldown starts when a shot is confirmed a MISS (world hit / lifetime end);
a HIT ends the in-flight lock with no cooldown. Host-enforced; HUD shows
the lockout for the seeker.

**Files:**
- Modify `scripts/seeker/seeker_combat.gd` — per-seeker cooldown ledger
  keyed on `shot_missed`; `request_fire` rejects while cooling;
  `cooldown_started(seconds)` rpc_id to the seeker for HUD.
- Modify `scripts/round/round_hud.gd` — cooldown bar/countdown ("Nachladen…").
- Test `tests/cooldown_test.gd`.

**Interfaces produced:** cooldown state queryable
(`SeekerCombat.cooldown_left(id)`).

**Automated test:** shrunk cooldown (0.4 s): miss → immediate re-fire
rejected → after 0.5 s accepted; hit → immediate re-fire accepted (no
cooldown on hit); cooldown value comes from GameState var.

**Acceptance criteria:** SPEC-literal miss-only cooldown; host-side
enforcement; suite green.

**Manual (Travis):** whether hit-no-cooldown feels right (flagged for
playtest tuning per SPEC 11's Rechenbasis note).

## Branch 6.4: feature/spectator-mode  (parent: feature/seeker-cooldown)

**Scope (SPEC 5.3 — owns the free camera + dead-only text chat):**
eliminated players get a free-fly spectator camera (WASD + mouse, rise/sink,
speed modifier) replacing the ghost's stuck camera, and a text chat visible
to and readable only by eliminated players (host relays; no voice in V1).

**Files:**
- Create `scripts/round/spectator_camera.gd` + `scenes/spectator_camera.tscn`
  — local-only free-fly rig; spawned by the capsule on own elimination,
  freed on `round_reset`.
- Create `scripts/round/dead_chat.gd` — host-relay chat:
  `send(text)` → host filters sender is dead → `rpc_id` to every dead peer;
  part of round HUD (LineEdit + log, visible only while dead).
- Modify `scripts/player_capsule.gd` — swap ghost camera → spectator rig.
- Modify `scripts/round/round_hud.gd` — chat UI + "Zuschauer" state.
- Modify `scenes/main.tscn` — `DeadChat` node.
- Test `tests/spectator_test.gd`.

**Automated test:** 3 peers (1 seeker, 2 hiders — so eliminating one hider
does not end the round): the dead hider gets a spectator rig locally (node
exists), alive peers don't; dead chat: the dead hider's message is NOT
delivered to the alive seeker or the alive hider; eliminate the second
hider (END fires) → a message now reaches both dead peers; `round_reset`
removes the rigs and hides the chat.

**Acceptance criteria:** free camera + dead-only chat per SPEC 5.3; alive
players can never read dead chat; suite green.

**Manual (Travis):** camera feel, chat usability, two-machine.

**Phase 6 exit:** accumulated suite green; a full round with seeker
elimination, splatter, cooldown, spectating works in tests end-to-end.

---

# Phase 7 — Map 1: Wohnhaus

## Branch 7.1: feature/map1-house-graybox  (parent: feature/spectator-mode)

**Scope (SPEC 13):** 9-room house graybox (≈1.5 × 6 hiders): Flur (hall),
Wohnzimmer, Küche, Esszimmer, Bad, Schlafzimmer, Kinderzimmer, Büro,
Abstellraum — plus the sealed seeker spawn room. Every room ≥ 2 exits;
flat, repaintable colors per room (checkered/wood/tile *patterns* come with
dressing); RoomVolumes on the Phase-5 convention; player spawn; lighting.
`main.tscn` swaps GrayRoom → Map1House (gray_room.tscn stays for tests).

**Files:**
- Create `maps/map1_house.tscn` (+ `scripts/round/map_info.gd` if metadata
  needed) — box-mesh construction on a grid, doorway gaps ≥ 1.4 m wide,
  per-room `RoomVolume` (ids "flur", "wohnzimmer", …), 6 `Marker3D`
  `PlayerSpawnPoint`-compatible spawn (single marker kept for main.gd
  compatibility), `SeekerSpawnRoom` + `SeekerSpawnPoint`, `npc_spawn`
  markers moved to 7.2 (none here).
- Modify `scenes/main.tscn` + `scripts/main.gd` — instance Map1House; main.gd
  finds spawn markers via groups (`player_spawn`, `seeker_spawn`) instead of
  the hardcoded `$GrayRoom/PlayerSpawnPoint` path; gray_room.tscn gets the
  same group tags so tests keep working.
- Test `tests/map1_graybox_test.gd`.

**Automated test:** load `maps/map1_house.tscn` headless: ≥ 9 room volumes
with unique ids; player + seeker spawn markers present (groups); every
room's volume AABB intersects ≥ 2 doorway markers (doorways carry small
`Marker3D`s in group `doorway` precisely so exits are testable); boot of
main scene OK.

**Acceptance criteria:** structure verified by test; SPEC 13 room rules met
(≥2 exits testably, plausible large-prop space per room comes in 7.3);
suite green (rotation tests still pass on gray_room).

**Manual (Travis):** walkthrough, scale/claustrophobia check, camera
clipping in doorways, two-machine roam.

## Branch 7.2: feature/map1-npc-spawn-markers  (parent: feature/map1-house-graybox)

**Scope (SPEC 7):** ~30 hand-placed NPC spawn markers across the 9 rooms
(none in the seeker room), floor-level, so 12 active NPCs per round leave
every round different.

**Files:** modify `maps/map1_house.tscn` (30+ `Marker3D` in `npc_spawn`,
spread ≥ 3 per room); test `tests/map1_npc_markers_test.gd`.

**Automated test:** ≥ 30 markers in group; every marker inside exactly one
room volume (and none in the seeker room); y within floor tolerance; NPC
manager on this map spawns the expected count without marker reuse.

**Acceptance criteria:** counts + placement invariants pass; suite green.

**Manual (Travis):** placement plausibility (corners, under tables later).

## Branch 7.3: feature/map1-prop-slots  (parent: feature/map1-npc-spawn-markers)

**Scope (SPEC 13):** plausible standing decoy props so hiders blend in:
every room ≥ 1 large slot (all hiders can start large), plus medium/small
scatter. Slots are `Marker3D`s (group `prop_slot`, meta `size`); each slot
gets a static decoy instance (colored duplicates of the placeholder prop
meshes — NOT white, white must stay the "untarnt" signal).

**Files:**
- Create `scripts/props/static_prop.gd` + `scenes/props/static_prop_*.tscn`
  (colored carton/bucket/cup variants as StaticBody3D decor).
- Modify `maps/map1_house.tscn` — slots + instances (~9 large, ~10 medium,
  ~12 small).
- Test `tests/map1_prop_slots_test.gd`.

**Automated test:** every room volume contains ≥ 1 large `prop_slot`; every
slot has a decoy child; decoys are StaticBody3D with collision; no decoy
uses the pure-white player-prop material.

**Acceptance criteria:** SPEC 13 "plausible Standorte für große Objekte in
jedem Raum" testably true; suite green.

**Manual (Travis):** plausibility/readability judgment.

## Branch 7.4: feature/map1-kenney-dressing  (parent: feature/map1-prop-slots)

**Scope (SPEC 13, 14):** first dressing pass with the two approved Kenney
kits: replace decoy primitives with Furniture Kit models, add Building Kit
accents (doors/windows), give floors/walls simple repaintable materials
(checkered/wood tones — flat colors, no photorealism). Copy **only used**
GLBs + license files into `assets/kenney/`. Graybox shell geometry stays
(the Kenney-vs-Synty decision gate comes after the playtest — this is
deliberately a furniture-level pass, recorded here).

**Files:** create `assets/kenney/furniture_kit/**` (+ license/readme),
`assets/kenney/building_kit/**` (+ license/readme) — GLB preferred; modify
`maps/map1_house.tscn` (decoys → Kenney instances at the same slots,
material dressing); test `tests/map1_dressing_test.gd`.

**Automated test:** every resource referenced by map1 exists in the repo;
license files present next to the assets; no file from the external root is
referenced by absolute path; headless import + boot with zero
missing-resource errors; every prop_slot still filled; committed asset set
⊆ set actually referenced by the scene (no unused copies).

**Acceptance criteria:** map dressed, licenses in place, no ZIPs/unused
files, suite green (incl. import check).

**Manual (Travis):** the look. Kenney-vs-Synty stays open until playtest.

**Phase 7 exit:** accumulated suite green on Map 1; full round loop playable
on the house in tests (round/rotation/NPC tests still target gray_room —
plus map-targeted spawn checks).

---

# Phase 8 — Web build & playtest prep

## Branch 8.1: feature/web-export-smoke-test  (parent: feature/map1-kenney-dressing)

**Scope (README web rules):** produce the Web build headlessly, serve it
with COOP/COEP locally, and smoke-test in Chrome: boots, renders the lobby,
basic input works, console free of errors, no failing requests. Build
artifacts are never committed.

**Files:** create `tools/serve_web.py` (stdlib-only static server sending
`Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy:
require-corp`) + `tools/README.md` (export + serve + test instructions);
test = the documented procedure itself (evidence in status file):
- `$GODOT --headless --export-release "Web" export/web/index.html` → exit 0,
  export dir populated;
- serve → Chrome `http://localhost:8060`: console shows
  `[Slime-Verstecken] Boot OK`; screenshot; click/keyboard reach the canvas;
  `read_console_messages` no errors; `read_network_requests` no failures.
- WebRTC two-tab host/join via the local signaling server: attempted;
  outcome reported honestly either way (ENet is impossible in browsers).

**Acceptance criteria:** export succeeds from CLI; Chrome smoke evidence
recorded; no committed build artifacts (`git status` clean of export/).

**Manual (Travis):** performance judgment, gamepad-of-choice/input feel,
cross-browser (Firefox/Safari) checks.

## Branch 8.2: feature/itch-playtest-build  (parent: feature/web-export-smoke-test)

**Scope (README hosting rule, LOCAL_OPERATOR policy):** upload the smoke-
tested Web build to `ttravis17/slime-verstecken-playtest:web-playtest` as a
hidden/private test upload. Pipeline documented + repeatable.

**Files:** create `tools/push_playtest.md` (exact butler commands, policy
guardrails, version scheme `<yyyymmdd>-<short-sha>`); status-file evidence.

**Procedure (binding order):**
1. Fresh export (as 8.1).
2. Anonymous visibility check of
   `https://ttravis17.itch.io/slime-verstecken-playtest` — must NOT be a
   publicly reachable page (draft/restricted 404s for anonymous visitors).
   If public: **abort upload**, report to Travis.
3. `butler status <target>` (channel inventory), then
   `butler push export/web <target> --userversion <ver>` — first push
   creates the channel on the hidden page; if butler offers an explicit
   hidden/visibility flag in `push --help`, use it; otherwise hiddenness is
   carried by the page's draft state (verified in step 2) and recorded.
4. `butler status <target>` again → build processed.
5. Chrome check of the build page (Travis' session): login prompt → stop +
   report; reachable → run the same smoke as 8.1 on the itch iframe.
6. Never unhide/publish/change pricing; never print credentials.

**Acceptance criteria:** honest upload attempt completed + evidenced (or
honest abort with reason); channel state recorded; docs committed.

**Manual (Travis):** flip page visibility when HE wants testers in; browser
embed settings on the itch page (viewport 1280×720, SharedArrayBuffer
toggle, fullscreen button) — butler cannot set those.

## Branch 8.3: planning/playtest-protocol  (parent: feature/itch-playtest-build)

**Scope (SPEC 16 open point, BUILD_PLAN Phase 8):** the written playtest
protocol: metrics, survey, Discord rollout, decision gates.

**Files:** create `planning/PLAYTEST_PROTOCOL.md`:
- Metrics: FPS (browser perf HUD instructions), disconnect count, round
  completion rate, elimination causes split (rotation vs paintball vs clone
  death-link), eats per round, Grundieren usage, hunt survival rate, room
  heat (subjective for V1).
- Survey (10 questions max, German): fun, clarity of rotation pressure,
  seeker balance, paint usability, perf, Kenney-vs-Synty look vote, free
  text.
- Rollout: staged 5 → 20 → ~100 over Discord, schedule template, feedback
  channel + form links placeholder, hidden-link distribution rules (page
  stays hidden; link+password or restricted — Travis executes).
- Decision gates: Kenney-vs-Synty (SPEC 14), cooldown tuning (SPEC 11),
  clone cut check (SPEC 10).

**Acceptance criteria:** protocol complete enough to run a playtest without
further design work; no code changes; suite unaffected.

**Manual (Travis+Maxim):** adopt/adjust the protocol; schedule the test.

**Phase 8 exit:** export pipeline + upload pipeline proven and documented;
protocol ready; suite green.

---

# Phase 9 — Clones (built last, cut first)

## Branch 9.1: feature/clones  (parent: planning/playtest-protocol)

**Scope (SPEC 10):** place up to `Progression.clones_allowed(eaten)` (≤ 3)
static clones of the current prop form **including current paint**, at the
player's position/orientation. No auto-decay. Host-authoritative placement;
paint carried as the owner's compacted stroke-event history (events rule —
the placement RPC ships events, every peer replays them onto the clone's
own texture; late joiners get the same events from the host's clone
registry).

**Files:**
- Create `scenes/clone.tscn` + `scripts/clones/clone.gd` — StaticBody3D +
  prop mesh instance + own painter-style texture replay; `owner_id`,
  `clone_id`, `form_id` from spawn data.
- Create `scripts/clones/clone_manager.gd` (Node in main.tscn) +
  `CloneSpawner` MultiplayerSpawner (spawn_path `../Clones`):
  `request_place(form_id, xform, paint_events)` authority-validated on
  host (hider, alive, round active, transformed, budget =
  `Progression.clones_allowed(eaten) - owned_alive_clones`, event list ≤
  1024); host stores per-clone event snapshot for late joiners; despawn on
  `round_reset`.
- Modify `scripts/paint/paint_sync.gd` — `history_snapshot() ->
  PackedInt64Array` (owner-side, current epoch, already compacted).
- Modify `scripts/player_capsule.gd` — `place_clone` action (KEY_C):
  authority collects `form_id` + own transform + `history_snapshot()` →
  `request_place`; HUD clone counter.
- Modify `scenes/main.tscn` — `Clones` node + spawner + manager.
- Modify `scripts/round/round_hud.gd` — "Klone: n/m".
- Test `tests/clones_test.gd`.

**Interfaces produced:** `CloneManager.request_place`,
`clones_of(peer_id) -> Array`, `CloneManager.remove_clone(clone_id)`
(9.2/9.3 consume), spawn-data contract `{owner_id, clone_id, form_id,
xform, paint_events}`.

**Automated test:** 2 peers, hider with 2 eaten (→ 2 clones): paint prop
(fill red + strokes), place clone → exists on both peers, same form, paint
pixels match the owner's image at sampled points; 3rd placement rejected
(budget 2); slime placement rejected; late-joining peer sees the clone with
correct paint; `round_reset` removes clones everywhere.

**Acceptance criteria:** SPEC 10 placement rules + events-only paint carry;
suite green.

**Manual (Travis):** indistinguishability check (clone vs player prop),
two-machine.

## Branch 9.2: feature/clone-death-link  (parent: feature/clones)

**Scope (SPEC 10):** Todes-Link — a destroyed clone kills its owner.
Paintball hit on a clone destroys the clone (poof + splatter) and
eliminates the owner (reason "clone", handled by the win-lose-reset
elimination path; win checks fire normally).

**Files:** modify `scripts/seeker/paintball.gd` (clone hit branch → host:
`CloneManager.destroy_clone(clone_id, by_shot=true)`);
modify `scripts/clones/clone_manager.gd` (destroy → despawn + owner
elimination via `GameState`); test `tests/clone_death_link_test.gd`.

**Automated test:** seeker shoots a clone → clone gone on all peers, owner
eliminated with reason "clone" on all peers, seeker-win END fires when that
was the last hider; shooting a clone of an already-dead owner just removes
the clone.

**Acceptance criteria:** death link exact (SPEC: bewusste Entscheidung,
zweifach bestätigt — no softening); suite green.

**Manual (Travis):** fairness feel — flagged as playtest-watch item.

## Branch 9.3: feature/clone-swap-teleport  (parent: feature/clone-death-link)

**Scope (SPEC 6 + 10):** Tausch-Teleport — button press teleports the owner
to a clone, consuming it. Target = most recently placed living clone
(recorded decision for V1; SPEC leaves selection open). The jump counts as
a room change and resets the rotation timer immediately (SPEC 10 —
bypasses the 5 s dwell by definition). Escape anchor + planned routes.

**Files:** modify `scripts/player_capsule.gd` (`swap_teleport` action
KEY_T → `request_swap` RPC); `scripts/clones/clone_manager.gd` (host
validates owner alive + has clone + round active → broadcast consume +
teleport (owner repositions via its authority; host despawns clone));
`scripts/round/rotation_tracker.gd` (public `on_swap_teleport()` →
`reset_timer()` + immediate room re-detect); test
`tests/clone_swap_test.gd`.

**Automated test:** hider places clone in room B, walks to room A, rotation
timer near expiry → swap: position ≈ clone position on both peers, clone
consumed everywhere, rotation timer restarted (no elimination at the old
deadline), works with multiple clones (most recent consumed first); swap
with zero clones = no-op.

**Acceptance criteria:** SPEC 10 semantics incl. rotation reset; suite
green.

**Manual (Travis):** escape-anchor feel, two-machine, playtest cut-check
(clones remain the first cut candidate).

**Phase 9 / chain exit:** ENTIRE accumulated suite (all tests, boot, import,
diff check) green on `feature/clone-swap-teleport`; every branch pushed;
final evidence report written.

---

## Status tracking

Live status, SHAs, per-branch test evidence, risks, and the manual-validation
checklist live in `planning/PHASE_5_9_STATUS.md` (same branch chain — updated
on every branch, the only file every branch may touch besides its own).
