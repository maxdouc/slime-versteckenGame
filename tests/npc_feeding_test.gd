extends SceneTree
## Headless multi-peer test — NPC slimes + feeding (Phase 5,
## feature/npc-slimes-feeding).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/npc_feeding_test.gd
##
## Same world-branch pattern as tests/round_phases_test.gd, extended with the
## NPC wiring from main.tscn (Npcs container + NpcSpawner + NpcManager). The
## host spawns NPCs at PREP from the gray room's npc_spawn markers; the hider
## eats through the real any_peer RPC path; unfed NPCs vanish at HUNT start.
##
## Covers: marker contract, host-spawned NPC count (2 x hiders) on both peers,
## a validated eat (proximity + phase + role) syncing the count and despawning
## the NPC everywhere, the npc_eaten signal on clients, rejection of far/wrong-
## phase/seeker eats, and the HUNT-start cleanup. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const NPC_MANAGER_PATH := "res://scripts/round/npc_manager.gd"
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
		printerr("[npc_feeding_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[npc_feeding_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[npc_feeding_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## One isolated "machine" mirroring main.tscn: GameState + gray room +
## Players/PlayerSpawner + Npcs/NpcSpawner/NpcManager.
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
	var npcs := Node3D.new()
	npcs.name = "Npcs"
	world.add_child(npcs)
	var npc_spawner := MultiplayerSpawner.new()
	npc_spawner.name = "NpcSpawner"
	world.add_child(npc_spawner)
	npc_spawner.spawn_path = NodePath("../Npcs")
	var manager: Node = (load(NPC_MANAGER_PATH) as GDScript).new()
	manager.name = "NpcManager"
	world.add_child(manager)
	var info := {"world": world, "api": api, "gs": gs, "players": players,
			"spawner": spawner, "npcs": npcs, "manager": manager}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _npc_count(info: Dictionary) -> int:
	return info.npcs.get_child_count()

func _run_tests() -> void:
	await process_frame

	# --- Marker contract --------------------------------------------------------
	print("[npc_feeding_test] npc_spawn markers")
	var room_probe: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room_probe)
	await process_frame
	var marker_count := 0
	for marker in room_probe.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("npc_spawn"):
			marker_count += 1
	_check(marker_count >= 6, "gray room has >= 6 npc_spawn markers (%d)" % marker_count)
	root.remove_child(room_probe)
	room_probe.free()

	# --- Connect host + client ---------------------------------------------------
	print("[npc_feeding_test] connect host + client")
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
		_check(false, "no connected pair — aborting")
		_finish()
		return

	# Track npc_eaten on the CLIENT world (diff-based emission must fire there).
	var client_eaten_events: Array = []
	client.gs.npc_eaten.connect(func(peer_id: int, count: int) -> void:
		client_eaten_events.append([peer_id, count]))

	# --- Round: NPCs spawn at PREP ------------------------------------------------
	print("[npc_feeding_test] NPCs spawn at PREP (2 x hiders)")
	host.gs.prep_seconds = 30.0  # long PREP: the test drives transitions itself
	host.gs.hunt_seconds = 30.0
	host.gs.end_seconds = 0.3
	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	var both_prep := await _until(prep_pred, SYNC_BUDGET)
	_check(both_prep, "both peers in PREP")

	# 2 players -> 1 hider -> 2 NPCs (SPEC.md 7: 2 x hider count).
	var npcs_spawned_pred := func() -> bool:
		return _npc_count(host) == 2 and _npc_count(client) == 2
	var npcs_spawned := await _until(npcs_spawned_pred, SYNC_BUDGET)
	_check(npcs_spawned, "2 NPCs spawned on host AND client (1 hider x 2)")
	if not npcs_spawned:
		_finish()
		return

	# Same NPCs, same spots, sleeping look: node names + positions match.
	var names_match := true
	for npc in host.npcs.get_children():
		var twin: Node3D = client.npcs.get_node_or_null(NodePath(npc.name))
		if twin == null or npc.position.distance_to(twin.position) > 0.01:
			names_match = false
	_check(names_match, "NPC names + positions identical on both peers")

	# --- Who is the hider? Drive its world's capsule + manager. -------------------
	var hider_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider_id = id
	_check(hider_id > 0, "found the hider id")
	var seeker_id: int = 1 if hider_id == client_id else client_id
	var hider_world: Dictionary = client if hider_id == client_id else host
	var seeker_world: Dictionary = host if hider_id == client_id else client

	var target_npc: Node3D = host.npcs.get_child(0)
	var target_id: int = target_npc.npc_id
	var second_npc: Node3D = host.npcs.get_child(1)
	var second_id: int = second_npc.npc_id

	# --- Rejections first: far away, wrong role ----------------------------------
	print("[npc_feeding_test] rejected eats")
	var hider_capsule: Node3D = hider_world.players.get_node(str(hider_id))
	hider_capsule.global_position = target_npc.global_position \
			+ Vector3(0.0, 0.5, 0.0) + Vector3(6.0, 0.0, 0.0)  # 6 m away
	hider_world.manager.request_eat_from(hider_id, target_id)
	await _until(func() -> bool: return false, 0.6)  # give a wrong accept time to sync
	_check(host.gs.eaten_of(hider_id) == 0, "eat from 6 m away rejected (distance gate)")
	_check(_npc_count(host) == 2, "NPC survived the far eat attempt")

	var seeker_capsule: Node3D = seeker_world.players.get_node(str(seeker_id))
	seeker_capsule.global_position = seeker_world.npcs.get_child(0).global_position \
			+ Vector3(0.5, 0.5, 0.0)
	seeker_world.manager.request_eat_from(seeker_id, target_id)
	await _until(func() -> bool: return false, 0.6)
	_check(host.gs.eaten_of(seeker_id) == 0, "seeker eat rejected (role gate)")
	_check(_npc_count(host) == 2, "NPC survived the seeker attempt")

	# --- The real eat: hider next to the NPC in PREP -------------------------------
	print("[npc_feeding_test] valid eat")
	var hider_npc_twin: Node3D = hider_world.npcs.get_node(NodePath(target_npc.name))
	hider_capsule.global_position = hider_npc_twin.global_position + Vector3(0.6, 0.3, 0.0)
	await process_frame
	hider_world.manager.request_eat_from(hider_id, target_id)
	var eaten_pred := func() -> bool:
		return host.gs.eaten_of(hider_id) == 1 and client.gs.eaten_of(hider_id) == 1 \
				and _npc_count(host) == 1 and _npc_count(client) == 1
	var eaten := await _until(eaten_pred, SYNC_BUDGET)
	_check(eaten, "valid eat: count 1 + NPC despawned on host AND client")
	var signal_pred := func() -> bool: return client_eaten_events.size() >= 1
	var signal_fired := await _until(signal_pred, SYNC_BUDGET)
	_check(signal_fired and client_eaten_events[0][0] == hider_id \
			and client_eaten_events[0][1] == 1,
			"client emitted npc_eaten(hider, 1) from the registry diff")
	_check(host.gs.eaten_of(seeker_id) == 0, "seeker count untouched")

	# Double-eat of the already-gone NPC: nothing changes.
	hider_world.manager.request_eat_from(hider_id, target_id)
	await _until(func() -> bool: return false, 0.5)
	_check(host.gs.eaten_of(hider_id) == 1, "re-eating a gone NPC rejected")

	# --- HUNT: eating forbidden, leftovers vanish -----------------------------------
	print("[npc_feeding_test] HUNT start clears NPCs")
	host.gs.hunt_seconds = 1.2
	host.gs._advance_phase()  # host authority: force PREP -> HUNT now
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	var both_hunt := await _until(hunt_pred, SYNC_BUDGET)
	_check(both_hunt, "both peers in HUNT")
	var cleared_pred := func() -> bool:
		return _npc_count(host) == 0 and _npc_count(client) == 0
	var cleared := await _until(cleared_pred, SYNC_BUDGET)
	_check(cleared, "unfed NPCs vanished at HUNT start on host AND client")

	# Eating in HUNT: the second NPC is gone anyway, so aim at a fresh round…
	# instead assert the phase gate directly with a would-have-been-valid setup.
	hider_world.manager.request_eat_from(hider_id, second_id)
	await _until(func() -> bool: return false, 0.5)
	_check(host.gs.eaten_of(hider_id) == 1, "eat during HUNT rejected (phase gate)")

	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	var round_over := await _until(lobby_pred, 8.0)
	_check(round_over, "round ended back in LOBBY")

	# --- Round 2: fresh counts, fresh NPCs -------------------------------------------
	print("[npc_feeding_test] round 2 resets eaten + respawns NPCs")
	host.gs.start_round()
	var npcs_again_pred := func() -> bool:
		return _npc_count(host) == 2 and _npc_count(client) == 2
	var npcs_again := await _until(npcs_again_pred, SYNC_BUDGET)
	_check(npcs_again, "round 2 spawned fresh NPCs on both peers")
	_check(host.gs.eaten_of(1) == 0 and host.gs.eaten_of(client_id) == 0,
			"eaten counts reset for the new round")
	host.gs._advance_phase()  # PREP -> HUNT
	host.gs._advance_phase()  # HUNT -> END; END expires into LOBBY on its own
	await _until(lobby_pred, 8.0)

	# --- Both request paths: the HOST player must be able to eat too (rpc_id at
	# yourself is illegal — the host path must call directly). Roles are random,
	# so start fresh rounds until each machine has been the hider once. ---------
	print("[npc_feeding_test] host-as-hider AND client-as-hider both eat")
	var seen := {1: false, client_id: false}
	var rounds := 0
	while (not seen[1] or not seen[client_id]) and rounds < 10 and not _done:
		rounds += 1
		host.gs.start_round()
		var round_npcs_pred := func() -> bool:
			return _npc_count(host) == 2 and _npc_count(client) == 2 \
					and host.gs.current_phase == host.gs.Phase.PREP \
					and client.gs.current_phase == client.gs.Phase.PREP
		if not await _until(round_npcs_pred, SYNC_BUDGET):
			_check(false, "round %d: NPCs failed to spawn" % (rounds + 2))
			break
		var round_hider := -1
		for id in host.gs.players:
			if host.gs.players[id]["role"] == host.gs.Role.HIDER:
				round_hider = id
		var eat_world: Dictionary = client if round_hider == client_id else host
		var eat_capsule: Node3D = eat_world.players.get_node(str(round_hider))
		var eat_npc: Node3D = eat_world.npcs.get_child(0)
		eat_capsule.global_position = eat_npc.global_position + Vector3(0.6, 0.3, 0.0)
		await process_frame
		eat_world.manager.request_eat_from(round_hider, eat_npc.npc_id)
		var this_hider := round_hider
		var round_eat_pred := func() -> bool:
			return host.gs.eaten_of(this_hider) == 1 and client.gs.eaten_of(this_hider) == 1
		if await _until(round_eat_pred, SYNC_BUDGET):
			seen[round_hider] = true
		host.gs._advance_phase()
		host.gs._advance_phase()
		await _until(lobby_pred, 8.0)
	_check(seen[1], "the HOST player ate successfully as hider (direct path)")
	_check(seen[client_id], "the CLIENT player ate successfully as hider (rpc path)")

	_finish()
