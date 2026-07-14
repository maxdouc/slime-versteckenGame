extends SceneTree
## Headless structural test — Map 1 graybox (Phase 7, feature/map1-house-graybox).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/map1_graybox_test.gd
##
## SPEC.md 13, Wohnhaus: 9 rooms (≈ 1.5 × 6 hiders), every room has at least
## 2 exits (the rotation rule must never build death traps), flat repaintable
## colors, plausible spawn logistics. The graybox encodes exits as doorway
## markers sitting ON the shared wall plane — boundary-inclusive room volumes
## count them for both adjacent rooms, so the ≥2-exits rule is testable.
##
## Covers: 9 uniquely-named room volumes on the Phase 5 convention, doorway
## count + per-room exit rule, player spawn inside a room, sealed seeker box
## outside every room volume, solid graybox construction (bodies with mesh +
## collision), and a repaintable multi-color floor palette. Exits 0 / 1.

const MAP_SCENE_PATH := "res://maps/map1_house.tscn"
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
		printerr("[map1_graybox_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[map1_graybox_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[map1_graybox_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _run_tests() -> void:
	await process_frame
	var packed: PackedScene = load(MAP_SCENE_PATH)
	_check(packed != null, "maps/map1_house.tscn loads")
	if packed == null:
		_finish()
		return
	var map: Node3D = packed.instantiate()
	root.add_child(map)
	await process_frame

	# --- Room volumes (Phase 5 convention) ---------------------------------------
	print("[map1_graybox_test] room volumes")
	var volumes: Array = []
	for area in map.find_children("*", "Area3D", true, false):
		if area.is_in_group("room_volume"):
			volumes.append(area)
	_check(volumes.size() == 9, "exactly 9 room volumes (%d)" % volumes.size())
	var ids := {}
	for volume in volumes:
		if volume.room_id != "":
			ids[volume.room_id] = volume
	_check(ids.size() == volumes.size(), "room ids unique and non-empty")
	_check(ids.has("flur"), "the central hall (flur) exists")
	var separated := true
	for i in volumes.size():
		for j in range(i + 1, volumes.size()):
			if volumes[i].global_position.distance_to(volumes[j].global_position) < 5.0:
				separated = false
	_check(separated, "room volumes sit on distinct centers (>= 5 m apart)")
	var self_contained := true
	for volume in volumes:
		if not volume.contains_global(volume.global_position):
			self_contained = false
	_check(self_contained, "every volume contains its own center")

	# --- Doorways: every room has at least 2 exits (SPEC.md 13) --------------------
	print("[map1_graybox_test] exits")
	var doorways: Array = []
	for marker in map.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("doorway"):
			doorways.append(marker)
	_check(doorways.size() >= 12, "at least 12 doorways (%d)" % doorways.size())
	var exits_ok := true
	for volume in volumes:
		var exits := 0
		for doorway in doorways:
			if volume.contains_global(doorway.global_position):
				exits += 1
		if exits < 2:
			exits_ok = false
			printerr("  room '%s' has only %d exits" % [volume.room_id, exits])
	_check(exits_ok, "every room has >= 2 exits (boundary-inclusive doorways)")
	var doors_between_rooms := true
	for doorway in doorways:
		var containing := 0
		for volume in volumes:
			if volume.contains_global(doorway.global_position):
				containing += 1
		if containing != 2:
			doors_between_rooms = false
	_check(doors_between_rooms, "every doorway sits between exactly 2 rooms")

	# --- Spawns ---------------------------------------------------------------------
	print("[map1_graybox_test] spawns")
	var player_spawn: Node3D = null
	var seeker_spawn: Node3D = null
	for marker in map.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("player_spawn"):
			player_spawn = marker
		elif marker.is_in_group("seeker_spawn"):
			seeker_spawn = marker
	_check(player_spawn != null, "player spawn marker exists")
	var spawn_room := ""
	if player_spawn != null:
		for volume in volumes:
			if volume.contains_global(player_spawn.global_position):
				spawn_room = volume.room_id
	_check(spawn_room != "", "player spawn lies inside a room (%s)" % spawn_room)
	_check(seeker_spawn != null, "seeker spawn marker exists")
	var seeker_outside := true
	if seeker_spawn != null:
		for volume in volumes:
			if volume.contains_global(seeker_spawn.global_position):
				seeker_outside = false
	_check(seeker_outside, "seeker box sits outside every room volume (blind)")

	# --- Solid construction -----------------------------------------------------------
	print("[map1_graybox_test] construction")
	var solid_bodies := 0
	var floor_colors := {}
	for body in map.find_children("*", "StaticBody3D", true, false):
		var mesh: MeshInstance3D = null
		var shape: CollisionShape3D = null
		for child in body.get_children():
			if child is MeshInstance3D:
				mesh = child
			elif child is CollisionShape3D:
				shape = child
		if mesh != null and shape != null and shape.shape != null:
			solid_bodies += 1
			var mat := mesh.get_active_material(0)
			if mat is StandardMaterial3D and body.name.begins_with("Floor"):
				floor_colors[(mat as StandardMaterial3D).albedo_color] = true
	_check(solid_bodies >= 30, "graybox has >= 30 solid bodies (%d)" % solid_bodies)
	_check(floor_colors.size() >= 5,
			"floors use a repaintable multi-color palette (%d colors)" % floor_colors.size())

	root.remove_child(map)
	map.free()
	_finish()
