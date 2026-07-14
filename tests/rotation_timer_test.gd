extends SceneTree
## Headless multi-peer test — rotation timer (Phase 5, feature/rotation-timer).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/rotation_timer_test.gd
##
## SPEC.md 6, the core identity: a per-hider timer starts on room entry and
## only runs during HUNT. A room change counts after 5 s continuous stay in
## the new room (the old timer keeps running meanwhile). On expiry the slime
## loses cohesion — a growing puddle (replicated to every peer) — and after a
## 10 s grace the player is eliminated (data layer: registry alive=false +
## player_eliminated signal; the full death behavior is feature/win-lose-reset).
##
## Timings are host settings, so this test also proves the settings broadcast:
## the tracker runs on the HIDER's machine with the HOST's shrunk values.
## Assertions are event-order based (alive before X / dead after Y) rather
## than tight wall-clock walls, to stay robust in headless runs. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const ROOM_VOLUME_PATH := "res://scripts/round/room_volume.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 150.0

const WEST := Vector3(-3.0, 1.0, 0.0)
const EAST := Vector3(3.0, 1.0, 0.0)

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
		printerr("[rotation_timer_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[rotation_timer_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[rotation_timer_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## Real-time wait (frame-driven), used where NOT changing is the assertion.
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
	var info := {"world": world, "api": api, "gs": gs, "players": players, "spawner": spawner}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

## Start a fresh round from LOBBY and force it into HUNT with the hider
## parked at `start_pos` (world-local). Returns the hider id.
func _start_hunt_round(host: Dictionary, client: Dictionary, start_pos: Vector3) -> int:
	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var hider_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider_id = id
	var hider_world: Dictionary = client if hider_id == client.api.get_unique_id() else host
	var capsule: CharacterBody3D = hider_world.players.get_node(str(hider_id))
	capsule.global_position = hider_world.world.position + start_pos
	capsule.velocity = Vector3.ZERO
	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)
	# Re-park after any role teleports (roles_assigned may have moved it).
	capsule.global_position = hider_world.world.position + start_pos
	capsule.velocity = Vector3.ZERO
	return hider_id

func _end_round(host: Dictionary, client: Dictionary) -> void:
	if host.gs.current_phase == host.gs.Phase.HUNT:
		host.gs._advance_phase()  # HUNT -> END
	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	await _until(lobby_pred, 8.0)

func _run_tests() -> void:
	await process_frame

	# --- Scene contract: two room volumes cover the gray room -------------------
	print("[rotation_timer_test] room volumes")
	var volume_script: GDScript = load(ROOM_VOLUME_PATH)
	_check(volume_script != null, "room_volume.gd exists")
	var room_probe: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room_probe)
	await process_frame
	var volumes: Array = []
	for child in room_probe.find_children("*", "Area3D", true, false):
		if child.is_in_group("room_volume"):
			volumes.append(child)
	_check(volumes.size() >= 2, "gray room has >= 2 room volumes (%d)" % volumes.size())
	var ids := {}
	for volume in volumes:
		ids[volume.room_id] = true
	_check(ids.size() == volumes.size(), "room ids are unique")
	var west_room := ""
	var east_room := ""
	for volume in volumes:
		if volume.contains_global(WEST):
			west_room = volume.room_id
		if volume.contains_global(EAST):
			east_room = volume.room_id
	_check(west_room != "", "a volume contains the west probe point")
	_check(east_room != "", "a volume contains the east probe point")
	_check(west_room != east_room, "west and east probes land in different rooms")
	root.remove_child(room_probe)
	room_probe.free()

	# --- Connect host + client ---------------------------------------------------
	print("[rotation_timer_test] connect host + client")
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

	# Host-side settings — shrunk. The hider's tracker may live on the CLIENT,
	# so these values must reach it through the settings broadcast.
	host.gs.prep_seconds = 30.0
	host.gs.hunt_seconds = 30.0
	host.gs.end_seconds = 0.2
	host.gs.rotation_seconds = 1.0
	host.gs.rotation_dwell_seconds = 0.25
	host.gs.rotation_grace_seconds = 0.4

	var host_elims: Array = []
	var client_elims: Array = []
	host.gs.player_eliminated.connect(func(id: int, reason: String) -> void:
		host_elims.append([id, reason]))
	client.gs.player_eliminated.connect(func(id: int, reason: String) -> void:
		client_elims.append([id, reason]))

	# --- Round 1: idle in one room -> drip -> elimination -------------------------
	print("[rotation_timer_test] round 1: idle expiry eliminates")
	var hider_id: int = await _start_hunt_round(host, client, WEST)
	_check(client.gs.rotation_seconds == 1.0 and client.gs.rotation_grace_seconds == 0.4,
			"host settings reached the client (settings broadcast)")
	var seeker_id: int = 1 if hider_id == client_id else client_id

	# During grace the puddle must be visible on the OTHER machine too.
	var observer_world: Dictionary = host if hider_id == client_id else client
	var drip_pred := func() -> bool:
		var copy: Node = observer_world.players.get_node_or_null(str(hider_id))
		return copy != null and copy.rotation_drip > 0.05
	var drip_seen := await _until(drip_pred, 3.0)
	_check(drip_seen, "grace drip replicated to the observing peer")

	var dead_pred := func() -> bool:
		return not host.gs.is_alive(hider_id) and not client.gs.is_alive(hider_id)
	var died := await _until(dead_pred, 3.0)
	_check(died, "idle hider eliminated on host AND client")
	_check(host_elims.size() == 1 and host_elims[0][0] == hider_id \
			and host_elims[0][1] == "rotation",
			"host emitted player_eliminated(hider, rotation)")
	_check(client_elims.size() == 1 and client_elims[0][1] == "rotation",
			"client emitted player_eliminated too")
	_check(host.gs.is_alive(seeker_id), "the seeker is untouched by rotation")
	await _end_round(host, client)
	host_elims.clear()
	client_elims.clear()

	# --- Round 2: room change past the dwell resets the timer ---------------------
	print("[rotation_timer_test] round 2: confirmed room change resets")
	hider_id = await _start_hunt_round(host, client, WEST)
	var hider_world: Dictionary = client if hider_id == client_id else host
	var capsule: CharacterBody3D = hider_world.players.get_node(str(hider_id))
	var hunt_t0 := _elapsed
	await _wait(0.5)  # half the rotation budget spent in WEST
	capsule.global_position = hider_world.world.position + EAST  # move to EAST
	capsule.velocity = Vector3.ZERO
	# Old-timer deadline would be t0 + 1.0 + 0.4 = 1.4. Confirmation lands at
	# ~0.75; the fresh deadline is ~0.75 + 1.4 = 2.15. Probe at 1.7: must live.
	while _elapsed < hunt_t0 + 1.7 and not _done:
		await process_frame
	_check(host.gs.is_alive(hider_id),
			"hider still alive 0.3 s past the OLD deadline (timer was reset)")
	var died2 := await _until(dead_pred, 3.0)
	_check(died2, "…but the fresh timer still kills an idle hider eventually")
	await _end_round(host, client)
	host_elims.clear()
	client_elims.clear()

	# --- Round 3: a door-sill bounce does NOT reset --------------------------------
	print("[rotation_timer_test] round 3: bounce inside the dwell does not reset")
	hider_id = await _start_hunt_round(host, client, WEST)
	hider_world = client if hider_id == client_id else host
	capsule = hider_world.players.get_node(str(hider_id))
	var t0 := _elapsed
	await _wait(0.1)
	capsule.global_position = hider_world.world.position + EAST  # into EAST…
	capsule.velocity = Vector3.ZERO
	await _wait(0.1)  # …for only 0.1 s (dwell is 0.25)
	capsule.global_position = hider_world.world.position + WEST  # bounce back
	capsule.velocity = Vector3.ZERO
	# No reset: death by roughly t0 + 1.4 (+ sync slack). Assert dead by 2.4.
	var died3 := await _until(dead_pred, 3.0)
	var death_moment := _elapsed
	_check(died3, "bouncing hider still eliminated")
	_check(death_moment - t0 < 2.4,
			"death arrived on the ORIGINAL schedule (%.2f s — no dwell reset)" % (death_moment - t0))
	await _end_round(host, client)
	host_elims.clear()
	client_elims.clear()

	# --- Round 4: PREP is rotation-free -------------------------------------------
	print("[rotation_timer_test] round 4: no rotation pressure during PREP")
	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var prep_hider := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			prep_hider = id
	var prep_world: Dictionary = client if prep_hider == client_id else host
	var prep_capsule: CharacterBody3D = prep_world.players.get_node(str(prep_hider))
	prep_capsule.global_position = prep_world.world.position + WEST
	prep_capsule.velocity = Vector3.ZERO
	await _wait(2.0)  # well past rotation (1.0) + grace (0.4)
	_check(host.gs.is_alive(prep_hider), "hider alive after 2 s idling in PREP")
	_check(prep_capsule.rotation_drip == 0.0, "no drip during PREP")

	# The tracker exposes the Phase 9 swap-teleport hook.
	var tracker: Node = prep_capsule.get_node_or_null("RotationTracker")
	_check(tracker != null, "capsule carries a RotationTracker node")
	_check(tracker != null and tracker.has_method("reset_timer"),
			"tracker exposes reset_timer() (clone swap-teleport consumes it)")
	await _end_round(host, client)

	_finish()
