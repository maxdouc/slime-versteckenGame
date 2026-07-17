extends SceneTree
## Headless multi-peer test — round phase machine (Phase 5, feature/round-phases).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/round_phases_test.gd
##
## Uses the established in-process pattern (see tests/network_transform_test.gd):
## isolated SceneMultiplayer branches over real localhost ENet peers. Each world
## gets its own `GameState` node (script scripts/game_state.gd) directly under
## the branch root — the same relative path the real game has (the autoload is a
## direct child of /root), so the @rpc paths match between test worlds exactly
## like they match between real machines. Gameplay resolves its round state via
## the ancestor-walk locator (scripts/round/round_locator.gd), never via the
## compile-time autoload identifier.
##
## Covers: host-driven LOBBY->PREP->HUNT->END->LOBBY with clients following,
## role assignment (exactly one seeker for 2 players, identical on all peers),
## seeker held in the sealed spawn room during PREP and released at HUNT,
## mid-round late join (phase + registry snapshot, joiner = NONE/not alive),
## host registry cleanup on disconnect, and the offline solo sandbox path.
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 150.0

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false
var _cleanup_peers: Array = []
var _worlds: Array = []
var _host_spawn_slot := 0

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		_failures += 1  # a timeout is a failure even if every ran check passed
		printerr("[round_phases_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
		_finish()
	return _done

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)

func _finish() -> void:
	if _done:
		return
	_done = true
	var branch_paths: Array = []
	for info in _worlds:
		branch_paths.append(info.world.get_path())
	for info in _worlds:
		root.remove_child(info.world)
		info.world.free()
	for path in branch_paths:
		set_multiplayer(null, path)
	for info in _worlds:
		info.api.multiplayer_peer = null
	for peer in _cleanup_peers:
		if peer != null:
			peer.close()
	for info in _worlds:
		info.clear()
	_worlds.clear()
	_cleanup_peers.clear()
	if _failures == 0:
		print("[round_phases_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[round_phases_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## One isolated "machine": branch API + gray room + GameState node (same
## relative path as the real autoload) + the Players/PlayerSpawner wiring.
func _make_world(world_name: String, x_offset: float) -> Dictionary:
	var world := Node3D.new()
	world.name = world_name
	world.position = Vector3(x_offset, 0.0, 0.0)
	root.add_child(world)
	var api := MultiplayerAPI.create_default_interface()
	set_multiplayer(api, world.get_path())
	var gs: Node = (load(GAME_STATE_PATH) as GDScript).new()
	gs.name = "GameState"
	world.add_child(gs)
	world.add_child(load(ROOM_SCENE_PATH).instantiate())
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	world.add_child(spawner)
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_capsule
	var info := {"world": world, "api": api, "gs": gs, "players": players, "spawner": spawner}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _seeker_ids(gs: Node) -> Array:
	var out: Array = []
	for id in gs.players:
		if gs.players[id]["role"] == gs.Role.SEEKER:
			out.append(id)
	return out

## Both worlds report the given phase.
func _phase_pred(a: Node, b: Node, phase: int) -> Callable:
	return func() -> bool: return a.current_phase == phase and b.current_phase == phase

## The named capsule's parent-relative distance to its world origin compares
## `far` against 12 m on both worlds (seeker box sits ~20 m out, main room ≤ 8).
func _distance_pred(a_players: Node, b_players: Node, node_name: String, far: bool) -> Callable:
	return func() -> bool:
		var a: Node3D = a_players.get_node_or_null(node_name)
		var b: Node3D = b_players.get_node_or_null(node_name)
		if a == null or b == null:
			return false
		var a_far := Vector2(a.position.x, a.position.z).length() > 12.0
		var b_far := Vector2(b.position.x, b.position.z).length() > 12.0
		return a_far == far and b_far == far

func _run_tests() -> void:
	await process_frame

	# --- Scene contract: spawn markers exist and are grouped -------------------
	print("[round_phases_test] gray room spawn markers")
	var room_probe: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room_probe)
	await process_frame
	var seeker_marker: Node3D = null
	var player_marker: Node3D = null
	for marker in room_probe.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("seeker_spawn"):
			seeker_marker = marker
		elif marker.is_in_group("player_spawn"):
			player_marker = marker
	_check(player_marker != null, "gray room has a player_spawn marker")
	_check(seeker_marker != null, "gray room has a seeker_spawn marker")
	var seeker_global := Vector3.ZERO
	if seeker_marker != null:
		seeker_global = seeker_marker.global_position
	_check(Vector2(seeker_global.x, seeker_global.z).length() > 14.0,
			"seeker spawn sits far outside the main room (sealed box)")
	root.remove_child(room_probe)
	room_probe.free()

	# --- Host + client connect over real localhost ENet ------------------------
	print("[round_phases_test] connect host + client")
	var host := _make_world("HostWorld", 0.0)
	var client := _make_world("ClientWorld", 50.0)

	var host_peer := ENetMultiplayerPeer.new()
	_check(host_peer.create_server(PORT, 8) == OK, "ENet server listening on %d" % PORT)
	_cleanup_peers.append(host_peer)
	host.api.multiplayer_peer = host_peer
	_host_spawn_slot = 1
	host.api.peer_connected.connect(func(id: int) -> void:
		host.spawner.spawn([id, Vector3(2.0 * _host_spawn_slot, 1.0, 0.0)])
		_host_spawn_slot += 1)
	host.api.peer_disconnected.connect(func(id: int) -> void:
		var gone: Node = host.players.get_node_or_null(str(id))
		if gone != null:
			gone.queue_free())
	host.spawner.spawn([1, Vector3(0.0, 1.0, 0.0)])

	var client_peer := ENetMultiplayerPeer.new()
	_check(client_peer.create_client("127.0.0.1", PORT) == OK, "ENet client created")
	_cleanup_peers.append(client_peer)
	client.api.multiplayer_peer = client_peer

	var connected_pred := func() -> bool:
		return client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	var connected := await _until(connected_pred, CONNECT_BUDGET)
	_check(connected, "client connected to host")
	var client_id: int = client.api.get_unique_id()
	var both_spawned_pred := func() -> bool:
		return host.players.get_child_count() == 2 and client.players.get_child_count() == 2
	var both_spawned := await _until(both_spawned_pred, CONNECT_BUDGET)
	_check(both_spawned, "both worlds spawned both capsules")
	if not (connected and both_spawned):
		_check(false, "no connected pair — skipping the round checks")
		_finish()
		return

	# --- Round 1: full phase cycle with shrunk host timings --------------------
	print("[round_phases_test] round 1: LOBBY -> PREP -> HUNT -> END -> LOBBY")
	host.gs.prep_seconds = 0.5
	host.gs.hunt_seconds = 0.7
	host.gs.end_seconds = 0.4
	_check(host.gs.current_phase == host.gs.Phase.LOBBY, "host starts in LOBBY")
	_check(not host.gs.is_round_active(), "LOBBY is not an active round")

	host.gs.start_round()
	var both_prep := await _until(_phase_pred(host.gs, client.gs, host.gs.Phase.PREP), SYNC_BUDGET)
	_check(both_prep, "start_round: PREP on host AND client")
	_check(host.gs.is_round_active(), "PREP counts as an active round")

	# Roles: exactly one seeker for two players, identical on both peers.
	var host_seekers := _seeker_ids(host.gs)
	var client_seekers := _seeker_ids(client.gs)
	_check(host.gs.players.size() == 2, "host registry has both players")
	_check(client.gs.players.size() == 2, "client registry has both players")
	_check(host_seekers.size() == 1, "exactly one seeker assigned (2 players)")
	_check(host_seekers == client_seekers, "identical seeker on host and client")
	var all_alive := true
	var eaten_zeroed := true
	for id in host.gs.players:
		all_alive = all_alive and host.gs.players[id]["alive"]
		eaten_zeroed = eaten_zeroed and host.gs.players[id]["eaten"] == 0
	_check(all_alive, "everyone starts alive")
	_check(eaten_zeroed, "everyone starts with eaten = 0")
	if host_seekers.size() != 1:
		_check(false, "no single seeker — skipping placement checks")
		_finish()
		return
	var seeker_id: int = host_seekers[0]
	var hider_id: int = 1 if seeker_id == client_id else client_id
	_check(host.gs.is_seeker(seeker_id), "is_seeker() agrees with the registry")
	_check(host.gs.role_of(hider_id) == host.gs.Role.HIDER, "the other player is a hider")
	_check(host.gs.is_alive(seeker_id), "is_alive() reads the registry")

	# Seeker sits in the sealed spawn room during PREP — on BOTH worlds
	# (positions are parent-relative, so the world offsets cancel out).
	var in_box := await _until(
			_distance_pred(host.players, client.players, str(seeker_id), true), SYNC_BUDGET)
	_check(in_box, "seeker teleported into the sealed box during PREP (both worlds)")
	var hider_near := await _until(
			_distance_pred(host.players, client.players, str(hider_id), false), SYNC_BUDGET)
	_check(hider_near, "hider stays in the main room during PREP")

	# --- PREP expires -> HUNT everywhere, seeker released ----------------------
	var both_hunt := await _until(_phase_pred(host.gs, client.gs, host.gs.Phase.HUNT), SYNC_BUDGET)
	_check(both_hunt, "PREP expiry: HUNT on host AND client")
	var released := await _until(
			_distance_pred(host.players, client.players, str(seeker_id), false), SYNC_BUDGET)
	_check(released, "seeker released into the main room at HUNT (both worlds)")

	# --- HUNT -> END -> LOBBY ---------------------------------------------------
	var both_end := await _until(_phase_pred(host.gs, client.gs, host.gs.Phase.END), SYNC_BUDGET)
	_check(both_end, "HUNT expiry: END on host AND client")
	_check(not host.gs.is_round_active(), "END is not an active round")
	var back_to_lobby := await _until(
			_phase_pred(host.gs, client.gs, host.gs.Phase.LOBBY), SYNC_BUDGET)
	_check(back_to_lobby, "END expiry: back to LOBBY on host AND client")

	# --- Round 2: late join mid-HUNT + disconnect cleanup ----------------------
	print("[round_phases_test] round 2: late join + disconnect")
	host.gs.prep_seconds = 0.3
	host.gs.hunt_seconds = 4.0
	host.gs.start_round()
	var hunt_pred := func() -> bool: return host.gs.current_phase == host.gs.Phase.HUNT
	var hunt_started := await _until(hunt_pred, SYNC_BUDGET)
	_check(hunt_started, "round 2 reached HUNT")

	var late := _make_world("LateWorld", 100.0)
	var late_peer := ENetMultiplayerPeer.new()
	_check(late_peer.create_client("127.0.0.1", PORT) == OK, "late ENet client created")
	_cleanup_peers.append(late_peer)
	late.api.multiplayer_peer = late_peer
	var late_conn_pred := func() -> bool:
		return late_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	var late_connected := await _until(late_conn_pred, CONNECT_BUDGET)
	_check(late_connected, "late client connected mid-HUNT")
	var late_id: int = late.api.get_unique_id()
	var late_sync_pred := func() -> bool:
		return late.gs.current_phase == late.gs.Phase.HUNT and late.gs.players.has(late_id)
	var late_synced := await _until(late_sync_pred, SYNC_BUDGET)
	_check(late_synced, "late joiner received phase HUNT + registry snapshot")
	if late_synced:
		_check(late.gs.role_of(late_id) == late.gs.Role.NONE,
				"mid-round joiner has role NONE")
		_check(not late.gs.is_alive(late_id), "mid-round joiner is not alive")
		_check(late.gs.players.size() == 3, "late registry contains all 3 players")
		_check(_seeker_ids(late.gs) == _seeker_ids(host.gs),
				"late joiner sees the same seeker")
	var late_everywhere_pred := func() -> bool:
		return host.gs.players.has(late_id) and client.gs.players.has(late_id)
	var host_added_late := await _until(late_everywhere_pred, SYNC_BUDGET)
	_check(host_added_late, "host + client registries picked up the late joiner")

	# Disconnect the late peer mid-round: host drops it and rebroadcasts.
	late_peer.close()
	late.api.multiplayer_peer = null
	var late_gone_pred := func() -> bool:
		return not host.gs.players.has(late_id) and not client.gs.players.has(late_id)
	var late_gone := await _until(late_gone_pred, CONNECT_BUDGET)
	_check(late_gone, "disconnected peer removed from every registry")

	var round2_done := await _until(
			_phase_pred(host.gs, client.gs, host.gs.Phase.LOBBY), 8.0)
	_check(round2_done, "round 2 ran out and returned everyone to LOBBY")

	# --- Offline solo sandbox: no peer, still playable --------------------------
	print("[round_phases_test] offline solo round")
	var solo: Node = (load(GAME_STATE_PATH) as GDScript).new()
	solo.name = "SoloGameState"
	root.add_child(solo)
	solo.prep_seconds = 0.2
	solo.hunt_seconds = 0.2
	solo.end_seconds = 0.2
	solo.start_round()
	_check(solo.current_phase == solo.Phase.PREP, "solo start_round enters PREP without a peer")
	_check(solo.players.size() == 1, "solo registry has exactly the local player")
	_check(_seeker_ids(solo).is_empty(), "solo round has zero seekers (clamped)")
	var solo_pred := func() -> bool: return solo.current_phase == solo.Phase.LOBBY
	var solo_cycled := await _until(solo_pred, 5.0)
	_check(solo_cycled, "solo round cycles PREP -> HUNT -> END -> LOBBY unaided")
	root.remove_child(solo)
	solo.free()

	_finish()
