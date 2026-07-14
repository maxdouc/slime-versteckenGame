extends SceneTree
## Headless multi-peer test — win/lose/reset (Phase 5, feature/win-lose-reset).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/win_lose_reset_test.gd
##
## SPEC.md 5.3: seekers win when every hider is eliminated before the hunt
## ends; each surviving hider wins individually (no score); eliminated players
## become ghosts (invisible, non-colliding, input-dead — the free spectator
## camera is Phase 6); every round ends in a COMPLETE reset (forms, paint,
## eaten, registry) back to the lobby. This branch owns elimination BEHAVIOR,
## win conditions, round end, and the reset (recorded overlap resolution).
##
## Covers: seeker win by elimination (host-side eliminate_player — the exact
## entry Phase 6's paintball uses), replicated end result, cross-peer ghosting,
## hider win by surviving the hunt with a survivor list, elimination rejected
## outside HUNT, the round_reset broadcast un-ghosting + re-slime-ing everyone
## with a cleared registry, and the disconnect win check. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const FORMS_PATH := "res://scripts/player_forms.gd"
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
		printerr("[win_lose_reset_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[win_lose_reset_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[win_lose_reset_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

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

func _hider_of(gs: Node) -> int:
	for id in gs.players:
		if gs.players[id]["role"] == gs.Role.HIDER:
			return id
	return -1

func _run_tests() -> void:
	await process_frame
	var forms: GDScript = load(FORMS_PATH)

	print("[win_lose_reset_test] connect host + client")
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
		_check(false, "no connected pair — aborting")
		_finish()
		return

	host.gs.prep_seconds = 30.0
	host.gs.hunt_seconds = 30.0
	host.gs.end_seconds = 0.4
	host.gs.rotation_seconds = 30.0  # rotation must not interfere here

	var host_resets := [0]
	var client_resets := [0]
	host.gs.round_reset.connect(func() -> void: host_resets[0] += 1)
	client.gs.round_reset.connect(func() -> void: client_resets[0] += 1)

	# --- Round A: seekers win by eliminating the last hider ----------------------
	print("[win_lose_reset_test] round A: elimination -> seeker win -> reset")
	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var hider_id := _hider_of(host.gs)
	_check(hider_id > 0, "found the hider")

	# Elimination outside HUNT must be rejected.
	host.gs.eliminate_player(hider_id, "paintball")
	await process_frame
	_check(host.gs.is_alive(hider_id) and host.gs.current_phase == host.gs.Phase.PREP,
			"eliminate_player during PREP rejected")

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)

	host.gs.eliminate_player(hider_id, "paintball")  # the Phase 6 entry point
	var end_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.END \
				and client.gs.current_phase == client.gs.Phase.END
	var ended := await _until(end_pred, SYNC_BUDGET)
	_check(ended, "last hider eliminated -> END on host AND client")
	_check(host.gs.end_result.get("winner", "") == "seekers", "host result: seekers win")
	_check(client.gs.end_result.get("winner", "") == "seekers", "client result: seekers win")
	_check(client.gs.end_result.get("survivors", [1]).is_empty(), "no survivors listed")

	# The dead hider is a ghost on BOTH machines.
	var ghost_pred := func() -> bool:
		var own: Node3D = host.players.get_node_or_null(str(hider_id))
		var twin: Node3D = client.players.get_node_or_null(str(hider_id))
		return own != null and twin != null \
				and not own.visible and not twin.visible \
				and own.collision_layer == 0 and twin.collision_layer == 0
	var ghosted := await _until(ghost_pred, SYNC_BUDGET)
	_check(ghosted, "eliminated hider ghosted (invisible, non-colliding) on both peers")

	# END expires -> LOBBY with the COMPLETE reset (SPEC.md 5.3).
	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	var reset_done := await _until(lobby_pred, 8.0)
	_check(reset_done, "END expired into LOBBY on both peers")
	_check(host_resets[0] == 1 and client_resets[0] == 1,
			"round_reset broadcast reached both peers exactly once")
	_check(host.gs.players.is_empty() and client.gs.players.is_empty(),
			"registry cleared for the lobby")
	var unghost_pred := func() -> bool:
		var own: Node3D = host.players.get_node_or_null(str(hider_id))
		var twin: Node3D = client.players.get_node_or_null(str(hider_id))
		return own != null and twin != null and own.visible and twin.visible \
				and own.collision_layer == 1 and twin.collision_layer == 1
	var unghosted := await _until(unghost_pred, SYNC_BUDGET)
	_check(unghosted, "ghost lifted everywhere after the reset")
	var slime_pred := func() -> bool:
		var own: Node = host.players.get_node_or_null(str(hider_id))
		return own != null and own.form_id == forms.SLIME
	_check(await _until(slime_pred, SYNC_BUDGET), "everyone back to slime after the reset")

	# --- Round B: hiders win by surviving the hunt --------------------------------
	print("[win_lose_reset_test] round B: survival -> individual hider win")
	host.gs.hunt_seconds = 0.8
	host.gs.start_round()
	await _until(prep_pred, SYNC_BUDGET)
	_check(host.gs.end_result.is_empty() and client.gs.end_result.is_empty(),
			"a new round clears the previous end result")
	var hider_b := _hider_of(host.gs)
	host.gs._advance_phase()  # PREP -> HUNT; the 0.8 s hunt then runs out
	var ended_b := await _until(end_pred, SYNC_BUDGET)
	_check(ended_b, "hunt expiry -> END on both peers")
	_check(host.gs.end_result.get("winner", "") == "hiders", "host result: hiders win")
	_check(client.gs.end_result.get("winner", "") == "hiders", "client result: hiders win")
	var survivors: Array = client.gs.end_result.get("survivors", [])
	_check(survivors == [hider_b], "the surviving hider is listed individually")
	_check(host.gs.is_alive(hider_b), "the survivor is alive")
	await _until(lobby_pred, 8.0)
	_check(host_resets[0] == 2 and client_resets[0] == 2, "second reset arrived on both")

	# --- Round C: a hider's disconnect ends the round for the seekers -------------
	print("[win_lose_reset_test] round C: hider disconnect -> seeker win")
	host.gs.hunt_seconds = 30.0
	var got_client_hider := false
	var attempts := 0
	while not got_client_hider and attempts < 10 and not _done:
		attempts += 1
		host.gs.start_round()
		await _until(prep_pred, SYNC_BUDGET)
		if _hider_of(host.gs) == client_id:
			got_client_hider = true
		else:
			host.gs._advance_phase()
			host.gs._advance_phase()
			await _until(lobby_pred, 8.0)
	_check(got_client_hider, "role lottery produced a client hider within %d rounds" % attempts)
	if got_client_hider:
		host.gs._advance_phase()  # PREP -> HUNT
		var host_hunt_pred := func() -> bool:
			return host.gs.current_phase == host.gs.Phase.HUNT
		await _until(host_hunt_pred, SYNC_BUDGET)
		client_peer.close()
		client.api.multiplayer_peer = null
		var host_end_pred := func() -> bool:
			return host.gs.current_phase == host.gs.Phase.END
		var ended_c := await _until(host_end_pred, CONNECT_BUDGET)
		_check(ended_c, "host ended the round when the last hider disconnected")
		_check(host.gs.end_result.get("winner", "") == "seekers",
				"disconnect counts as a seeker win")

	_finish()
