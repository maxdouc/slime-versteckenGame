extends SceneTree
## Headless multi-peer test — seeker cooldown (Phase 6, feature/seeker-cooldown).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/cooldown_test.gd
##
## SPEC.md 11, spec-literal: the miss penalty is ONLY a cooldown (default 4 s,
## host-adjustable via GameState.paintball_cooldown). A HIT ends the in-flight
## lock with no cooldown — the next shot may fly immediately. Host-enforced.
##
## Three players (1 seeker, 2 hiders) so a hit does not end the round.
## Covers: miss starts the cooldown (re-fire rejected, cooldown_left > 0),
## expiry re-arms, a hit does NOT cool down (instant follow-up accepted), and
## the value really comes from the GameState setting. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const COMBAT_PATH := "res://scripts/seeker/seeker_combat.gd"
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
		printerr("[cooldown_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[cooldown_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[cooldown_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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
	var info := {"world": world, "api": api, "gs": gs, "players": players,
			"spawner": spawner, "projectiles": projectiles, "combat": combat}
	_worlds.append(info)
	return info

func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _run_tests() -> void:
	await process_frame

	print("[cooldown_test] connect host + 2 clients")
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
	host.gs.end_seconds = 0.5
	host.gs.rotation_seconds = 30.0
	host.gs.paintball_cooldown = 0.5  # host setting — the ONLY value that counts

	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP
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
	var seeker_own: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)

	# Park everyone at known spots: seeker east, hiders west, off each axis.
	seeker_own.global_position = seeker_world.world.position + Vector3(4.0, 1.0, 0.0)
	seeker_own.velocity = Vector3.ZERO
	var hider_a_world: Dictionary = worlds_by_id[hider_ids[0]]
	var hider_a: CharacterBody3D = hider_a_world.players.get_node(str(hider_ids[0]))
	hider_a.global_position = hider_a_world.world.position + Vector3(-3.0, 1.0, 3.0)
	hider_a.velocity = Vector3.ZERO
	var hider_b_world: Dictionary = worlds_by_id[hider_ids[1]]
	var hider_b: CharacterBody3D = hider_b_world.players.get_node(str(hider_ids[1]))
	hider_b.global_position = hider_b_world.world.position + Vector3(-3.0, 1.0, -3.0)
	hider_b.velocity = Vector3.ZERO
	await process_frame
	await process_frame

	# --- Miss -> cooldown -----------------------------------------------------------
	print("[cooldown_test] miss starts the cooldown")
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-0.3, -1.0, 0.0))  # into the floor, away from both hiders
	var missed_pred := func() -> bool:
		return host.projectiles.get_child_count() == 0 \
				and host.combat.cooldown_left(seeker_id) > 0.0
	var missed := await _until(missed_pred, 3.0)
	_check(missed, "miss resolved and the cooldown ledger is running")

	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-0.3, -1.0, 0.0))
	await _wait(0.25)
	_check(host.projectiles.get_child_count() == 0, "re-fire during cooldown rejected")

	await _wait(0.5)  # the 0.5 s host cooldown has expired by now
	_check(host.combat.cooldown_left(seeker_id) == 0.0, "cooldown expired on schedule")
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-0.3, -1.0, 0.0))
	var refired_pred := func() -> bool: return host.projectiles.get_child_count() == 1
	_check(await _until(refired_pred, 2.0), "fire accepted after the cooldown")
	var resolved_pred := func() -> bool: return host.projectiles.get_child_count() == 0
	await _until(resolved_pred, 3.0)
	await _wait(0.7)  # let that miss's cooldown expire too

	# --- Hit -> NO cooldown (spec-literal: Fehlschuss = Cooldown) ---------------------
	print("[cooldown_test] hit does not cool down")
	var aim_from := Vector3(4.0, 1.2, 0.0)
	var target: Vector3 = hider_a.position + Vector3(0.0, 0.45, 0.0)
	seeker_world.combat.request_fire_from(seeker_id, aim_from, (target - aim_from).normalized())
	var hit_pred := func() -> bool:
		return not host.gs.is_alive(hider_ids[0]) \
				and host.projectiles.get_child_count() == 0
	var hit := await _until(hit_pred, 3.0)
	_check(hit, "direct hit eliminated hider A (round continues: hider B lives)")
	_check(host.gs.current_phase == host.gs.Phase.HUNT, "round still running after one kill")
	_check(host.combat.cooldown_left(seeker_id) == 0.0, "NO cooldown after a hit")
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-0.3, -1.0, 0.0))
	var instant_pred := func() -> bool: return host.projectiles.get_child_count() == 1
	_check(await _until(instant_pred, 2.0), "instant follow-up shot accepted after the hit")

	_finish()
