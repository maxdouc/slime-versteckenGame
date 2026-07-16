extends SceneTree
## Headless multi-peer test — clone swap-teleport (Phase 9,
## feature/clone-swap-teleport).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/clone_swap_test.gd
##
## SPEC.md 10 Tausch-Teleport: one button teleports the owner to a clone and
## consumes it — the escape anchor. V1 target selection (recorded decision):
## the MOST RECENTLY placed living clone. The jump counts as a room change
## and restarts the rotation timer IMMEDIATELY (no 5-second dwell — SPEC.md
## 10 defines the jump as a change). Form and paint stay with the player.
##
## Covers: LIFO target choice, consumption synced to every peer, form+paint
## kept, the rotation-timer reset (alive past the old deadline, dead on the
## fresh one), and the zero-clones no-op. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const CLONE_MANAGER_PATH := "res://scripts/clones/clone_manager.gd"
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
		printerr("[clone_swap_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[clone_swap_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[clone_swap_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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
	var clones := Node3D.new()
	clones.name = "Clones"
	world.add_child(clones)
	var clone_spawner := MultiplayerSpawner.new()
	clone_spawner.name = "CloneSpawner"
	world.add_child(clone_spawner)
	clone_spawner.spawn_path = NodePath("../Clones")
	var manager: Node = (load(CLONE_MANAGER_PATH) as GDScript).new()
	manager.name = "CloneManager"
	world.add_child(manager)
	var info := {"world": world, "api": api, "gs": gs, "players": players,
			"spawner": spawner, "clones": clones, "manager": manager}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _clone_count(info: Dictionary) -> int:
	return info.clones.get_child_count()

func _run_tests() -> void:
	await process_frame

	print("[clone_swap_test] connect host + client")
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

	host.gs.prep_seconds = 60.0
	host.gs.hunt_seconds = 60.0
	host.gs.end_seconds = 0.4
	host.gs.rotation_seconds = 1.2
	host.gs.rotation_dwell_seconds = 0.25
	host.gs.rotation_grace_seconds = 0.5

	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var hider_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider_id = id
	var hider_world: Dictionary = client if hider_id == client_id else host
	var other_world: Dictionary = host if hider_id == client_id else client
	var hider: CharacterBody3D = hider_world.players.get_node(str(hider_id))

	# Prep: 2 eaten, transformed, painted, TWO clones in the WEST room.
	host.gs.record_eaten(hider_id)
	host.gs.record_eaten(hider_id)
	var eaten_pred := func() -> bool: return hider_world.gs.eaten_of(hider_id) == 2
	await _until(eaten_pred, SYNC_BUDGET)
	hider.transform_to_prop("bucket")
	await process_frame
	hider.get_node("PaintSync").local_fill(Color(0.8, 0.3, 0.1))
	hider.global_position = hider_world.world.position + Vector3(-4.0, 1.0, -3.0)
	hider.velocity = Vector3.ZERO
	await process_frame
	hider.place_clone()  # clone A (older)
	var one_pred := func() -> bool:
		return _clone_count(host) == 1 and _clone_count(client) == 1
	_check(await _until(one_pred, SYNC_BUDGET), "clone A placed everywhere")
	var clone_a_id: int = host.clones.get_child(0).clone_id
	hider.global_position = hider_world.world.position + Vector3(-4.0, 1.0, 3.0)
	hider.velocity = Vector3.ZERO
	await process_frame
	hider.place_clone()  # clone B (most recent) — the LIFO swap target
	var two_pred := func() -> bool:
		return _clone_count(host) == 2 and _clone_count(client) == 2
	_check(await _until(two_pred, SYNC_BUDGET), "clone B placed everywhere")

	# Idle far away in the EAST room; the shrunk rotation timer starts there.
	hider.global_position = hider_world.world.position + Vector3(3.0, 1.0, 0.0)
	hider.velocity = Vector3.ZERO
	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)
	hider.global_position = hider_world.world.position + Vector3(3.0, 1.0, 0.0)
	hider.velocity = Vector3.ZERO
	var hunt_t0 := _elapsed

	# --- Swap near the old deadline: escape anchor (SPEC.md 10) --------------------
	print("[clone_swap_test] swap-teleport")
	await _wait(0.8)  # rotation (1.2 s) more than half spent in EAST
	hider.request_swap()
	var swapped_pred := func() -> bool:
		var own_there: bool = hider.position.distance_to(Vector3(-4.0, 1.0, 3.0)) < 0.8
		var copy: Node3D = other_world.players.get_node_or_null(str(hider_id))
		var copy_there: bool = copy != null \
				and copy.position.distance_to(Vector3(-4.0, 1.0, 3.0)) < 0.8
		return own_there and copy_there and _clone_count(host) == 1 \
				and _clone_count(client) == 1
	_check(await _until(swapped_pred, SYNC_BUDGET),
			"owner landed at clone B on BOTH peers and B was consumed")
	_check(host.clones.get_child(0).clone_id == clone_a_id,
			"the OLDER clone A survived (LIFO target selection)")
	_check(hider.form_id == "bucket", "form kept through the swap")
	_check(hider.painter.is_painted(), "paint kept through the swap")

	# --- The jump counts as a room change: the timer restarted -----------------------
	# Old deadline ~= t0 + 1.2 + 0.5 = 1.7; the swap at ~0.8 restarts it, so the
	# fresh deadline sits ~= 2.5+. Alive at 2.05 proves the reset; the fresh
	# timer must still kill an idle hider afterwards.
	while _elapsed < hunt_t0 + 2.05 and not _done:
		await process_frame
	_check(host.gs.is_alive(hider_id),
			"hider alive past the OLD deadline (swap reset the rotation timer)")
	var dead_pred := func() -> bool: return not host.gs.is_alive(hider_id)
	_check(await _until(dead_pred, 3.5), "…but the FRESH timer still ran out (no immunity)")

	# --- Round 2: zero clones -> the swap is a calm no-op -----------------------------
	print("[clone_swap_test] zero-clones no-op")
	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	if host.gs.current_phase == host.gs.Phase.HUNT:
		host.gs._advance_phase()
	await _until(lobby_pred, 8.0)
	host.gs.rotation_seconds = 60.0  # rotation must not interfere here
	host.gs.start_round()
	await _until(prep_pred, SYNC_BUDGET)
	var hider2_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider2_id = id
	var hider2_world: Dictionary = client if hider2_id == client_id else host
	var hider2: CharacterBody3D = hider2_world.players.get_node(str(hider2_id))
	hider2.global_position = hider2_world.world.position + Vector3(2.0, 1.0, 2.0)
	hider2.velocity = Vector3.ZERO
	await _wait(0.3)
	var before: Vector3 = hider2.position
	hider2.request_swap()
	await _wait(0.6)
	# Horizontal comparison only — the freshly parked capsule is still
	# settling onto the floor (y sinks), which is not a teleport.
	var drift := Vector2(hider2.position.x - before.x, hider2.position.z - before.z)
	_check(drift.length() < 0.3,
			"swap with zero clones is a no-op (no teleport, no crash)")

	_finish()
