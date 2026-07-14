extends SceneTree
## Headless multi-peer test — spectator mode (Phase 6, feature/spectator-mode).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/spectator_test.gd
##
## SPEC.md 5.3: eliminated players get a free spectator camera and a text
## chat only the dead can read (no voice in V1). This branch owns exactly
## that per the recorded overlap resolution — elimination behavior itself
## came with feature/win-lose-reset.
##
## Three peers (1 seeker, 2 hiders) so one elimination leaves the round
## running. Covers: the dead player's OWN machine spawns a free-fly rig
## (alive machines never do), dead chat reaches only dead peers (the alive
## seeker receives nothing, a live hider receives nothing, alive senders are
## rejected), both dead peers chat during END, and the round reset removes
## the rig again. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const DEAD_CHAT_PATH := "res://scripts/round/dead_chat.gd"
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
		printerr("[spectator_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[spectator_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[spectator_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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
	var chat: Node = (load(DEAD_CHAT_PATH) as GDScript).new()
	chat.name = "DeadChat"
	world.add_child(chat)
	var info := {"world": world, "api": api, "gs": gs, "players": players,
			"spawner": spawner, "chat": chat, "inbox": []}
	chat.message_received.connect(func(from_id: int, text: String) -> void:
		info.inbox.append([from_id, text]))
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _rig_count(info: Dictionary) -> int:
	var count := 0
	for child in info.world.get_children():
		if str(child.name).begins_with("SpectatorCamera"):
			count += 1
	return count

func _run_tests() -> void:
	await process_frame

	print("[spectator_test] connect host + 2 clients")
	var host := _make_world("HostWorld", 0.0)
	var client_a := _make_world("ClientA", 50.0)
	var client_b := _make_world("ClientB", 100.0)

	var host_peer := ENetMultiplayerPeer.new()
	_check(host_peer.create_server(PORT, 8) == OK, "ENet server listening on %d" % PORT)
	_cleanup_peers.append(host_peer)
	host.api.multiplayer_peer = host_peer
	_host_spawn_slot = 1
	host.api.peer_connected.connect(func(id: int) -> void:
		host.spawner.spawn([id, Vector3(2.0 * _host_spawn_slot, 1.0, 0.0)])
		_host_spawn_slot += 1)
	host.spawner.spawn([1, Vector3(0.0, 1.0, 0.0)])

	for info in [client_a, client_b]:
		var peer := ENetMultiplayerPeer.new()
		_check(peer.create_client("127.0.0.1", PORT) == OK, "ENet client created")
		_cleanup_peers.append(peer)
		info.api.multiplayer_peer = peer

	var all_spawned_pred := func() -> bool:
		return host.players.get_child_count() == 3 \
				and client_a.players.get_child_count() == 3 \
				and client_b.players.get_child_count() == 3
	var all_spawned := await _until(all_spawned_pred, CONNECT_BUDGET)
	_check(all_spawned, "all three worlds spawned all three capsules")
	if not all_spawned:
		_check(false, "no trio — aborting")
		_finish()
		return

	host.gs.prep_seconds = 30.0
	host.gs.hunt_seconds = 30.0
	host.gs.end_seconds = 2.5  # long enough to chat during END
	host.gs.rotation_seconds = 30.0

	host.gs.start_round()
	var prep_pred := func() -> bool: return host.gs.current_phase == host.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var seeker_id := -1
	var hider_ids: Array = []
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.SEEKER:
			seeker_id = id
		else:
			hider_ids.append(id)
	_check(seeker_id > 0 and hider_ids.size() == 2, "1 seeker + 2 hiders assigned")

	var worlds_by_id := {1: host,
			client_a.api.get_unique_id(): client_a,
			client_b.api.get_unique_id(): client_b}
	var seeker_world: Dictionary = worlds_by_id[seeker_id]
	var world_a: Dictionary = worlds_by_id[hider_ids[0]]
	var world_b: Dictionary = worlds_by_id[hider_ids[1]]

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool: return host.gs.current_phase == host.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)

	# --- Eliminate hider A: only A's machine grows a free camera ------------------
	print("[spectator_test] free camera for the dead")
	host.gs.eliminate_player(hider_ids[0], "paintball")
	var rig_pred := func() -> bool: return _rig_count(world_a) == 1
	_check(await _until(rig_pred, SYNC_BUDGET),
			"the dead hider's OWN machine spawned the spectator rig")
	_check(_rig_count(seeker_world) == 0 and _rig_count(world_b) == 0,
			"alive machines run no spectator rig")

	# --- Dead chat: only the dead read it ------------------------------------------
	print("[spectator_test] dead-only chat")
	world_a.chat.send("hallo aus dem jenseits")
	var a_heard_pred := func() -> bool: return world_a.inbox.size() == 1
	_check(await _until(a_heard_pred, SYNC_BUDGET), "dead sender got its own line back")
	await _wait(0.4)  # give any wrong delivery time to arrive
	_check(seeker_world.inbox.is_empty(), "the alive seeker heard nothing")
	_check(world_b.inbox.is_empty(), "the alive hider heard nothing")

	# An alive player cannot use the dead channel.
	seeker_world.chat.send("psst")
	await _wait(0.4)
	_check(world_a.inbox.size() == 1, "alive sender rejected (nothing delivered)")

	# --- Second elimination -> END; both dead peers chat ---------------------------
	print("[spectator_test] END: both dead peers share the channel")
	host.gs.eliminate_player(hider_ids[1], "paintball")
	var end_pred := func() -> bool: return host.gs.current_phase == host.gs.Phase.END
	_check(await _until(end_pred, SYNC_BUDGET), "last hider down -> END")
	var rig_b_pred := func() -> bool: return _rig_count(world_b) == 1
	_check(await _until(rig_b_pred, SYNC_BUDGET), "second dead machine got a rig too")
	world_b.chat.send("bin auch tot")
	var both_heard_pred := func() -> bool:
		return world_a.inbox.size() == 2 and world_b.inbox.size() == 1
	_check(await _until(both_heard_pred, SYNC_BUDGET),
			"END chat reached BOTH dead peers")
	_check(world_a.inbox[1][0] == hider_ids[1], "the line carries the sender id")
	_check(seeker_world.inbox.is_empty(), "the seeker still heard nothing")

	# --- Reset removes the rigs ------------------------------------------------------
	print("[spectator_test] reset cleanup")
	var lobby_pred := func() -> bool: return host.gs.current_phase == host.gs.Phase.LOBBY
	await _until(lobby_pred, 8.0)
	var rigs_gone_pred := func() -> bool:
		return _rig_count(world_a) == 0 and _rig_count(world_b) == 0
	_check(await _until(rigs_gone_pred, SYNC_BUDGET), "reset removed every spectator rig")

	_finish()
