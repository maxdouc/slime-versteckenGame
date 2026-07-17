extends SceneTree
## Headless multi-peer test — clones (Phase 9, feature/clones).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/clones_test.gd
##
## SPEC.md 10: a clone is a STATIC copy of the current form INCLUDING its
## paint at placement time, unlocked through the eat table (max 3, budget =
## Progression.clones_allowed). Placement is host-validated; the paint rides
## in the spawn data as the owner's compacted stroke-event snapshot — never a
## texture — so live peers and late joiners replay the identical image.
##
## Covers: budget enforcement from the eat table, slime placement rejected,
## the clone appearing on every peer with the right form AND pixel-accurate
## paint, no auto-decay across time, late-join replay via the spawner, and
## the round-reset cleanup. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const CLONE_MANAGER_PATH := "res://scripts/clones/clone_manager.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 150.0
const RED := Color(0.8, 0.1, 0.1)

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
		printerr("[clones_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[clones_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[clones_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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

	print("[clones_test] connect host + client")
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

	host.gs.prep_seconds = 60.0  # the test controls transitions
	host.gs.hunt_seconds = 60.0
	host.gs.end_seconds = 0.4
	host.gs.rotation_seconds = 60.0
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

	# --- Slime placement is rejected (a clone copies a FORM) ----------------------
	print("[clones_test] gating")
	hider.place_clone()
	await _wait(0.5)
	_check(_clone_count(host) == 0, "slime placement rejected")

	# 2 eaten -> medium unlocked AND clone budget = 2 (SPEC.md 8/10).
	host.gs.record_eaten(hider_id)
	host.gs.record_eaten(hider_id)
	var eaten_pred := func() -> bool: return hider_world.gs.eaten_of(hider_id) == 2
	await _until(eaten_pred, SYNC_BUDGET)
	hider.transform_to_prop("bucket")
	await process_frame
	_check(hider.form_id == "bucket", "hider transformed (medium at 2 eaten)")

	# Paint the prop: red base coat + one stroke, through the production path.
	hider.painter.brush_color = RED
	hider.get_node("PaintSync").local_fill(RED)
	hider.get_node("PaintSync").local_stroke(Vector2(0.25, 0.25), Color(0.1, 0.2, 0.9))
	await _wait(0.4)  # let the paint events reach the other peer

	# --- Placement: the clone appears everywhere with form + paint ----------------
	# Fixed contract (fix/phase-5-9-manual-validation): the clone appears
	# PLACE_OFFSET in front of the facing, base floor-snapped — never inside
	# the placer, never inside the floor.
	print("[clones_test] placement with paint")
	hider.global_position = hider_world.world.position + Vector3(-3.0, 1.0, -3.0)
	hider.velocity = Vector3.ZERO
	hider.get_node("Visual").rotation.y = 0.0  # facing -Z, deterministic
	await process_frame
	hider.place_clone()
	var placed_pred := func() -> bool:
		return _clone_count(host) == 1 and _clone_count(client) == 1
	var placed := await _until(placed_pred, SYNC_BUDGET)
	_check(placed, "clone spawned on host AND client")
	if not placed:
		_finish()
		return
	var host_clone: Node3D = host.clones.get_child(0)
	var client_clone: Node3D = client.clones.get_child(0)
	_check(host_clone.form_id == "bucket" and client_clone.form_id == "bucket",
			"clone carries the placed form on both peers")
	_check(host_clone.position.distance_to(Vector3(-3.0, 0.12, -4.3)) < 0.3,
			"clone stands floor-snapped in front of the hider")
	var paint_pred := func() -> bool:
		var a: Image = host_clone.paint_image()
		var b: Image = client_clone.paint_image()
		return a != null and b != null
	_check(await _until(paint_pred, SYNC_BUDGET), "clone paint replayed on both peers")
	var owner_image: Image = hider.painter.image()
	var samples_ok := true
	for uv in [Vector2(0.25, 0.25), Vector2(0.7, 0.7), Vector2(0.5, 0.1)]:
		var px := int(uv.x * 256)
		var py := int(uv.y * 256)
		var want: Color = owner_image.get_pixel(px, py)
		if not host_clone.paint_image().get_pixel(px, py).is_equal_approx(want) \
				or not client_clone.paint_image().get_pixel(px, py).is_equal_approx(want):
			samples_ok = false
	_check(samples_ok, "clone pixels match the owner's paint at placement (both peers)")

	# The owner repainting AFTER placement must not touch the static clone.
	hider.get_node("PaintSync").local_fill(Color(0.1, 0.9, 0.1))
	await _wait(0.4)
	_check(not host_clone.paint_image().get_pixel(180, 180).is_equal_approx(Color(0.1, 0.9, 0.1)),
			"a clone is STATIC: the owner's later repaint does not touch it")

	# --- Budget: 2 eaten = 2 clones, the third is rejected -------------------------
	# Each placement gets its own FREE spot: overlap protection would
	# otherwise shadow the budget rule this section is about.
	print("[clones_test] budget")
	hider.global_position = hider_world.world.position + Vector3(0.0, 1.0, -3.0)
	hider.velocity = Vector3.ZERO
	await process_frame
	hider.place_clone()
	var second_pred := func() -> bool:
		return _clone_count(host) == 2 and _clone_count(client) == 2
	_check(await _until(second_pred, SYNC_BUDGET), "second clone allowed (budget 2)")
	hider.global_position = hider_world.world.position + Vector3(3.0, 1.0, -3.0)
	hider.velocity = Vector3.ZERO
	await process_frame
	hider.place_clone()
	await _wait(0.5)
	_check(_clone_count(host) == 2, "third clone rejected (SPEC.md 8 budget)")

	# --- No auto-decay ---------------------------------------------------------------
	await _wait(1.0)
	_check(_clone_count(host) == 2 and _clone_count(client) == 2,
			"clones do not decay on their own (SPEC.md 10)")

	# --- Late joiner gets the clones INCLUDING paint ---------------------------------
	print("[clones_test] late joiner")
	var late := _make_world("LateWorld", 100.0)
	var late_peer := ENetMultiplayerPeer.new()
	_check(late_peer.create_client("127.0.0.1", PORT) == OK, "late ENet client created")
	_cleanup_peers.append(late_peer)
	late.api.multiplayer_peer = late_peer
	var late_pred := func() -> bool: return _clone_count(late) == 2
	_check(await _until(late_pred, CONNECT_BUDGET), "late joiner received both clones")
	var late_clone: Node3D = late.clones.get_child(0)
	var late_paint_ok: bool = late_clone.paint_image() != null \
			and late_clone.paint_image().get_pixel(64, 64).is_equal_approx(
					host_clone.paint_image().get_pixel(64, 64))
	_check(late_paint_ok, "late joiner replayed the clone paint from the spawn data")

	# --- Round reset removes every clone ----------------------------------------------
	print("[clones_test] reset")
	host.gs._advance_phase()  # PREP -> HUNT
	host.gs._advance_phase()  # HUNT -> END -> (end_seconds) -> LOBBY + reset
	var cleared_pred := func() -> bool:
		return _clone_count(host) == 0 and _clone_count(client) == 0 \
				and _clone_count(late) == 0
	_check(await _until(cleared_pred, 8.0), "round reset removed clones everywhere")

	_finish()
