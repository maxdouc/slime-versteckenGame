extends SceneTree
## Headless two-peer test — networked transform state (Phase 3,
## feature/network-transform-state).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/network_transform_test.gd
##
## Boots THREE independent SceneMultiplayer branches inside this one process —
## HostWorld (ENet server on 127.0.0.1:8911), ClientWorld, and a late-joining
## LateWorld — each with the Players/PlayerSpawner wiring mirrored from
## main.gd and the real player scene. Every peer is a real ENetMultiplayerPeer
## over localhost, so the full high-level replication path (spawner spawns,
## synchronizer deltas, spawn state) is exercised end to end: host->client and
## client->host transforms, every size, repeated cycles, a same-frame burst,
## late join while already transformed, and disconnect cleanup. The worlds sit
## 50 m apart on X so their physics bodies never touch each other.
##
## The gameplay code under test never touches a transport — only this harness
## builds peers, exactly like server/smoke_test.gd does for the WebRTC path.
## The real two-machine test stays mandatory before merge (README rule).
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const FORMS_SCRIPT_PATH := "res://scripts/player_forms.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8911  # private port; the game's ENet fallback default is 8910
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 150.0
const WHITE := Color(1, 1, 1, 1)

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
		printerr("[net_transform_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
	# Teardown order matters: free the worlds FIRST, while their branch APIs
	# are still registered and their sessions alive, so every synchronizer and
	# spawner unregisters against the API that actually tracks it. Only then
	# unregister the branches and drop the peers.
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
	# The peer_connected lambdas capture the world dicts, which hold the APIs
	# owning those signal connections — a RefCounted cycle GDScript never
	# collects. Emptying the dicts breaks the cycle so nothing leaks at exit.
	for info in _worlds:
		info.clear()
	_worlds.clear()
	_cleanup_peers.clear()
	if _failures == 0:
		print("[net_transform_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[net_transform_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

## Await process frames until `predicate` returns true or the budget runs out.
func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## One isolated multiplayer "machine": its own SceneMultiplayer branch with the
## same Players + PlayerSpawner wiring main.gd uses, plus a gray room floor.
func _make_world(world_name: String, x_offset: float) -> Dictionary:
	var world := Node3D.new()
	world.name = world_name
	world.position = Vector3(x_offset, 0.0, 0.0)
	root.add_child(world)
	var api := MultiplayerAPI.create_default_interface()
	set_multiplayer(api, world.get_path())
	world.add_child(load(ROOM_SCENE_PATH).instantiate())
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	world.add_child(spawner)
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_capsule
	var info := {"world": world, "api": api, "players": players, "spawner": spawner}
	_worlds.append(info)
	return info

## Mirrors main.gd's spawn contract: data = [peer id, spawn position].
func _spawn_capsule(data: Variant) -> Node:
	var capsule: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _run_tests() -> void:
	await process_frame
	var forms: GDScript = load(FORMS_SCRIPT_PATH)

	# --- Replication config declares form_id ---------------------------------
	print("[net_transform_test] replication config")
	var probe: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	var sync_node: MultiplayerSynchronizer = probe.get_node("MultiplayerSynchronizer")
	var config: SceneReplicationConfig = sync_node.replication_config
	var form_path := NodePath(".:form_id")
	var has_form := config.get_properties().has(form_path)
	_check(has_form, "replication config contains .:form_id")
	if has_form:
		_check(config.property_get_spawn(form_path),
				"form_id ships in spawn state (late joiners)")
		_check(config.property_get_replication_mode(form_path)
				== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
				"form_id replicates on change only (compact, reliable)")
	_check(config.get_properties().has(NodePath(".:position"))
			and config.get_properties().has(NodePath("Visual:rotation")),
			"existing position/rotation sync entries untouched")
	probe.free()

	# --- Host + client connect over real localhost ENet ----------------------
	print("[net_transform_test] connect host + client")
	var host := _make_world("HostWorld", 0.0)
	var client := _make_world("ClientWorld", 50.0)

	var host_peer := ENetMultiplayerPeer.new()
	_check(host_peer.create_server(PORT, 8) == OK, "ENet server listening on %d" % PORT)
	_cleanup_peers.append(host_peer)
	host.api.multiplayer_peer = host_peer
	_host_spawn_slot = 1
	host.spawner.spawn([1, Vector3(0.0, 1.0, 0.0)])
	host.api.peer_connected.connect(func(id: int) -> void:
		host.spawner.spawn([id, Vector3(3.0 * _host_spawn_slot, 1.0, 0.0)])
		_host_spawn_slot += 1)
	host.api.peer_disconnected.connect(func(id: int) -> void:
		var gone: Node = host.players.get_node_or_null(str(id))
		if gone != null:
			gone.queue_free())

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
		_check(false, "no connected pair — skipping the sync checks")
		_finish()
		return

	var host_own: CharacterBody3D = host.players.get_node("1")
	var host_copy_client: CharacterBody3D = host.players.get_node(str(client_id))
	var client_own: CharacterBody3D = client.players.get_node(str(client_id))
	var client_copy_host: CharacterBody3D = client.players.get_node("1")
	await process_frame
	_check(client_copy_host.get_node_or_null("CameraPivot") == null,
			"client's copy of the host is remote (camera rig freed)")
	_check(client_own.get_node_or_null("CameraPivot") != null,
			"client's own capsule is local (camera rig present)")
	_check(client_copy_host.form_id == forms.SLIME, "host copy starts as slime on the client")

	# --- Host transforms, client sees it --------------------------------------
	print("[net_transform_test] host -> client")
	host_own.transform_to_prop("carton")
	_check(await _until(func() -> bool: return client_copy_host.form_id == "carton", SYNC_BUDGET),
			"host's carton form arrived at the client")
	_check_applied(client_copy_host, forms, "carton", "client copy of host")
	_check(is_equal_approx(host_own.max_speed(), host_own.WALK_SPEED * 0.4),
			"authoritative host runs at 40 % as carton")

	# --- Client transforms, host sees it --------------------------------------
	print("[net_transform_test] client -> host")
	client_own.transform_to_prop("cup")
	_check(await _until(func() -> bool: return host_copy_client.form_id == "cup", SYNC_BUDGET),
			"client's cup form arrived at the host")
	_check_applied(host_copy_client, forms, "cup", "host copy of client")

	# --- Every size, back to slime, twice over --------------------------------
	print("[net_transform_test] every size + repeated cycles")
	var cycles_ok := true
	for cycle in 2:
		for step: String in ["bucket", "cup", "carton", forms.SLIME]:
			if step == forms.SLIME:
				host_own.transform_to_slime()
			else:
				host_own.transform_to_prop(step)
			if not await _until(func() -> bool: return client_copy_host.form_id == step, SYNC_BUDGET):
				_check(false, "cycle %d: '%s' never arrived at the client" % [cycle, step])
				cycles_ok = false
				break
			var anchor: Node3D = client_copy_host.get_node("Visual/PropAnchor")
			var slime_visible: bool = client_copy_host.get_node("Visual/SlimeVisual").visible
			var want_children: int = 0 if step == forms.SLIME else 1
			if anchor.get_child_count() != want_children or slime_visible != (step == forms.SLIME):
				_check(false, "cycle %d: stale or duplicate visuals after '%s'" % [cycle, step])
				cycles_ok = false
				break
		if not cycles_ok:
			break
	_check(cycles_ok, "2 full remote cycles: exactly one visible form per step")

	# --- Same-frame burst: only the final state matters ------------------------
	host_own.transform_to_prop("carton")
	host_own.transform_to_prop("cup")
	host_own.transform_to_prop("bucket")
	_check(await _until(func() -> bool: return client_copy_host.form_id == "bucket", SYNC_BUDGET),
			"same-frame burst: final form (bucket) wins on the client")
	_check(client_copy_host.get_node("Visual/PropAnchor").get_child_count() == 1,
			"same-frame burst: still exactly one visual")

	# --- Late joiner sees the current forms via spawn state --------------------
	print("[net_transform_test] late joiner")
	host_own.transform_to_prop("carton")
	await _until(func() -> bool: return client_copy_host.form_id == "carton", SYNC_BUDGET)
	var late := _make_world("LateWorld", 100.0)
	var late_peer := ENetMultiplayerPeer.new()
	_check(late_peer.create_client("127.0.0.1", PORT) == OK, "late ENet client created")
	_cleanup_peers.append(late_peer)
	late.api.multiplayer_peer = late_peer
	var late_spawned := await _until(func() -> bool: return late.players.get_child_count() == 3, CONNECT_BUDGET)
	_check(late_spawned, "late world received all 3 capsules")
	if late_spawned:
		var late_copy_host: CharacterBody3D = late.players.get_node("1")
		var late_copy_client: CharacterBody3D = late.players.get_node(str(client_id))
		_check(await _until(func() -> bool: return late_copy_host.form_id == "carton", SYNC_BUDGET),
				"late joiner sees the host already as carton")
		_check_applied(late_copy_host, forms, "carton", "late copy of host")
		_check(await _until(func() -> bool: return late_copy_client.form_id == "cup", SYNC_BUDGET),
				"late joiner sees the client's cup form")

		# --- Remote copies must ignore local transform attempts ----------------
		print("[net_transform_test] non-authority transform calls")
		late_copy_host.transform_to_prop("cup")
		late_copy_host.transform_to_slime()
		await process_frame
		_check(late_copy_host.form_id == "carton",
				"a remote copy ignores local transform_to_* calls (authority guard)")

	# --- Disconnect cleanup -----------------------------------------------------
	print("[net_transform_test] disconnect cleanup")
	client_peer.close()
	client.api.multiplayer_peer = null  # stop polling the closed socket
	var cleaned_pred := func() -> bool:
		return host.players.get_node_or_null(str(client_id)) == null \
				and (not late_spawned or late.players.get_node_or_null(str(client_id)) == null)
	var cleaned := await _until(cleaned_pred, CONNECT_BUDGET)
	_check(cleaned, "disconnected client's capsule despawned everywhere")
	_check(host.players.get_child_count() == 2, "host world keeps exactly host + late capsules")

	_finish()

## The remote copy must show exactly the expected form: one visual, registry
## collision, and — always — neutral white prop meshes (SPEC.md 9.1).
func _check_applied(capsule: CharacterBody3D, forms: GDScript, expected_form: String, label: String) -> void:
	var slime_visual: Node3D = capsule.get_node("Visual/SlimeVisual")
	var anchor: Node3D = capsule.get_node("Visual/PropAnchor")
	var collision: CollisionShape3D = capsule.get_node("CollisionShape3D")
	if expected_form == forms.SLIME:
		_check(slime_visual.visible and anchor.get_child_count() == 0,
				"%s: slime visible, no prop visual" % label)
		_check(collision.shape is CapsuleShape3D, "%s: slime capsule collision" % label)
		return
	_check(not slime_visual.visible, "%s: slime hidden" % label)
	_check(anchor.get_child_count() == 1, "%s: exactly one prop visual" % label)
	_check(collision.shape == forms.collision_shape(expected_form),
			"%s: collision volume from the registry" % label)
	var meshes: Array[Node] = anchor.find_children("*", "MeshInstance3D", true, false)
	var all_white := meshes.size() > 0  # no meshes at all must fail, not pass
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			all_white = false
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			if not (material is StandardMaterial3D and material.albedo_color == WHITE
					and material.albedo_texture == null):
				all_white = false
	_check(all_white, "%s: prop renders neutral white (%d meshes)" % [label, meshes.size()])
