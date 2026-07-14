extends SceneTree
## Headless test — Map 1 prop slots (Phase 7, feature/map1-prop-slots).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/map1_prop_slots_test.gd
##
## SPEC.md 13: plausible spots for LARGE objects in every room (all hiders
## can start large), plus medium/small scatter so transformed hiders blend
## among standing decoys. Decoys are colored StaticBody3D props — NEVER pure
## white, because white is reserved as the "untarnt" tell on players.
##
## Covers: slot counts (>= 9 large / >= 10 medium / >= 12 small), at least
## one large slot in EVERY room, containment in exactly one room, solid
## bodies with collision, no pure-white decoy, valid size classes, and
## clearance from the NPC spawn markers. Exits 0 / 1.

const MAP_SCENE_PATH := "res://maps/map1_house.tscn"
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
		printerr("[map1_prop_slots_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[map1_prop_slots_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[map1_prop_slots_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _run_tests() -> void:
	await process_frame
	var map: Node3D = (load(MAP_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(map)
	await process_frame

	var volumes: Array = []
	for area in map.find_children("*", "Area3D", true, false):
		if area.is_in_group("room_volume"):
			volumes.append(area)
	var npc_markers: Array = []
	for marker in map.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("npc_spawn"):
			npc_markers.append(marker)
	var slots: Array = []
	for node in map.find_children("*", "StaticBody3D", true, false):
		if node.is_in_group("prop_slot"):
			slots.append(node)

	print("[map1_prop_slots_test] slot inventory")
	var by_size := {"large": [], "medium": [], "small": []}
	var sizes_valid := true
	for slot in slots:
		if by_size.has(slot.size_class):
			by_size[slot.size_class].append(slot)
		else:
			sizes_valid = false
	_check(slots.size() >= 28, ">= 28 decoy slots on the map (%d)" % slots.size())
	_check(sizes_valid, "every slot declares a valid size class")
	_check(by_size["large"].size() >= 9, ">= 9 large decoys (%d)" % by_size["large"].size())
	_check(by_size["medium"].size() >= 10, ">= 10 medium decoys (%d)" % by_size["medium"].size())
	_check(by_size["small"].size() >= 12, ">= 12 small decoys (%d)" % by_size["small"].size())

	# SPEC.md 13: every room offers a plausible LARGE hiding spot.
	print("[map1_prop_slots_test] placement rules")
	var rooms_with_large := {}
	for slot in by_size["large"]:
		for volume in volumes:
			if volume.contains_global(slot.global_position):
				rooms_with_large[volume.room_id] = true
	_check(rooms_with_large.size() == 9,
			"every one of the 9 rooms holds a large decoy (%d)" % rooms_with_large.size())

	var contained_ok := true
	for slot in slots:
		var containing := 0
		for volume in volumes:
			if volume.contains_global(slot.global_position):
				containing += 1
		if containing != 1:
			contained_ok = false
			printerr("  slot %s sits in %d rooms" % [slot.name, containing])
	_check(contained_ok, "every slot sits strictly inside exactly one room")

	var clearance_ok := true
	for slot in slots:
		for marker in npc_markers:
			var flat_a: Vector3 = slot.global_position * Vector3(1, 0, 1)
			var flat_b: Vector3 = marker.global_position * Vector3(1, 0, 1)
			if flat_a.distance_to(flat_b) < 0.8:
				clearance_ok = false
				printerr("  slot %s crowds npc marker %s" % [slot.name, marker.name])
	_check(clearance_ok, "decoys keep >= 0.8 m clearance from NPC markers")

	# Solid, collidable, and NEVER the players' neutral white.
	print("[map1_prop_slots_test] decoy construction")
	var solid_ok := true
	var color_ok := true
	for slot in slots:
		var mesh: MeshInstance3D = null
		var shape: CollisionShape3D = null
		for child in slot.get_children():
			if child is MeshInstance3D:
				mesh = child
			elif child is CollisionShape3D:
				shape = child
		if mesh == null or shape == null or shape.shape == null:
			solid_ok = false
			continue
		var mat := mesh.get_active_material(0)
		if not (mat is StandardMaterial3D) \
				or (mat as StandardMaterial3D).albedo_color.is_equal_approx(WHITE):
			color_ok = false
	_check(solid_ok, "every decoy is a solid body (mesh + collision)")
	_check(color_ok, "no decoy wears the players' neutral white")

	root.remove_child(map)
	map.free()
	_finish()
