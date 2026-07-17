extends SceneTree
## Headless three-peer test — roles, independent progression, reset, rejoin
## (fix/phase-5-9-manual-validation round 2, intermittent 3-player issue).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/three_player_round_test.gd
##
## Manual validation saw ONE 3-player round (1 seeker + 2 hiders) where a
## hider who ate NPCs could not transform while the other hider could not
## progress — a second identical round behaved. This test pins the whole
## contract over real localhost ENet with three (later four) full worlds:
##
##   * 3 players in the lobby -> exactly 1 seeker + 2 hiders, identical
##     registry on every peer
##   * both hiders eat INDEPENDENTLY from the shared NPC pool and their
##     unlocks follow their OWN eaten count (SPEC.md 8)
##   * the seeker can neither eat nor transform
##   * END -> reset -> LOBBY clears every role and progression everywhere
##     (the manual host start stays required — intended behavior)
##   * the next round deals fresh roles (shuffle-based assignment is
##     intentionally random — NOTHING here asserts who gets which role)
##   * a peer joining MID-ROUND spectates (role NONE, dead, no transform)
##     until the next round, where it plays with a real role
##
## Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const NPC_MANAGER_PATH := "res://scripts/round/npc_manager.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 6.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 200.0

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
		printerr("[three_player_round_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[three_player_round_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[three_player_round_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _wait(seconds: float) -> void:
	var deadline := _elapsed + seconds
	while _elapsed < deadline and not _done:
		await process_frame

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

## Every world must agree on phase + role/alive/eaten per player.
func _registries_agree(worlds: Array, expected_players: int) -> bool:
	var reference: Dictionary = worlds[0].gs.players
	if reference.size() != expected_players:
		return false
	for info in worlds:
		var reg: Dictionary = info.gs.players
		if reg.size() != expected_players:
			return false
		for id in reference:
			if not reg.has(id):
				return false
			if reg[id]["role"] != reference[id]["role"] \
					or reg[id]["alive"] != reference[id]["alive"] \
					or reg[id]["eaten"] != reference[id]["eaten"]:
				return false
	return true

func _role_counts(gs: Node) -> Dictionary:
	var out := {"seekers": 0, "hiders": 0, "none": 0}
	for id in gs.players:
		match gs.players[id]["role"]:
			gs.Role.SEEKER:
				out["seekers"] += 1
			gs.Role.HIDER:
				out["hiders"] += 1
			_:
				out["none"] += 1
	return out

## Feed one specific NPC to a hider through the production path: park the
## hider's own capsule at the NPC and fire the any_peer RPC, retrying while
## the position still replicates to the host (10 fps headless pacing).
func _eat_npc(hider_world: Dictionary, hider_id: int, npc: Node3D,
		want_eaten: int, all_worlds: Array) -> bool:
	var capsule: Node3D = hider_world.players.get_node(str(hider_id))
	var twin: Node3D = hider_world.npcs.get_node_or_null(NodePath(npc.name))
	if twin == null:
		return false
	capsule.global_position = twin.global_position + Vector3(0.6, 0.3, 0.0)
	capsule.velocity = Vector3.ZERO
	for _attempt in 4:
		await _wait(0.4)  # let the park replicate to the host copy
		hider_world.manager.request_eat_from(hider_id, npc.npc_id)
		var fed := func() -> bool:
			for info in all_worlds:
				if info.gs.eaten_of(hider_id) != want_eaten:
					return false
			return true
		if await _until(fed, 1.5):
			return true
	return false

func _run_tests() -> void:
	await process_frame

	print("[three_player_round_test] connect host + two clients (lobby join)")
	var host := _make_world("HostWorld", 0.0)
	var client_a := _make_world("ClientAWorld", 50.0)
	var client_b := _make_world("ClientBWorld", 100.0)
	var trio: Array = [host, client_a, client_b]

	var host_peer := ENetMultiplayerPeer.new()
	_check(host_peer.create_server(PORT, 8) == OK, "ENet server listening on %d" % PORT)
	_cleanup_peers.append(host_peer)
	host.api.multiplayer_peer = host_peer
	_host_spawn_slot = 1
	host.api.peer_connected.connect(func(id: int) -> void:
		host.spawner.spawn([id, Vector3(2.0 * _host_spawn_slot, 1.0, 0.0)])
		_host_spawn_slot += 1)
	host.spawner.spawn([1, Vector3(0.0, 1.0, 0.0)])

	var peer_a := ENetMultiplayerPeer.new()
	_check(peer_a.create_client("127.0.0.1", PORT) == OK, "client A created")
	_cleanup_peers.append(peer_a)
	client_a.api.multiplayer_peer = peer_a
	var peer_b := ENetMultiplayerPeer.new()
	_check(peer_b.create_client("127.0.0.1", PORT) == OK, "client B created")
	_cleanup_peers.append(peer_b)
	client_b.api.multiplayer_peer = peer_b

	var all_connected := func() -> bool:
		return peer_a.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and peer_b.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and host.players.get_child_count() == 3 \
				and client_a.players.get_child_count() == 3 \
				and client_b.players.get_child_count() == 3
	var connected := await _until(all_connected, CONNECT_BUDGET)
	_check(connected, "three peers connected, three capsules on every world")
	if not connected:
		_check(false, "no three-peer session — aborting")
		_finish()
		return
	var id_a: int = client_a.api.get_unique_id()
	var id_b: int = client_b.api.get_unique_id()
	var worlds_by_id := {1: host, id_a: client_a, id_b: client_b}

	host.gs.prep_seconds = 120.0
	host.gs.hunt_seconds = 60.0
	host.gs.end_seconds = 0.5
	host.gs.rotation_seconds = 60.0  # rotation must not interfere here

	# --- Round 1: exactly 1 seeker + 2 hiders, agreed everywhere ---------------
	print("[three_player_round_test] round 1: roles")
	host.gs.start_round()
	var round1_pred := func() -> bool:
		for info in trio:
			if info.gs.current_phase != info.gs.Phase.PREP:
				return false
		return _registries_agree(trio, 3)
	_check(await _until(round1_pred, SYNC_BUDGET),
			"PREP everywhere with an identical 3-player registry")
	var counts: Dictionary = _role_counts(host.gs)
	_check(counts["seekers"] == 1 and counts["hiders"] == 2 and counts["none"] == 0,
			"exactly 1 seeker and 2 hiders (got %s)" % str(counts))
	var seeker_id := -1
	var hider_ids: Array = []
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.SEEKER:
			seeker_id = id
		else:
			hider_ids.append(id)
	var h1: int = hider_ids[0]
	var h2: int = hider_ids[1]
	var h1_world: Dictionary = worlds_by_id[h1]
	var h2_world: Dictionary = worlds_by_id[h2]
	var seeker_world: Dictionary = worlds_by_id[seeker_id]

	# --- NPC pool: npcs_per_hider (2) x 2 hiders on every world -----------------
	var npcs_pred := func() -> bool:
		for info in trio:
			if info.npcs.get_child_count() != 4:
				return false
		return true
	_check(await _until(npcs_pred, SYNC_BUDGET), "4 NPCs spawned on every world")

	# --- Independent feeding: h1 eats 2, h2 eats 1 -----------------------------
	print("[three_player_round_test] independent feeding")
	var pool: Array = host.npcs.get_children().duplicate()
	_check(await _eat_npc(h1_world, h1, pool[0], 1, trio), "hider 1 ate NPC #1")
	_check(await _eat_npc(h1_world, h1, pool[1], 2, trio), "hider 1 ate NPC #2")
	_check(await _eat_npc(h2_world, h2, pool[2], 1, trio), "hider 2 ate NPC #3")
	var counts_pred := func() -> bool:
		for info in trio:
			if info.gs.eaten_of(h1) != 2 or info.gs.eaten_of(h2) != 1:
				return false
		return true
	_check(await _until(counts_pred, SYNC_BUDGET),
			"eaten counts INDEPENDENT and agreed everywhere (h1=2, h2=1)")

	# --- Unlocks follow each hider's OWN count (SPEC.md 8) ---------------------
	var h1_capsule: CharacterBody3D = h1_world.players.get_node(str(h1))
	var h2_capsule: CharacterBody3D = h2_world.players.get_node(str(h2))
	h1_capsule.transform_to_prop("cup")
	_check(h1_capsule.form_id == "cup", "hider 1 (2 eaten) unlocked SMALL")
	h1_capsule.transform_to_prop("bucket")
	_check(h1_capsule.form_id == "bucket", "hider 1 (2 eaten) unlocked MEDIUM")
	h2_capsule.transform_to_prop("bucket")
	_check(h2_capsule.form_id == "bucket", "hider 2 (1 eaten) unlocked MEDIUM")
	h2_capsule.transform_to_prop("cup")
	_check(h2_capsule.form_id == "bucket", "hider 2 (1 eaten) still LOCKED out of SMALL")
	h2_capsule.transform_to_prop("carton")
	_check(h2_capsule.form_id == "carton", "hider 2: LARGE always available")

	# --- The seeker can neither eat nor transform ------------------------------
	print("[three_player_round_test] seeker gates")
	var seeker_capsule: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))
	seeker_capsule.transform_to_prop("carton")
	_check(seeker_capsule.form_id == "slime", "seeker cannot transform")
	var last_npc: Node3D = pool[3]
	var seeker_twin: Node3D = seeker_world.npcs.get_node_or_null(NodePath(last_npc.name))
	if seeker_twin != null:
		seeker_capsule.global_position = seeker_twin.global_position + Vector3(0.6, 0.3, 0.0)
		seeker_capsule.velocity = Vector3.ZERO
	await _wait(0.6)
	seeker_world.manager.request_eat_from(seeker_id, last_npc.npc_id)
	await _wait(0.8)
	_check(host.gs.eaten_of(seeker_id) == 0, "seeker eat rejected")
	_check(is_instance_valid(last_npc) and host.npcs.get_child_count() == 1,
			"the last NPC survived the seeker")

	# --- END -> reset -> LOBBY clears progression everywhere -------------------
	print("[three_player_round_test] reset")
	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		for info in trio:
			if info.gs.current_phase != info.gs.Phase.HUNT:
				return false
		return true
	await _until(hunt_pred, SYNC_BUDGET)
	host.gs._advance_phase()  # HUNT -> END (hiders win) -> 0.5 s -> LOBBY + reset
	var lobby_pred := func() -> bool:
		for info in trio:
			if info.gs.current_phase != info.gs.Phase.LOBBY:
				return false
			if not info.gs.players.is_empty():
				return false
		return true
	_check(await _until(lobby_pred, 8.0),
			"END -> reset -> LOBBY: registry EMPTY on every world (manual restart stays)")
	var reslimed_pred := func() -> bool:
		return h1_capsule.form_id == "slime" and h2_capsule.form_id == "slime"
	_check(await _until(reslimed_pred, SYNC_BUDGET), "hiders re-slimed by the reset")

	# --- Round 2 starts; a FOURTH peer joins MID-ROUND and spectates ----------
	print("[three_player_round_test] round 2 + mid-round joiner")
	host.gs.start_round()
	var round2_pred := func() -> bool:
		for info in trio:
			if info.gs.current_phase != info.gs.Phase.PREP:
				return false
		return _registries_agree(trio, 3)
	_check(await _until(round2_pred, SYNC_BUDGET), "round 2 running (fresh registry)")
	var counts2: Dictionary = _role_counts(host.gs)
	_check(counts2["seekers"] == 1 and counts2["hiders"] == 2,
			"round 2 again 1 seeker + 2 hiders (shuffle result itself is random)")
	var fresh_pred := func() -> bool:
		for id in host.gs.players:
			if host.gs.eaten_of(id) != 0:
				return false
		return true
	_check(fresh_pred.call(), "round 2 progression starts at 0 eaten for everyone")
	# A hider with 0 eaten must be locked out of MEDIUM again.
	var r2_hider := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			r2_hider = id
	var r2_capsule: CharacterBody3D = worlds_by_id[r2_hider].players.get_node(str(r2_hider))
	r2_capsule.transform_to_prop("bucket")
	_check(r2_capsule.form_id == "slime", "0 eaten: MEDIUM locked again (reset really cleared)")
	r2_capsule.transform_to_prop("carton")
	_check(r2_capsule.form_id == "carton", "0 eaten: LARGE playable")

	var late := _make_world("LateWorld", 150.0)
	var quad: Array = [host, client_a, client_b, late]
	var peer_late := ENetMultiplayerPeer.new()
	_check(peer_late.create_client("127.0.0.1", PORT) == OK, "late client created")
	_cleanup_peers.append(peer_late)
	late.api.multiplayer_peer = peer_late
	var late_conn_pred := func() -> bool:
		return peer_late.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and late.players.get_child_count() == 4
	var late_joined := await _until(late_conn_pred, CONNECT_BUDGET)
	_check(late_joined, "mid-round joiner connected and sees all capsules")
	var late_id: int = late.api.get_unique_id()
	worlds_by_id[late_id] = late
	var spectator_pred := func() -> bool:
		for info in quad:
			var reg: Dictionary = info.gs.players
			if not reg.has(late_id):
				return false
			if reg[late_id]["role"] != info.gs.Role.NONE or reg[late_id]["alive"]:
				return false
		return info_phase_prep(quad)
	_check(await _until(spectator_pred, SYNC_BUDGET),
			"mid-round joiner registered as spectator (NONE, dead) on ALL worlds")
	var late_capsule: CharacterBody3D = late.players.get_node(str(late_id))
	late_capsule.transform_to_prop("carton")
	_check(late_capsule.form_id == "slime", "mid-round joiner cannot transform")

	# --- Round 3: the former spectator gets a real role ------------------------
	print("[three_player_round_test] round 3 with the former spectator")
	host.gs._advance_phase()  # PREP -> HUNT
	host.gs._advance_phase()  # HUNT -> END -> LOBBY + reset
	var lobby2_pred := func() -> bool:
		for info in quad:
			if info.gs.current_phase != info.gs.Phase.LOBBY:
				return false
		return true
	await _until(lobby2_pred, 8.0)
	host.gs.start_round()
	var round3_pred := func() -> bool:
		for info in quad:
			if info.gs.current_phase != info.gs.Phase.PREP:
				return false
		return _registries_agree(quad, 4)
	_check(await _until(round3_pred, SYNC_BUDGET), "round 3 running with 4 players")
	var counts3: Dictionary = _role_counts(host.gs)
	_check(counts3["seekers"] == 1 and counts3["hiders"] == 3 and counts3["none"] == 0,
			"round 3: 1 seeker + 3 hiders — the former spectator now plays")
	_check(host.gs.role_of(late_id) != host.gs.Role.NONE and host.gs.is_alive(late_id),
			"the former spectator has a real role and is alive")

	_finish()

func info_phase_prep(worlds: Array) -> bool:
	for info in worlds:
		if info.gs.current_phase != info.gs.Phase.PREP:
			return false
	return true
