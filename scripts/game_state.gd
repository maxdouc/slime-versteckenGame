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

enum Phase { LOBBY, PREP, HUNT, END }
enum Role { NONE, HIDER, SEEKER }

# Defaults — SPEC.md 4. Host-configurable at lobby time.
var prep_seconds: float = 60.0
var hunt_seconds: float = 240.0
var end_seconds: float = 10.0          ## END screen dwell before LOBBY
var rotation_seconds: float = 60.0     ## per-hider rotation timer (SPEC.md 6)
var paintball_cooldown: float = 4.0    ## seeker miss penalty (SPEC.md 11)

var current_phase: Phase = Phase.LOBBY

## peer_id -> {"role": Role, "alive": bool, "eaten": int}. The host writes and
## broadcasts it wholesale (6-8 players — tiny); everyone else only reads.
var players: Dictionary = {}

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
			_set_phase(Phase.END)
		Phase.END:
			_set_phase(Phase.LOBBY)
		_:
			pass

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
	phase_changed.emit(current_phase)

@rpc("authority", "call_local", "reliable")
func _sync_registry(reg: Dictionary, fresh_roles: bool) -> void:
	players = reg
	registry_changed.emit()
	if fresh_roles:
		roles_assigned.emit()

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
	_sync_registry.rpc_id(id, players, false)
	_sync_phase.rpc_id(id, current_phase, _timer)

func _on_peer_disconnected(id: int) -> void:
	if not _is_authority():
		return
	if players.has(id):
		var reg := players.duplicate(true)
		reg.erase(id)
		_broadcast_registry(reg, false)
