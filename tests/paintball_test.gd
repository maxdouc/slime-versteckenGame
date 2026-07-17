extends SceneTree
## Headless multi-peer test — paintball gun (Phase 6, feature/paintball-gun).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/paintball_test.gd
##
## SPEC.md 11: the one seeker weapon. Visible projectile, HOST-authoritative
## flight (ray-swept — no tunneling) and hit resolution; a direct hit on an
## alive hider is an immediate elimination via the Phase 5 entry
## (GameState.eliminate_player, reason "paintball"), which also fires the
## seeker-win END when the last hider falls. One projectile in flight per
## seeker (recorded decision). Fire requests are host-validated: role, phase,
## liveness, claimed id vs real sender, and origin plausibility.
##
## Worlds mirror main.tscn's Projectiles/ProjectileSpawner/SeekerCombat
## wiring. Exits 0 / 1.

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
		printerr("[paintball_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[paintball_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[paintball_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## One isolated "machine" mirroring main.tscn incl. the seeker-kit wiring.
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

func _projectile_count(info: Dictionary) -> int:
	return info.projectiles.get_child_count()

func _run_tests() -> void:
	await process_frame

	print("[paintball_test] connect host + client")
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
	host.gs.end_seconds = 0.6
	host.gs.rotation_seconds = 30.0  # rotation must not interfere
	host.gs.paintball_cooldown = 0.3  # shrunk so shot sequences stay fast

	var hits: Array = []
	var misses: Array = []
	host.combat.shot_hit.connect(func(seeker_id: int) -> void: hits.append(seeker_id))
	host.combat.shot_missed.connect(func(seeker_id: int) -> void: misses.append(seeker_id))

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
	_check(hider_id > 0, "roles assigned")

	# Park both actors at known spots (parent-relative coordinates).
	var seeker_own: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))
	var hider_own: CharacterBody3D = hider_world.players.get_node(str(hider_id))

	# --- Fire gating during PREP ---------------------------------------------------
	print("[paintball_test] gating")
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4, 1.2, 0), Vector3(-1, 0, 0))
	await _until(func() -> bool: return false, 0.4)
	_check(_projectile_count(host) == 0, "fire during PREP rejected")

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client.gs.current_phase == client.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)

	# Re-park after the HUNT teleports. The hider stands 3 m OFF the wall-shot
	# axis (z = 0) so the miss below cannot clip it by accident.
	seeker_own.global_position = seeker_world.world.position + Vector3(4.0, 1.0, 0.0)
	seeker_own.velocity = Vector3.ZERO
	hider_own.global_position = hider_world.world.position + Vector3(-3.0, 1.0, 3.0)
	hider_own.velocity = Vector3.ZERO
	await process_frame

	# The hider may not fire; a spoofed seeker id may not fire either.
	hider_world.combat.request_fire_from(hider_id, Vector3(-3, 1.2, 0), Vector3(1, 0, 0))
	hider_world.combat.request_fire.rpc_id(1, seeker_id, Vector3(4, 1.2, 0), Vector3(-1, 0, 0))
	await _until(func() -> bool: return false, 0.4)
	_check(_projectile_count(host) == 0, "hider fire AND spoofed-id fire rejected")

	# Origin far from the seeker's body is rejected (no teleport shots).
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4, 1.2, 8.0), Vector3(-1, 0, 0))
	await _until(func() -> bool: return false, 0.4)
	_check(_projectile_count(host) == 0, "implausible fire origin rejected")

	# --- Wall shot: visible flight, one-in-flight lock, miss resolution -------------
	print("[paintball_test] wall shot")
	# Down the room toward the far west wall: ~9.8 m of flight at 35 m/s.
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-1, 0, 0))
	var visible_pred := func() -> bool:
		return _projectile_count(host) == 1 and _projectile_count(client) == 1
	var seen := await _until(visible_pred, 1.0)
	_check(seen, "projectile visible on host AND client during flight")

	# Second fire while one is in flight: locked.
	seeker_world.combat.request_fire_from(seeker_id, Vector3(4.0, 1.2, 0.0),
			Vector3(-1, 0, 0))
	_check(_projectile_count(host) <= 1, "second fire rejected while one is in flight")

	var gone_pred := func() -> bool:
		return _projectile_count(host) == 0 and _projectile_count(client) == 0
	var resolved := await _until(gone_pred, 3.0)
	_check(resolved, "wall hit despawned the projectile everywhere")
	var miss_pred := func() -> bool: return misses.size() >= 1
	_check(await _until(miss_pred, SYNC_BUDGET), "shot_missed(seeker) emitted on the host")
	_check(hits.is_empty(), "no hit recorded for the wall shot")
	_check(host.gs.is_alive(hider_id), "hider unharmed by the miss")

	# --- Kill shot: direct hit eliminates and ends the round -------------------------
	print("[paintball_test] kill shot")
	await _until(func() -> bool: return false, 0.45)  # let the miss cooldown expire
	_check(host.gs.is_alive(hider_id), "hider still alive before the kill shot")
	var aim_from := Vector3(4.0, 1.2, 0.0)
	var target: Vector3 = hider_own.position + Vector3(0.0, 0.45, 0.0)  # center mass
	var dir := (target - aim_from).normalized()
	seeker_world.combat.request_fire_from(seeker_id, aim_from, dir)
	var dead_pred := func() -> bool:
		return not host.gs.is_alive(hider_id) and not client.gs.is_alive(hider_id)
	var killed := await _until(dead_pred, 3.0)
	_check(killed, "direct hit eliminated the hider on host AND client")
	var hit_pred := func() -> bool: return hits.size() >= 1
	_check(await _until(hit_pred, SYNC_BUDGET), "shot_hit(seeker) emitted on the host")
	var end_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.END \
				and host.gs.end_result.get("winner", "") == "seekers"
	_check(await _until(end_pred, SYNC_BUDGET),
			"last hider down -> seeker-win END (Phase 5 integration)")
	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	await _until(lobby_pred, 8.0)
	_check(_projectile_count(host) == 0 and _projectile_count(client) == 0,
			"no projectiles survive into the lobby")

	_finish()
