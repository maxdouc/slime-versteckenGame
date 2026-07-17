extends SceneTree
## Headless multi-peer test — clone death link (Phase 9, feature/clone-death-link).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/clone_death_link_test.gd
##
## SPEC.md 10, Todes-Link (a deliberate, twice-confirmed decision): when a
## clone is destroyed, its owner dies. A paintball hitting a clone destroys
## the clone on every peer and eliminates the owner (reason "clone") through
## the Phase 5 entry — counting as a HIT for the seeker (it downed a player,
## so no cooldown). Shooting a clone whose owner is already dead just removes
## the clone and counts as a miss (cooldown starts). Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const COMBAT_PATH := "res://scripts/seeker/seeker_combat.gd"
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
		printerr("[clone_death_link_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[clone_death_link_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[clone_death_link_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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
			"spawner": spawner, "projectiles": projectiles, "combat": combat,
			"clones": clones, "manager": manager}
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

	print("[clone_death_link_test] connect host + 2 clients")
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

	host.gs.prep_seconds = 60.0
	host.gs.hunt_seconds = 60.0
	host.gs.end_seconds = 0.5
	host.gs.rotation_seconds = 60.0
	host.gs.paintball_cooldown = 0.9

	var elims: Array = []
	host.gs.player_eliminated.connect(func(id: int, reason: String) -> void:
		elims.append([id, reason]))

	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client_a.gs.current_phase == client_a.gs.Phase.PREP \
				and client_b.gs.current_phase == client_b.gs.Phase.PREP
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
	var owner_id: int = hider_ids[0]
	var owner_world: Dictionary = worlds_by_id[owner_id]
	var owner: CharacterBody3D = owner_world.players.get_node(str(owner_id))

	# Owner gets 2 eaten -> 2 clones; places them apart, then steps away.
	host.gs.record_eaten(owner_id)
	host.gs.record_eaten(owner_id)
	var eaten_pred := func() -> bool: return owner_world.gs.eaten_of(owner_id) == 2
	await _until(eaten_pred, SYNC_BUDGET)
	owner.transform_to_prop("bucket")
	await process_frame
	owner.global_position = owner_world.world.position + Vector3(-3.0, 1.0, 3.0)
	owner.velocity = Vector3.ZERO
	owner.get_node("Visual").rotation.y = 0.0  # facing -Z, deterministic
	await process_frame
	owner.place_clone()
	var one_pred := func() -> bool:
		return _clone_count(host) == 1 and _clone_count(client_a) == 1 \
				and _clone_count(client_b) == 1
	_check(await _until(one_pred, SYNC_BUDGET), "clone 1 placed everywhere")
	# The fixed placement contract offsets + floor-snaps clones, so the shots
	# below aim at the ACTUAL clone positions, not the park spots.
	var clone1_pos: Vector3 = host.clones.get_child(0).position
	var clone1_id: int = host.clones.get_child(0).clone_id
	owner.global_position = owner_world.world.position + Vector3(-3.0, 1.0, -3.0)
	owner.velocity = Vector3.ZERO
	await process_frame
	owner.place_clone()
	var two_pred := func() -> bool:
		return _clone_count(host) == 2 and _clone_count(client_a) == 2 \
				and _clone_count(client_b) == 2
	_check(await _until(two_pred, SYNC_BUDGET), "clone 2 placed everywhere")
	var clone2_pos := Vector3.ZERO
	for clone in host.clones.get_children():
		if clone.clone_id != clone1_id:
			clone2_pos = clone.position
	# Park the owner well away from both clones and the firing line.
	owner.global_position = owner_world.world.position + Vector3(-4.5, 1.0, 0.0)
	owner.velocity = Vector3.ZERO
	var bystander_world: Dictionary = worlds_by_id[hider_ids[1]]
	var bystander: CharacterBody3D = bystander_world.players.get_node(str(hider_ids[1]))
	bystander.global_position = bystander_world.world.position + Vector3(0.0, 1.0, -4.5)
	bystander.velocity = Vector3.ZERO

	host.gs._advance_phase()  # PREP -> HUNT
	var hunt_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.HUNT \
				and client_a.gs.current_phase == client_a.gs.Phase.HUNT \
				and client_b.gs.current_phase == client_b.gs.Phase.HUNT
	await _until(hunt_pred, SYNC_BUDGET)
	var seeker_world: Dictionary = worlds_by_id[seeker_id]
	var seeker_own: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))
	seeker_own.global_position = seeker_world.world.position + Vector3(4.0, 1.0, 0.0)
	seeker_own.velocity = Vector3.ZERO
	await process_frame
	await process_frame

	# --- Shot 1: the clone dies, so does its owner (Todes-Link) --------------------
	print("[clone_death_link_test] death link")
	var clone1_target := clone1_pos + Vector3(0.0, 0.275, 0.0)  # bucket center mass
	var aim_from := Vector3(4.0, 1.2, 0.0)
	seeker_world.combat.request_fire_from(seeker_id, aim_from,
			(clone1_target - aim_from).normalized())
	var linked_pred := func() -> bool:
		return not host.gs.is_alive(owner_id) \
				and _clone_count(host) == 1 and _clone_count(client_a) == 1 \
				and _clone_count(client_b) == 1
	_check(await _until(linked_pred, SYNC_BUDGET),
			"clone destroyed everywhere AND its owner eliminated")
	var reason_ok := false
	for e in elims:
		if e[0] == owner_id and e[1] == "clone":
			reason_ok = true
	_check(reason_ok, "elimination reason is 'clone'")
	_check(host.gs.current_phase == host.gs.Phase.HUNT,
			"round continues (the second hider lives)")
	_check(host.combat.cooldown_left(seeker_id) == 0.0,
			"downing a player through their clone counts as a HIT (no cooldown)")

	# --- Shot 2: a dead owner's clone is just debris --------------------------------
	print("[clone_death_link_test] dead owner's clone")
	var clone2_target := clone2_pos + Vector3(0.0, 0.275, 0.0)
	seeker_world.combat.request_fire_from(seeker_id, aim_from,
			(clone2_target - aim_from).normalized())
	var debris_pred := func() -> bool:
		return _clone_count(host) == 0 and _clone_count(client_a) == 0 \
				and _clone_count(client_b) == 0
	_check(await _until(debris_pred, SYNC_BUDGET),
			"the dead owner's clone despawned everywhere")
	_check(not host.gs.is_alive(owner_id), "the owner stays dead (no double kill)")
	_check(host.gs.is_alive(hider_ids[1]), "the bystander hider is untouched")
	var miss_pred := func() -> bool: return host.combat.cooldown_left(seeker_id) > 0.0
	_check(await _until(miss_pred, SYNC_BUDGET),
			"shooting lifeless debris counts as a MISS (cooldown started)")

	_finish()
