extends SceneTree
## Headless multi-peer test — seeker splatter (Phase 6, feature/seeker-splatter).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/splatter_test.gd
##
## SPEC.md 11: a missed shot leaves permanent paint on the map — the seeker
## himself changes the camouflage surfaces. Splatter syncs as EVENTS
## (pos/normal/seed), never textures; every peer builds the same seeded blob
## visual. A miss landing next to a transformed alive hider additionally
## sprays that hider's prop — routed through the OWNER's own PaintSync stroke
## events, so late joiners replay it with the normal paint history.
##
## Covers: identical splatters on both peers after a floor miss, no spray on
## a far-away hider, near-miss spray landing in the hider's paint image on
## both peers, late joiner receiving splatter history AND the sprayed prop
## via paint replay, the bounded splatter cap, and the round-reset clear.
## Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const COMBAT_PATH := "res://scripts/seeker/seeker_combat.gd"
const SPLATTER_MANAGER_PATH := "res://scripts/seeker/splatter_manager.gd"
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
		printerr("[splatter_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[splatter_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[splatter_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var projectile_spawner := MultiplayerSpawner.new()
	projectile_spawner.name = "ProjectileSpawner"
	world.add_child(projectile_spawner)
	projectile_spawner.spawn_path = NodePath("../Projectiles")
	var combat: Node = (load(COMBAT_PATH) as GDScript).new()
	combat.name = "SeekerCombat"
	world.add_child(combat)
	var splatters := Node3D.new()
	splatters.name = "Splatters"
	world.add_child(splatters)
	var splatter_manager: Node = (load(SPLATTER_MANAGER_PATH) as GDScript).new()
	splatter_manager.name = "SplatterManager"
	world.add_child(splatter_manager)
	var info := {"world": world, "api": api, "gs": gs, "players": players,
			"spawner": spawner, "projectiles": projectiles, "combat": combat,
			"splatters": splatters, "splatter_manager": splatter_manager}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _splat_count(info: Dictionary) -> int:
	return info.splatters.get_child_count()

## True when the capsule's paint image holds any non-white pixel.
func _prop_painted(capsule: Node) -> bool:
	if not capsule.painter.is_painted():
		return false
	var image: Image = capsule.painter.image()
	for x in range(0, 256, 8):
		for y in range(0, 256, 8):
			if image.get_pixel(x, y) != Color(1, 1, 1, 1):
				return true
	return false

func _run_tests() -> void:
	await process_frame

	print("[splatter_test] connect host + client")
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

	host.gs.prep_seconds = 30.0
	host.gs.hunt_seconds = 30.0
	host.gs.end_seconds = 0.5
	host.gs.rotation_seconds = 30.0

	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	await _until(prep_pred, SYNC_BUDGET)
	var hider_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider_id = id
	var seeker_id: int = 1 if hider_id == client_id else client_id
	var seeker_world: Dictionary = client if seeker_id == client_id else host
	var hider_world: Dictionary = client if hider_id == client_id else host
	var seeker_own: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))
	var hider_own: CharacterBody3D = hider_world.players.get_node(str(hider_id))

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)

	# --- Miss into the floor, far from the hider -----------------------------------
	print("[splatter_test] floor miss -> identical splatter everywhere")
	seeker_own.global_position = seeker_world.world.position + Vector3(4.0, 1.0, 0.0)
	seeker_own.velocity = Vector3.ZERO
	hider_own.global_position = hider_world.world.position + Vector3(-4.0, 1.0, -4.0)
	hider_own.velocity = Vector3.ZERO
	await process_frame
	hider_own.transform_to_prop("carton")  # large — unlocked at 0 eaten
	await process_frame

	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-0.25, -1.0, 0.0))  # steep into the floor near (3.7, 0.1, 0)
	var splat_pred := func() -> bool:
		return _splat_count(host) == 1 and _splat_count(client) == 1
	var splatted := await _until(splat_pred, 3.0)
	_check(splatted, "one splatter spawned on host AND client")
	if splatted:
		var host_splat: Node3D = host.splatters.get_child(0)
		var client_splat: Node3D = client.splatters.get_child(0)
		_check(host_splat.position.distance_to(client_splat.position) < 0.05,
				"splatter positions match across peers (parent-relative)")
		_check(host_splat.get_child_count() == client_splat.get_child_count()
				and host_splat.get_child_count() > 0,
				"seeded blob layout matches across peers")
	var hider_copy_on_host: Node = host.players.get_node(str(hider_id))
	_check(not _prop_painted(hider_own) and not _prop_painted(hider_copy_on_host),
			"far-away hider caught no spray")

	# --- Near miss sprays the transformed hider's prop -------------------------------
	print("[splatter_test] near miss sprays the hider prop")
	seeker_own.global_position = seeker_world.world.position + Vector3(-1.2, 1.0, 1.6)
	seeker_own.velocity = Vector3.ZERO
	hider_own.global_position = hider_world.world.position + Vector3(-2.0, 1.0, 3.0)
	hider_own.velocity = Vector3.ZERO
	await process_frame
	# Down at the floor spot 0.8 m from the hider — the ray passes the carton.
	var aim_from := Vector3(-1.2, 2.4, 2.0)
	var target := Vector3(-1.2, 0.1, 3.0)
	seeker_world.combat.request_fire_from(seeker_id, aim_from, (target - aim_from).normalized())
	var sprayed_pred := func() -> bool:
		return _prop_painted(hider_own) and _prop_painted(hider_copy_on_host)
	var sprayed := await _until(sprayed_pred, 3.0)
	_check(sprayed, "near miss sprayed the hider's prop on BOTH peers")
	var two_splats_pred := func() -> bool:
		return _splat_count(host) == 2 and _splat_count(client) == 2
	_check(await _until(two_splats_pred, 3.0), "second splatter landed everywhere")

	# --- Late joiner: splatter history + sprayed prop via paint replay ---------------
	print("[splatter_test] late joiner")
	var late := _make_world("LateWorld", 100.0)
	var late_peer := ENetMultiplayerPeer.new()
	_check(late_peer.create_client("127.0.0.1", PORT) == OK, "late ENet client created")
	_cleanup_peers.append(late_peer)
	late.api.multiplayer_peer = late_peer
	var late_splats_pred := func() -> bool: return _splat_count(late) == 2
	_check(await _until(late_splats_pred, CONNECT_BUDGET),
			"late joiner received both splatters")
	var late_spray_pred := func() -> bool:
		var late_hider: Node = late.players.get_node_or_null(str(hider_id))
		return late_hider != null and _prop_painted(late_hider)
	_check(await _until(late_spray_pred, CONNECT_BUDGET),
			"late joiner sees the sprayed prop (paint event replay)")

	# --- Bounded history --------------------------------------------------------------
	print("[splatter_test] bounded cap")
	# The cap is a built-in bound, identical on every peer in production —
	# shrink it everywhere for the test.
	host.splatter_manager.max_splatters = 3
	client.splatter_manager.max_splatters = 3
	late.splatter_manager.max_splatters = 3
	for i in 4:
		host.splatter_manager.add_world_splatter(
				host.world.position + Vector3(-4.0 + i, 0.1, -2.0), Vector3.UP)
	var capped_pred := func() -> bool:
		return _splat_count(host) == 3 and _splat_count(client) == 3
	_check(await _until(capped_pred, 3.0),
			"cap keeps the newest splatters everywhere (3 of 6)")

	# --- Round reset clears every splatter ---------------------------------------------
	print("[splatter_test] reset clears")
	host.gs._advance_phase()  # HUNT -> END; END expires -> reset -> LOBBY
	var cleared_pred := func() -> bool:
		return _splat_count(host) == 0 and _splat_count(client) == 0 \
				and _splat_count(late) == 0
	_check(await _until(cleared_pred, 8.0), "round reset cleared splatters everywhere")

	_finish()
