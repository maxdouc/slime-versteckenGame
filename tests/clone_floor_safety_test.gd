extends SceneTree
## Headless multi-peer test — floor-safe clone placement + swap landing
## (fix/phase-5-9-manual-validation, defect 1 regression).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/clone_floor_safety_test.gd
##
## Manual validation found: clones spawned exactly at the placer's position,
## overlapping the placer's body — move_and_slide depenetration then shoved
## the player unpredictably, including THROUGH the 0.2 m floor slabs. Swap
## teleported into the not-yet-freed clone collision with the same shove.
## Nothing floor-validated any y, so buried positions propagated.
##
## The fixed contract, covered here for ALL prop sizes:
##   * the clone appears PLACE_OFFSET in front of the placer's facing,
##     floor-snapped: base = first walkable surface below (+ epsilon)
##   * placement never displaces the placer (no overlap by construction)
##   * a blocked spot (existing clone/wall/player) rejects the placement
##   * swap lands the owner exactly at the clone's floor-safe base and the
##     player NEVER ends below the floor — including repeated place/swap
##   * both peers agree on every clone and landing position
##
## Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const CLONE_MANAGER_PATH := "res://scripts/clones/clone_manager.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 170.0

## gray_room floor: 0.2 box centered at y 0 -> top at +0.1 (parent-relative,
## Players/Clones sit at the world root).
const FLOOR_TOP := 0.1
const PLACE_OFFSET := 1.3  # must match clone_manager.gd

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
		printerr("[clone_floor_safety_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[clone_floor_safety_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[clone_floor_safety_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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

## Park the hider, zero its yaw (facing -Z) and wait until it stands on the
## floor — every placement in this test starts from a SETTLED body.
func _park_settled(hider: CharacterBody3D, world: Dictionary, spot: Vector3) -> bool:
	hider.global_position = world.world.position + spot
	hider.velocity = Vector3.ZERO
	hider.get_node("Visual").rotation.y = 0.0
	var settled := func() -> bool: return hider.is_on_floor()
	return await _until(settled, SYNC_BUDGET)

func _run_tests() -> void:
	await process_frame

	print("[clone_floor_safety_test] connect host + client")
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

	host.gs.prep_seconds = 120.0
	host.gs.hunt_seconds = 60.0
	host.gs.end_seconds = 0.4
	host.gs.rotation_seconds = 60.0  # rotation must never interfere here

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

	# 2 eaten -> all sizes unlocked (SPEC.md 8) and a clone budget of 2.
	host.gs.record_eaten(hider_id)
	host.gs.record_eaten(hider_id)
	var eaten_pred := func() -> bool: return hider_world.gs.eaten_of(hider_id) == 2
	await _until(eaten_pred, SYNC_BUDGET)

	# --- Every prop size: placement is offset, floor-snapped, shove-free ------
	var spots := {
		"carton": Vector3(-4.0, 1.0, -3.0),
		"bucket": Vector3(0.0, 1.0, -3.0),
		"cup": Vector3(4.0, 1.0, -3.0),
	}
	for form_id in spots:
		print("[clone_floor_safety_test] placement + swap: ", form_id)
		var spot: Vector3 = spots[form_id]
		_check(await _park_settled(hider, hider_world, spot),
				"%s: hider settled on the floor" % form_id)
		hider.transform_to_prop(form_id)
		await process_frame
		var count_before := _clone_count(host)
		hider.place_clone()
		var placed_pred := func() -> bool:
			return _clone_count(host) == count_before + 1 \
					and _clone_count(client) == count_before + 1
		_check(await _until(placed_pred, SYNC_BUDGET),
				"%s: clone placed on BOTH peers" % form_id)
		if _clone_count(host) != count_before + 1:
			continue
		var newest: Node3D = host.clones.get_child(host.clones.get_child_count() - 1)
		# Facing -Z (yaw 0) -> the clone stands PLACE_OFFSET in front.
		var expected := Vector3(spot.x, FLOOR_TOP, spot.z - PLACE_OFFSET)
		var flat_err := Vector2(newest.position.x - expected.x,
				newest.position.z - expected.z).length()
		_check(flat_err < 0.15,
				"%s: clone offset in front of the placer (err %.2f m)" % [form_id, flat_err])
		_check(absf(newest.position.y - FLOOR_TOP) < 0.08,
				"%s: clone base floor-snapped (y=%.3f)" % [form_id, newest.position.y])
		# The placer must NOT be displaced by its own clone (the old shove).
		var before_pos: Vector3 = hider.position
		await _wait(0.6)
		var shove := Vector2(hider.position.x - before_pos.x,
				hider.position.z - before_pos.z).length()
		_check(shove < 0.1 and hider.position.y > FLOOR_TOP - 0.05,
				"%s: placer not shoved by its clone (drift %.2f m, y=%.3f)"
				% [form_id, shove, hider.position.y])

		# --- Swap: land exactly at the clone's floor-safe base, never below ---
		var landing_expected: Vector3 = newest.position
		hider.request_swap()
		var swapped_pred := func() -> bool:
			return _clone_count(host) == count_before \
					and _clone_count(client) == count_before
		_check(await _until(swapped_pred, SYNC_BUDGET),
				"%s: swap consumed the clone on BOTH peers" % form_id)
		# Sample the owner every frame for a second: below-floor is an
		# instant failure even if it recovers later.
		var min_y := hider.position.y
		var sample_deadline := _elapsed + 1.0
		while _elapsed < sample_deadline and not _done:
			min_y = minf(min_y, hider.position.y)
			await process_frame
		_check(min_y > FLOOR_TOP - 0.08,
				"%s: owner NEVER dipped below the floor (min y=%.3f)" % [form_id, min_y])
		var land_err := Vector2(hider.position.x - landing_expected.x,
				hider.position.z - landing_expected.z).length()
		_check(land_err < 0.15,
				"%s: owner landed at the clone spot (err %.2f m)" % [form_id, land_err])
		var copy: Node3D = other_world.players.get_node_or_null(str(hider_id))
		_check(copy != null and copy.position.y > FLOOR_TOP - 0.15,
				"%s: remote copy also on the floor" % form_id)

	# --- A blocked spot rejects the placement (overlap protection) ------------
	print("[clone_floor_safety_test] blocked spot")
	_check(await _park_settled(hider, hider_world, Vector3(-4.0, 1.0, 3.0)),
			"blocked: hider settled on the floor")
	hider.transform_to_prop("carton")
	await process_frame
	var base_count := _clone_count(host)
	hider.place_clone()
	var first_pred := func() -> bool:
		return _clone_count(host) == base_count + 1 \
				and _clone_count(client) == base_count + 1
	_check(await _until(first_pred, SYNC_BUDGET), "blocked: first clone placed")
	hider.place_clone()  # same spot — must be REJECTED, not stacked
	await _wait(1.0)
	_check(_clone_count(host) == base_count + 1 and _clone_count(client) == base_count + 1,
			"blocked: second clone on the SAME spot was rejected")

	# --- Repeated place/swap cycles never bury the player ---------------------
	print("[clone_floor_safety_test] repeated place/swap cycles")
	var cycle_spots: Array = [
		Vector3(-2.0, 1.0, 4.0), Vector3(0.0, 1.0, 4.0),
		Vector3(2.0, 1.0, 4.0), Vector3(4.0, 1.0, 4.0),
	]
	var cycles_ok := true
	var worst_y := 10.0
	for i in cycle_spots.size():
		if not await _park_settled(hider, hider_world, cycle_spots[i]):
			cycles_ok = false
			break
		var n := _clone_count(host)
		hider.place_clone()
		var cyc_placed := func() -> bool: return _clone_count(host) == n + 1
		if not await _until(cyc_placed, SYNC_BUDGET):
			cycles_ok = false
			break
		hider.request_swap()
		var cyc_swapped := func() -> bool: return _clone_count(host) == n
		if not await _until(cyc_swapped, SYNC_BUDGET):
			cycles_ok = false
			break
		var watch_deadline := _elapsed + 0.8
		while _elapsed < watch_deadline and not _done:
			worst_y = minf(worst_y, hider.position.y)
			await process_frame
	_check(cycles_ok, "cycles: %d place+swap cycles all completed" % cycle_spots.size())
	_check(worst_y > FLOOR_TOP - 0.08,
			"cycles: player never below the floor across all cycles (min y=%.3f)" % worst_y)
	_check(host.gs.is_alive(hider_id), "cycles: hider still alive afterwards")

	_finish()
