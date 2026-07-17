extends SceneTree
## Headless test — Map 1 Kenney dressing (Phase 7, feature/map1-kenney-dressing).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/map1_dressing_test.gd
##
## SPEC.md 13/14: first dressing pass with the approved Kenney Furniture Kit
## (CC0). Rules under test: the license ships next to the assets; ONLY used
## assets are committed (every .glb under assets/kenney is referenced by a
## decoy scene); every decoy on the map renders Kenney geometry (dressed, not
## primitive); decoys stay solid slot-convention bodies and never read as the
## players' all-white untransformed look; and the slot layout survived the
## dressing (counts + a large decoy in every room). Exits 0 / 1.

const MAP_SCENE_PATH := "res://maps/map1_house.tscn"
const ASSET_DIR := "res://assets/kenney/furniture_kit"
const TIMEOUT_SEC := 60.0
const WHITE := Color(1, 1, 1, 1)

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
		printerr("[map1_dressing_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[map1_dressing_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[map1_dressing_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _glb_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ASSET_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".glb"):
			out.append(file)
		file = dir.get_next()
	return out

func _run_tests() -> void:
	await process_frame

	# --- Licensing + used-only asset policy ----------------------------------------
	print("[map1_dressing_test] asset policy")
	_check(FileAccess.file_exists(ASSET_DIR + "/License.txt"),
			"Kenney license ships next to the assets")
	var glbs := _glb_files()
	_check(glbs.size() >= 6, ">= 6 Kenney models copied (%d)" % glbs.size())

	# Every committed .glb must be referenced by some decoy scene text.
	var scene_text := ""
	var scenes_dir := DirAccess.open("res://scenes/props")
	if scenes_dir != null:
		scenes_dir.list_dir_begin()
		var f := scenes_dir.get_next()
		while f != "":
			if f.ends_with(".tscn"):
				scene_text += FileAccess.get_file_as_string("res://scenes/props/" + f)
			f = scenes_dir.get_next()
	var all_used := glbs.size() > 0
	for glb in glbs:
		if not scene_text.contains(glb):
			all_used = false
			printerr("  unused committed asset: %s" % glb)
	_check(all_used, "every committed Kenney model is referenced by a decoy scene")

	# --- The map is dressed -----------------------------------------------------------
	print("[map1_dressing_test] dressed decoys")
	var map: Node3D = (load(MAP_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame

	var volumes: Array = []
	for area in map.find_children("*", "Area3D", true, false):
		if area.is_in_group("room_volume"):
			volumes.append(area)
	var slots: Array = []
	for node in map.find_children("*", "StaticBody3D", true, false):
		if node.is_in_group("prop_slot"):
			slots.append(node)
	_check(slots.size() >= 28, "slot layout survived the dressing (%d slots)" % slots.size())

	var dressed_ok := true
	var solid_ok := true
	var not_all_white_ok := true
	var kenney_models_used := {}
	for slot in slots:
		var meshes: Array = slot.find_children("*", "MeshInstance3D", true, false)
		var has_kenney := false
		var any_colored := false
		for mesh_node in meshes:
			var mesh: Mesh = (mesh_node as MeshInstance3D).mesh
			if mesh == null:
				continue
			var path := mesh.resource_path
			if path.begins_with(ASSET_DIR):
				has_kenney = true
				kenney_models_used[path.get_slice("::", 0)] = true
			for surface in mesh.get_surface_count():
				var mat := (mesh_node as MeshInstance3D).get_active_material(surface)
				if mat is BaseMaterial3D \
						and not (mat as BaseMaterial3D).albedo_color.is_equal_approx(WHITE):
					any_colored = true
		if not has_kenney:
			dressed_ok = false
			printerr("  undressed slot: %s" % slot.name)
		if not any_colored:
			not_all_white_ok = false
			printerr("  all-white slot: %s" % slot.name)
		var has_shape := false
		for child in slot.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
				has_shape = true
		if not has_shape:
			solid_ok = false
	_check(dressed_ok, "every decoy renders Kenney geometry")
	_check(solid_ok, "every decoy still has a collision shape")
	_check(not_all_white_ok, "no decoy reads as the players' all-white look")
	_check(kenney_models_used.size() >= 6,
			"the map uses >= 6 distinct Kenney models (%d)" % kenney_models_used.size())

	# SPEC.md 13 invariant survives: a LARGE decoy in every room.
	var rooms_with_large := {}
	for slot in slots:
		if slot.size_class == "large":
			for volume in volumes:
				if volume.contains_global(slot.global_position):
					rooms_with_large[volume.room_id] = true
	_check(rooms_with_large.size() == 9,
			"every room still holds a large decoy (%d)" % rooms_with_large.size())

	root.remove_child(map)
	map.free()
	_finish()
