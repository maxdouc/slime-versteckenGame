extends Node
## GameState — host-authoritative round state: phase machine + player registry
## (Phase 5, feature/round-phases).
##
## The HOST (the server peer — or the sole machine when no real transport is
## attached) owns every phase transition and the player registry; clients
## follow via @rpc on this node. All timings are the host-adjustable defaults
## from SPEC.md 4 (Among-Us principle) — only the HOST's values matter, they
## travel to clients inside the sync RPCs.
##
## Gameplay resolves this node through scripts/round/round_locator.gd (an
## ancestor walk), never through the compile-time autoload identifier. That
## keeps every consumer testable in the headless multi-world pattern: each
## test world carries its own GameState child at the same relative path the
## autoload has under /root, so RPC paths match real machines exactly.
##
## Round flow (SPEC.md 5): LOBBY -> PREP (hiders eat/hide, seekers boxed) ->
## HUNT -> END (result screen) -> LOBBY. Roles per SPEC.md 4: 2 seekers from
## 7 players, else 1 — always leaving at least one hider; a solo dev round is
## 1 hider, 0 seekers. Mid-round joiners are registered as spectators
## ({NONE, not alive}) until the next round starts (recorded team decision in
## planning/PHASE_5_9_EXECUTION.md).

signal phase_changed(phase: Phase)
signal roles_assigned
signal registry_changed
signal npc_eaten(peer_id: int, count: int)
signal player_eliminated(peer_id: int, reason: String)
signal round_reset

enum Phase { LOBBY, PREP, HUNT, END }
enum Role { NONE, HIDER, SEEKER }

const Progression := preload("res://scripts/round/progression.gd")

# Defaults — SPEC.md 4. Host-configurable at lobby time.
var prep_seconds: float = 60.0
var hunt_seconds: float = 240.0
var end_seconds: float = 10.0          ## END screen dwell before LOBBY
var rotation_seconds: float = 60.0     ## per-hider rotation timer (SPEC.md 6)
var rotation_dwell_seconds: float = 5.0   ## stay this long before a room counts
var rotation_grace_seconds: float = 10.0  ## drip window after expiry, then out
var paintball_cooldown: float = 4.0    ## seeker miss penalty (SPEC.md 11)
var npcs_per_hider: float = 2.0        ## NPC slimes per hider (SPEC.md 7)

var current_phase: Phase = Phase.LOBBY

## peer_id -> {"role": Role, "alive": bool, "eaten": int}. The host writes and
## broadcasts it wholesale (6-8 players — tiny); everyone else only reads.
var players: Dictionary = {}

## Result of the round on display during END (SPEC.md 5.3):
## {"winner": "seekers"|"hiders", "survivors": Array of peer ids}. Survivors
## are the individual winners — there is no score. Cleared at round start.
var end_result: Dictionary = {}

var _timer: float = 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(delta: float) -> void:
	if current_phase == Phase.LOBBY:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.0  # clients floor the display here and wait for the host
	if _is_authority():
		_advance_phase()

## Host-only: begin a round from the lobby.
func start_round() -> void:
	if not can_start_round():
		return
	_broadcast_settings()  # clients run their own rotation timers on these
	var ids := _connected_ids()
	var seeker_count := clampi(2 if ids.size() >= 7 else 1, 0, ids.size() - 1)
	ids.shuffle()
	var reg := {}
	for i in ids.size():
		reg[ids[i]] = {
			"role": Role.SEEKER if i < seeker_count else Role.HIDER,
			"alive": true,
			"eaten": 0,
		}
	_broadcast_registry(reg, true)
	_set_phase(Phase.PREP)

## Victim-side entry point: this machine's own player just lost cohesion
## (rotation) — later also other self-reported causes. The HOST re-validates.
func request_elimination(reason: String) -> void:
	var me := multiplayer.get_unique_id() if _has_net_peer() else 1
	if _has_net_peer() and not multiplayer.is_server():
		_request_elimination_rpc.rpc_id(1, me, reason)
	else:
		_request_elimination_rpc(me, reason)

@rpc("any_peer", "reliable")
func _request_elimination_rpc(victim_id: int, reason: String) -> void:
	if not _is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != victim_id:
		return  # only the victim itself may self-report
	eliminate_player(victim_id, reason)

## HOST-side elimination entry — the data layer: flips alive=false in the
## registry and broadcasts the event. The full death BEHAVIOR (ghosting, win
## checks, END, reset) is owned by feature/win-lose-reset; Phase 6's paintball
## calls this same entry with reason "paintball".
func eliminate_player(victim_id: int, reason: String) -> void:
	if not _is_authority() or current_phase != Phase.HUNT:
		return  # eliminations only happen during the hunt (SPEC.md 5/6)
	if role_of(victim_id) != Role.HIDER or not is_alive(victim_id):
		return
	var reg := players.duplicate(true)
	reg[victim_id]["alive"] = false
	_broadcast_registry(reg, false)
	if _has_net_peer():
		_sync_elimination.rpc(victim_id, reason)
	else:
		_sync_elimination(victim_id, reason)
	# Win check (SPEC.md 5.3): seekers win once every hider is gone.
	if alive_hider_ids().is_empty():
		_finish_round("seekers", [])

func can_start_round() -> bool:
	return current_phase == Phase.LOBBY and _is_authority()

func role_of(id: int) -> Role:
	return players[id]["role"] if players.has(id) else Role.NONE

func is_seeker(id: int) -> bool:
	return role_of(id) == Role.SEEKER

func is_alive(id: int) -> bool:
	return players.has(id) and players[id]["alive"]

func is_round_active() -> bool:
	return current_phase == Phase.PREP or current_phase == Phase.HUNT

func eaten_of(id: int) -> int:
	return players[id]["eaten"] if players.has(id) else 0

func hider_ids() -> Array:
	var out: Array = []
	for id in players:
		if players[id]["role"] == Role.HIDER:
			out.append(id)
	return out

func alive_hider_ids() -> Array:
	var out: Array = []
	for id in players:
		if players[id]["role"] == Role.HIDER and players[id]["alive"]:
			out.append(id)
	return out

## Host-only: a validated feeding just completed (SPEC.md 7). The updated
## registry travels to everyone; clients learn about the increase through the
## diff in _sync_registry and re-emit npc_eaten locally. The count caps at
## the SPEC.md 8 progression cap — a 4th NPC is still consumed but buys
## nothing (recorded decision; the spec caps the progression, not the meal).
func record_eaten(id: int) -> void:
	if not _is_authority() or not players.has(id):
		return
	if players[id]["eaten"] >= Progression.EAT_CAP:
		return
	var reg := players.duplicate(true)
	reg[id]["eaten"] += 1
	_broadcast_registry(reg, false)

## Round-truth query for sibling systems (NPC manager, seeker kit, …).
func is_round_authority() -> bool:
	return _is_authority()

func time_left() -> float:
	return maxf(_timer, 0.0)

func phase_name() -> String:
	return Phase.keys()[current_phase]

## Player-facing phase title (German — project string convention).
func phase_title() -> String:
	match current_phase:
		Phase.PREP:
			return "Vorbereitung"
		Phase.HUNT:
			return "Jagd"
		Phase.END:
			return "Rundenende"
		_:
			return "Lobby"

# --- Host internals ----------------------------------------------------------

func _advance_phase() -> void:
	match current_phase:
		Phase.PREP:
			_set_phase(Phase.HUNT)
		Phase.HUNT:
			# The clock beat the seekers: every hider still alive wins
			# individually (SPEC.md 5.3 — no score).
			_finish_round("hiders", alive_hider_ids())
		Phase.END:
			reset_round()
			_set_phase(Phase.LOBBY)
		_:
			pass

## Host-only: seal the round with its result and show the END screen.
func _finish_round(winner: String, survivors: Array) -> void:
	var result := {"winner": winner, "survivors": survivors}
	if _has_net_peer():
		_sync_end_result.rpc(result)
	else:
		_sync_end_result(result)
	_set_phase(Phase.END)

## Host-only: the COMPLETE per-round reset (SPEC.md 5.3 — "Kompletter Reset
## jede Runde. Keine persistenten Freischaltungen."). Every peer un-ghosts,
## re-slimes and respawns via the round_reset broadcast; the registry clears
## so the lobby has no roles, no eats, no corpses.
func reset_round() -> void:
	if not _is_authority():
		return
	if _has_net_peer():
		_sync_round_reset.rpc()
	else:
		_sync_round_reset()
	_broadcast_registry({}, false)

func _set_phase(p: Phase) -> void:
	var duration := 0.0
	match p:
		Phase.PREP:
			duration = prep_seconds
		Phase.HUNT:
			duration = hunt_seconds
		Phase.END:
			duration = end_seconds
	if _has_net_peer():
		_sync_phase.rpc(p, duration)
	else:
		_sync_phase(p, duration)

func _broadcast_registry(reg: Dictionary, fresh_roles: bool) -> void:
	if _has_net_peer():
		_sync_registry.rpc(reg, fresh_roles)
	else:
		_sync_registry(reg, fresh_roles)

## Host settings that OTHER machines act on locally (rotation timings now;
## cooldown display later). Sent at round start and to late joiners.
func _settings_payload() -> Dictionary:
	return {
		"prep_seconds": prep_seconds,
		"hunt_seconds": hunt_seconds,
		"end_seconds": end_seconds,
		"rotation_seconds": rotation_seconds,
		"rotation_dwell_seconds": rotation_dwell_seconds,
		"rotation_grace_seconds": rotation_grace_seconds,
		"paintball_cooldown": paintball_cooldown,
		"npcs_per_hider": npcs_per_hider,
	}

func _broadcast_settings() -> void:
	if _has_net_peer():
		_sync_settings.rpc(_settings_payload())
	else:
		_sync_settings(_settings_payload())

## True only with a REAL transport attached. Offline play (editor solo, no
## lobby yet) and the OfflineMultiplayerPeer default both count as "no peer":
## RPCs would be pointless or error, so the host path calls methods directly.
func _has_net_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

## The machine that owns round truth: the server — or anyone playing alone.
func _is_authority() -> bool:
	return not _has_net_peer() or multiplayer.is_server()

func _connected_ids() -> Array:
	if not _has_net_peer():
		return [1]
	var ids: Array = [multiplayer.get_unique_id()]
	for id in multiplayer.get_peers():
		ids.append(id)
	return ids

# --- Replication ---------------------------------------------------------------

## Broadcast by the host; call_local applies it through the same code path on
## the host itself — one deterministic path for every peer (paint_sync model).
@rpc("authority", "call_local", "reliable")
func _sync_phase(phase: int, duration: float) -> void:
	current_phase = phase as Phase
	_timer = duration
	if current_phase == Phase.PREP:
		end_result = {}  # a fresh round owes nothing to the last one
	phase_changed.emit(current_phase)

@rpc("authority", "call_local", "reliable")
func _sync_settings(s: Dictionary) -> void:
	prep_seconds = s.get("prep_seconds", prep_seconds)
	hunt_seconds = s.get("hunt_seconds", hunt_seconds)
	end_seconds = s.get("end_seconds", end_seconds)
	rotation_seconds = s.get("rotation_seconds", rotation_seconds)
	rotation_dwell_seconds = s.get("rotation_dwell_seconds", rotation_dwell_seconds)
	rotation_grace_seconds = s.get("rotation_grace_seconds", rotation_grace_seconds)
	paintball_cooldown = s.get("paintball_cooldown", paintball_cooldown)
	npcs_per_hider = s.get("npcs_per_hider", npcs_per_hider)

@rpc("authority", "call_local", "reliable")
func _sync_elimination(victim_id: int, reason: String) -> void:
	player_eliminated.emit(victim_id, reason)

@rpc("authority", "call_local", "reliable")
func _sync_end_result(result: Dictionary) -> void:
	end_result = result

@rpc("authority", "call_local", "reliable")
func _sync_round_reset() -> void:
	round_reset.emit()

@rpc("authority", "call_local", "reliable")
func _sync_registry(reg: Dictionary, fresh_roles: bool) -> void:
	# Diff the eaten counts BEFORE replacing, so every peer (not only the
	# host) can emit npc_eaten without a second RPC.
	var increases: Array = []
	if not fresh_roles:
		for id in reg:
			var before: int = players[id]["eaten"] if players.has(id) else 0
			if reg[id]["eaten"] > before:
				increases.append([id, reg[id]["eaten"]])
	players = reg
	registry_changed.emit()
	if fresh_roles:
		roles_assigned.emit()
	for inc in increases:
		npc_eaten.emit(inc[0], inc[1])

# --- Peer lifecycle (host book-keeping) ----------------------------------------

func _on_peer_connected(id: int) -> void:
	if not _is_authority() or not _has_net_peer():
		return
	# Mid-round joiners spectate until the next round. The broadcast reaches
	# the joiner too, but the explicit snapshot below also covers joins in
	# LOBBY (no broadcast needed) and re-sends the current phase + clock.
	if not players.has(id):
		var reg := players.duplicate(true)
		reg[id] = {"role": Role.NONE, "alive": false, "eaten": 0}
		_broadcast_registry(reg, false)
	_sync_settings.rpc_id(id, _settings_payload())
	_sync_registry.rpc_id(id, players, false)
	_sync_phase.rpc_id(id, current_phase, _timer)

func _on_peer_disconnected(id: int) -> void:
	if not _is_authority():
		return
	if players.has(id):
		var reg := players.duplicate(true)
		reg.erase(id)
		_broadcast_registry(reg, false)
		# A vanished hider can decide the round: no hiders left = seeker win.
		if current_phase == Phase.HUNT and alive_hider_ids().is_empty():
			_finish_round("seekers", [])
