extends SceneTree
## Headless test — eat progression table (Phase 5, feature/eat-progression-table).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/progression_test.gd
##
## Part 1 checks the pure SPEC.md 8 table (scripts/round/progression.gd):
## 0 eaten -> large only · 1+ -> +medium · 2+ -> +small · cap 3; clone budget
## equals eaten, clamped 0..3. Part 2 drives the enforcement over two real
## localhost ENet peers: hiders can only take unlocked sizes while a round is
## active, seekers cannot transform at all mid-round, LOBBY stays a sandbox,
## the slime form is always allowed, and the eaten count caps at 3.
## Exits 0 / 1.

const PROGRESSION_PATH := "res://scripts/round/progression.gd"
const FORMS_PATH := "res://scripts/player_forms.gd"
const GAME_STATE_PATH := "res://scripts/game_state.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 120.0

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
		printerr("[progression_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[progression_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[progression_test] FAIL — %d of %d checks failed" % [_failures, _checks])
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

func _run_tests() -> void:
	await process_frame
	var progression: GDScript = load(PROGRESSION_PATH)
	var forms: GDScript = load(FORMS_PATH)

	# --- Part 1: the pure SPEC.md 8 table ---------------------------------------
	print("[progression_test] SPEC.md 8 table (pure)")
	var expect := [
		# eaten, large, medium, small, clones
		[0, true, false, false, 0],
		[1, true, true, false, 1],
		[2, true, true, true, 2],
		[3, true, true, true, 3],
	]
	for row in expect:
		var eaten: int = row[0]
		_check(progression.is_size_unlocked(eaten, forms.Size.LARGE) == row[1],
				"eaten=%d: large %s" % [eaten, "unlocked" if row[1] else "locked"])
		_check(progression.is_size_unlocked(eaten, forms.Size.MEDIUM) == row[2],
				"eaten=%d: medium %s" % [eaten, "unlocked" if row[2] else "locked"])
		_check(progression.is_size_unlocked(eaten, forms.Size.SMALL) == row[3],
				"eaten=%d: small %s" % [eaten, "unlocked" if row[3] else "locked"])
		_check(progression.clones_allowed(eaten) == row[4],
				"eaten=%d: %d clones" % [eaten, row[4]])
	_check(progression.is_size_unlocked(0, forms.Size.SLIME),
			"the slime form is always unlocked")
	_check(progression.clones_allowed(7) == 3, "clone budget clamps above the cap")
	_check(progression.EAT_CAP == 3, "eat cap is 3 (SPEC.md 8)")

	# --- Part 2: enforcement over two peers ---------------------------------------
	print("[progression_test] connect host + client")
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
	host.gs.end_seconds = 0.2
	host.gs.start_round()
	var prep_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.PREP \
				and client.gs.current_phase == client.gs.Phase.PREP
	_check(await _until(prep_pred, SYNC_BUDGET), "both peers in PREP")

	var hider_id := -1
	for id in host.gs.players:
		if host.gs.players[id]["role"] == host.gs.Role.HIDER:
			hider_id = id
	var seeker_id: int = 1 if hider_id == client_id else client_id
	var hider_world: Dictionary = client if hider_id == client_id else host
	var seeker_world: Dictionary = host if hider_id == client_id else client
	var hider: CharacterBody3D = hider_world.players.get_node(str(hider_id))
	var seeker: CharacterBody3D = seeker_world.players.get_node(str(seeker_id))

	# 0 eaten: large only.
	hider.transform_to_prop("bucket")
	await process_frame
	_check(hider.form_id == forms.SLIME, "0 eaten: medium (bucket) rejected")
	hider.transform_to_prop("cup")
	await process_frame
	_check(hider.form_id == forms.SLIME, "0 eaten: small (cup) rejected")
	hider.transform_to_prop("carton")
	await process_frame
	_check(hider.form_id == "carton", "0 eaten: large (carton) allowed")
	hider.transform_to_slime()
	await process_frame
	_check(hider.form_id == forms.SLIME, "back to slime always allowed")

	# 1 eaten: +medium, small still locked.
	host.gs.record_eaten(hider_id)
	var one_synced_pred := func() -> bool:
		return hider_world.gs.eaten_of(hider_id) == 1
	_check(await _until(one_synced_pred, SYNC_BUDGET), "eaten=1 reached the hider's peer")
	hider.transform_to_prop("bucket")
	await process_frame
	_check(hider.form_id == "bucket", "1 eaten: medium (bucket) allowed")
	hider.transform_to_prop("cup")
	await process_frame
	_check(hider.form_id == "bucket", "1 eaten: small (cup) still rejected")

	# 2 eaten: everything.
	host.gs.record_eaten(hider_id)
	var two_synced_pred := func() -> bool:
		return hider_world.gs.eaten_of(hider_id) == 2
	_check(await _until(two_synced_pred, SYNC_BUDGET), "eaten=2 reached the hider's peer")
	hider.transform_to_prop("cup")
	await process_frame
	_check(hider.form_id == "cup", "2 eaten: small (cup) allowed")

	# The unlocked form must still replicate (existing sync untouched).
	var other_side: Dictionary = host if hider_world == client else client
	var replicated_pred := func() -> bool:
		var copy: Node = other_side.players.get_node_or_null(str(hider_id))
		return copy != null and copy.form_id == "cup"
	_check(await _until(replicated_pred, SYNC_BUDGET), "unlocked form replicates to the other peer")

	# Seekers never transform while the round runs.
	seeker.transform_to_prop("carton")
	await process_frame
	_check(seeker.form_id == forms.SLIME, "seeker transform rejected mid-round")

	# Cap: two more eats land on 3, further eats stay 3.
	host.gs.record_eaten(hider_id)
	host.gs.record_eaten(hider_id)
	host.gs.record_eaten(hider_id)
	var cap_pred := func() -> bool: return host.gs.eaten_of(hider_id) == 3
	_check(await _until(cap_pred, SYNC_BUDGET), "eaten caps at 3 (SPEC.md 8)")

	# LOBBY sandbox: end the round, everyone transforms freely again.
	host.gs._advance_phase()  # PREP -> HUNT
	host.gs._advance_phase()  # HUNT -> END -> (end_seconds) -> LOBBY
	var lobby_pred := func() -> bool:
		return host.gs.current_phase == host.gs.Phase.LOBBY \
				and client.gs.current_phase == client.gs.Phase.LOBBY
	_check(await _until(lobby_pred, 8.0), "round over, back in LOBBY")
	seeker.transform_to_prop("cup")
	await process_frame
	_check(seeker.form_id == "cup", "LOBBY sandbox: ex-seeker transforms freely")
	hider.transform_to_prop("bucket")
	await process_frame
	_check(hider.form_id == "bucket", "LOBBY sandbox: any size without eats")

	_finish()
