extends SceneTree
## Headless two-peer test — paint event sync (Phase 4,
## feature/paint-event-sync).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/paint_sync_test.gd
##
## SPEC.md 9.3 netcode rule: brush strokes sync as EVENTS and replay on every
## client — whole textures are never transmitted. This suite boots three
## independent SceneMultiplayer branches in one process (HostWorld,
## ClientWorld, late-joining LateWorld) over real localhost ENet peers, the
## same harness as tests/network_transform_test.gd. The gameplay code under
## test never touches a transport.
##
## Covers: the compact int64 event encoding (quantize -> broadcast -> every
## peer stamps the DEQUANTIZED values, so images match bit for bit), stroke/
## Grundieren/Alles-Löschen propagation, bounded history compaction (a fill
## obsoletes earlier strokes), the transform+paint same-frame race (epoch
## gating), late-join replay from events, non-authority rejection, and the
## slime-return wipe arriving on remote copies.
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const SYNC_SCRIPT_PATH := "res://scripts/paint/paint_sync.gd"
const FORMS_SCRIPT_PATH := "res://scripts/player_forms.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const PORT := 8912  # private; 8910 = game ENet fallback, 8911 = transform test
const SYNC_BUDGET := 5.0
const CONNECT_BUDGET := 8.0
const TIMEOUT_SEC := 150.0
const MOSS := Color(0.25, 0.55, 0.2)
const BLUE := Color(0.15, 0.3, 0.85)
const RED := Color(0.82, 0.13, 0.10)

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
		printerr("[paint_sync_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
	# Teardown order (see network_transform_test.gd): worlds first, then
	# unregister branch APIs, then peers; finally break the dict cycles.
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
		print("[paint_sync_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[paint_sync_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

## Await process frames until `predicate` returns true or the budget runs out.
func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

## One isolated multiplayer "machine" (see network_transform_test.gd).
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

## Bit-identical paint on two capsules — the core determinism requirement.
func _images_equal(a: CharacterBody3D, b: CharacterBody3D) -> bool:
	if not a.painter.is_painted() or not b.painter.is_painted():
		return false
	return a.painter.image().get_data() == b.painter.image().get_data()

func _color_close(a: Color, b: Color, tol := 0.007) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
			and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol

func _run_tests() -> void:
	await process_frame
	var forms: GDScript = load(FORMS_SCRIPT_PATH)
	var sync_script: GDScript = load(SYNC_SCRIPT_PATH)

	# --- Event encoding: compact, quantized, lossless roundtrip ---------------
	print("[paint_sync_test] event encoding")
	_check(int(sync_script.MAX_HISTORY) > 0 and int(sync_script.MAX_HISTORY) <= 8192,
			"history is bounded (MAX_HISTORY = %d)" % int(sync_script.MAX_HISTORY))
	var stroke_event: int = sync_script.encode_stroke(Vector2(0.5, 0.75), MOSS)
	_check(sync_script.decode_type(stroke_event) == sync_script.EVENT_STROKE,
			"stroke event decodes as a stroke")
	_check(sync_script.decode_uv(stroke_event).distance_to(Vector2(0.5, 0.75)) < 1.0 / 65535.0 * 2.0,
			"stroke uv survives 16-bit quantization")
	_check(_color_close(sync_script.decode_color(stroke_event), MOSS, 1.0 / 255.0),
			"stroke color survives 8-bit quantization")
	var corner_lo: int = sync_script.encode_stroke(Vector2(0.0, 0.0), Color(0, 0, 0))
	var corner_hi: int = sync_script.encode_stroke(Vector2(1.0, 1.0), Color(1, 1, 1))
	_check(sync_script.decode_uv(corner_lo) == Vector2(0.0, 0.0)
			and sync_script.decode_uv(corner_hi) == Vector2(1.0, 1.0),
			"uv corners (0,0)/(1,1) roundtrip exactly")
	var fill_event: int = sync_script.encode_fill(BLUE)
	_check(sync_script.decode_type(fill_event) == sync_script.EVENT_FILL
			and _color_close(sync_script.decode_color(fill_event), BLUE, 1.0 / 255.0),
			"fill event roundtrips type + color")
	_check(sync_script.decode_type(sync_script.encode_clear()) == sync_script.EVENT_CLEAR,
			"clear event roundtrips its type")

	# --- Scene structure: PaintSync node + paint_epoch replication -------------
	print("[paint_sync_test] scene structure")
	var probe: Node = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	var probe_sync: Node = probe.get_node_or_null("PaintSync")
	_check(probe_sync != null and probe_sync.get_script() == sync_script,
			"player scene has the PaintSync node with its script")
	var config: SceneReplicationConfig = \
			probe.get_node("MultiplayerSynchronizer").replication_config
	var epoch_path := NodePath(".:paint_epoch")
	var has_epoch := config.get_properties().has(epoch_path)
	_check(has_epoch, "replication config contains .:paint_epoch")
	if has_epoch:
		_check(config.property_get_spawn(epoch_path),
				"paint_epoch ships in spawn state (late joiners)")
		_check(config.property_get_replication_mode(epoch_path)
				== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE,
				"paint_epoch replicates on change only")
	_check(config.get_properties().has(NodePath(".:form_id"))
			and config.get_properties().has(NodePath(".:position"))
			and config.get_properties().has(NodePath("Visual:rotation")),
			"existing replication entries untouched")
	var structure_ok := probe_sync != null and has_epoch  # before free() nulls the refs
	probe.free()
	if not structure_ok:
		_check(false, "no PaintSync wiring — skipping the network checks")
		_finish()
		return

	# --- Host + client connect over real localhost ENet ------------------------
	print("[paint_sync_test] connect host + client")
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
	var client_copy_host: CharacterBody3D = client.players.get_node("1")
	var host_copy_client: CharacterBody3D = host.players.get_node(str(client_id))
	var host_sync: Node = host_own.get_node("PaintSync")

	# --- Strokes replicate bit-identically --------------------------------------
	print("[paint_sync_test] strokes host -> client")
	host_own.transform_to_prop("carton")
	_check(await _until(func() -> bool: return client_copy_host.form_id == "carton", SYNC_BUDGET),
			"host's carton form arrived at the client")
	host_sync.local_stroke(Vector2(0.5, 0.75), MOSS)
	_check(host_own.painter.is_painted(), "local stroke paints the host immediately (call_local)")
	_check(await _until(func() -> bool: return _images_equal(host_own, client_copy_host), SYNC_BUDGET),
			"one stroke: client image is bit-identical")
	host_sync.local_stroke(Vector2(0.2, 0.2), RED)
	host_sync.local_stroke(Vector2(0.8, 0.3), BLUE)
	host_sync.local_stroke(Vector2(0.35, 0.9), MOSS)
	_check(await _until(func() -> bool: return _images_equal(host_own, client_copy_host), SYNC_BUDGET),
			"four strokes: still bit-identical")
	_check(client_copy_host.paint_epoch == host_own.paint_epoch,
			"paint_epoch agrees on both peers")
	_check(host_sync._history.size() == 4, "history holds the four stroke events")

	# --- Grundieren compacts, Alles-Löschen empties ------------------------------
	print("[paint_sync_test] fill + clear")
	host_sync.local_fill(BLUE)
	_check(host_sync._history.size() == 1, "fill compacts the history to itself")
	host_sync.local_stroke(Vector2(0.5, 0.5), RED)
	_check(host_sync._history.size() == 2, "strokes append after the fill")
	_check(await _until(func() -> bool: return _images_equal(host_own, client_copy_host), SYNC_BUDGET),
			"fill + stroke: client image is bit-identical")
	_check(_color_close(client_copy_host.painter.color_at_uv(Vector2(0.05, 0.05)), BLUE),
			"client sees the fill color outside the stroke")
	host_sync.local_clear()
	_check(host_sync._history.size() == 0, "clear empties the history")
	_check(await _until(func() -> bool: return not client_copy_host.painter.is_painted(), SYNC_BUDGET),
			"Alles-Löschen resets the client copy to neutral white")
	_check(not host_own.painter.is_painted(), "and the host copy too")

	# --- Transform + paint in the same frame (epoch race) ------------------------
	print("[paint_sync_test] transform + paint burst")
	host_own.transform_to_prop("bucket")
	host_sync.local_fill(MOSS)
	host_sync.local_stroke(Vector2(0.25, 0.25), RED)
	var burst_pred := func() -> bool:
		return client_copy_host.form_id == "bucket" and _images_equal(host_own, client_copy_host)
	_check(await _until(burst_pred, SYNC_BUDGET),
			"same-frame transform+fill+stroke converges bit-identically")
	var client_prop: MeshInstance3D = client_copy_host.painter.bound_mesh_instance()
	_check(client_prop != null and is_instance_valid(client_prop)
			and client_prop.get_surface_override_material(0) != null
			and client_prop.get_surface_override_material(0).albedo_texture
					== client_copy_host.painter.texture(),
			"client copy renders the paint on the NEW prop mesh")

	# --- Client paints too (any peer can be a sender for its own capsule) --------
	print("[paint_sync_test] client -> host")
	var client_own: CharacterBody3D = client.players.get_node(str(client_id))
	client_own.transform_to_prop("cup")
	await _until(func() -> bool: return host_copy_client.form_id == "cup", SYNC_BUDGET)
	client_own.get_node("PaintSync").local_fill(RED)
	_check(await _until(func() -> bool: return _images_equal(client_own, host_copy_client), SYNC_BUDGET),
			"client's Grundieren arrives bit-identically at the host")

	# --- Non-authority calls are rejected ----------------------------------------
	print("[paint_sync_test] non-authority guard")
	var host_bytes: PackedByteArray = host_own.painter.image().get_data()
	client_copy_host.get_node("PaintSync").local_stroke(Vector2(0.9, 0.9), RED)
	for i in 30:
		await process_frame
	_check(host_own.painter.image().get_data() == host_bytes,
			"a remote copy cannot inject strokes (authority guard)")

	# --- Late joiner replays the paint from events ---------------------------------
	print("[paint_sync_test] late join replay")
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
		_check(await _until(func() -> bool: return _images_equal(host_own, late_copy_host), SYNC_BUDGET),
				"late joiner reproduces the host's paint bit-identically")
		_check(await _until(func() -> bool: return _images_equal(client_own, late_copy_client), SYNC_BUDGET),
				"late joiner reproduces the client's paint too")
		_check(late_copy_host.paint_epoch == host_own.paint_epoch,
				"late joiner's paint_epoch matches")

	# --- Returning to slime wipes everywhere ---------------------------------------
	print("[paint_sync_test] slime return wipes remotely")
	host_own.transform_to_slime()
	_check(await _until(func() -> bool: return not client_copy_host.painter.is_painted(), SYNC_BUDGET),
			"slime return wipes the client copy")
	if late_spawned:
		var late_copy_host2: CharacterBody3D = late.players.get_node("1")
		_check(await _until(func() -> bool: return not late_copy_host2.painter.is_painted(), SYNC_BUDGET),
				"slime return wipes the late copy")
	_check(host_sync._history.size() == 0, "slime return clears the history")

	_finish()
