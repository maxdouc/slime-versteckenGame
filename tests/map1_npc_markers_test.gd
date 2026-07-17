extends SceneTree
## Headless test — Map 1 NPC spawn markers (Phase 7, feature/map1-npc-spawn-markers).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/map1_npc_markers_test.gd
##
## SPEC.md 7: ~30 hand-placed markers on Map 1; 12 of them activate for a
## full lobby, so no two rounds look alike. Covers: >= 30 markers in the
## npc_spawn group, every marker strictly inside exactly ONE room volume
## (which also proves none sit in the sealed seeker box), >= 3 markers per
## room, sane floor heights — plus an integration pass: the NpcManager
## running offline on this map spawns the expected count at distinct marker
## positions. Exits 0 / 1.

const MAP_SCENE_PATH := "res://maps/map1_house.tscn"
const GAME_STATE_PATH := "res://scripts/game_state.gd"
const NPC_MANAGER_PATH := "res://scripts/round/npc_manager.gd"
const TIMEOUT_SEC := 60.0

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		_failures += 1  # a timeout is a failure even if every ran check passed
		printerr("[map1_npc_markers_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
	if _failures == 0:
		print("[map1_npc_markers_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[map1_npc_markers_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _run_tests() -> void:
	await process_frame
	var map: Node3D = (load(MAP_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame

	var volumes: Array = []
	for area in map.find_children("*", "Area3D", true, false):
		if area.is_in_group("room_volume"):
			volumes.append(area)
	var markers: Array = []
	for marker in map.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("npc_spawn"):
			markers.append(marker)

	# --- Placement rules ----------------------------------------------------------
	print("[map1_npc_markers_test] placement")
	_check(markers.size() >= 30, ">= 30 npc_spawn markers (%d)" % markers.size())
	var per_room := {}
	var placement_ok := true
	var heights_ok := true
	for marker in markers:
		var containing: Array = []
		for volume in volumes:
			if volume.contains_global(marker.global_position):
				containing.append(volume.room_id)
		if containing.size() != 1:
			placement_ok = false
			printerr("  marker %s sits in %d rooms" % [marker.name, containing.size()])
		else:
			per_room[containing[0]] = per_room.get(containing[0], 0) + 1
		var y: float = marker.global_position.y
		if y <= 0.0 or y >= 1.0:
			heights_ok = false
	_check(placement_ok, "every marker sits strictly inside exactly one room")
	_check(heights_ok, "every marker floats at floor height (0 < y < 1)")
	var spread_ok := per_room.size() == 9
	for room_id in per_room:
		if per_room[room_id] < 3:
			spread_ok = false
			printerr("  room '%s' has only %d markers" % [room_id, per_room[room_id]])
	_check(spread_ok, "every one of the 9 rooms holds >= 3 markers")

	root.remove_child(map)
	map.free()

	# --- Integration: the NpcManager spawns from these markers ----------------------
	print("[map1_npc_markers_test] offline spawn integration")
	var world := Node3D.new()
	world.name = "OfflineWorld"
	root.add_child(world)
	var gs: Node = (load(GAME_STATE_PATH) as GDScript).new()
	gs.name = "GameState"
	world.add_child(gs)
	var map2: Node3D = (load(MAP_SCENE_PATH) as PackedScene).instantiate()
	world.add_child(map2)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	var npcs := Node3D.new()
	npcs.name = "Npcs"
	world.add_child(npcs)
	var npc_spawner := MultiplayerSpawner.new()
	npc_spawner.name = "NpcSpawner"
	world.add_child(npc_spawner)
	npc_spawner.spawn_path = NodePath("../Npcs")
	var manager: Node = (load(NPC_MANAGER_PATH) as GDScript).new()
	manager.name = "NpcManager"
	world.add_child(manager)
	await process_frame

	gs.start_round()  # offline: 1 hider, 0 seekers -> 2 NPCs
	var spawned_pred := func() -> bool: return npcs.get_child_count() == 2
	_check(await _until(spawned_pred, 5.0), "offline round spawned 2 NPCs (2 x 1 hider)")
	var positions := {}
	var on_markers := true
	var marker_positions: Array = []
	for marker in map2.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("npc_spawn"):
			marker_positions.append(marker.global_position)
	for npc in npcs.get_children():
		positions[npc.global_position.snapped(Vector3(0.01, 0.01, 0.01))] = true
		var near := false
		for pos in marker_positions:
			if npc.global_position.distance_to(pos) < 0.1:
				near = true
		if not near:
			on_markers = false
	_check(positions.size() == 2, "the two NPCs occupy two distinct spots (no reuse)")
	_check(on_markers, "every NPC stands on one of the hand-placed markers")

	root.remove_child(world)
	world.free()
	_finish()
