extends SceneTree
## Headless test — the furniture form set (feature/prop-set-matches-map).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/prop_forms_test.gd
##
## The transform system grew from three primitive placeholders to a full set of
## Kenney furniture forms so hiders can disguise as the pieces that actually
## stand in Map 1. This test guards the two things that could regress:
##
##   1. SPEC.md 9.1 — EVERY form still spawns neutral white in the tree, even
##      though the furniture reuses the COLORED map-decoy meshes (the white
##      comes from scripts/props/white_form.gd, applied on _ready). transform_
##      test only instantiates the first prop of each size; this checks all of
##      them, live in the tree, which is the only place the override runs.
##   2. Each size class offers several forms, ordered so index 0 is the
##      placeholder, and the capsule's size key CYCLES through them (wrapping),
##      driving the real _cycle_form path with the eat gate open (lobby).
##
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const FORMS_SCRIPT_PATH := "res://scripts/player_forms.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
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
		printerr("[prop_forms_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
		_done = true
		quit(1)
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
		print("[prop_forms_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[prop_forms_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _run_tests() -> void:
	await process_frame
	var forms: GDScript = load(FORMS_SCRIPT_PATH)

	# --- Registry: several forms per class, placeholder first -----------------
	print("[prop_forms_test] registry per size")
	for wanted in ["SMALL", "MEDIUM", "LARGE"]:
		var ids: Array = forms.prop_ids_of_size(forms.Size[wanted])
		_check(ids.size() >= 2, "%s class offers several forms (%d)" % [wanted, ids.size()])
		_check(ids[0] == forms.first_prop_of_size(forms.Size[wanted]),
				"%s: prop_ids_of_size[0] == first_prop_of_size" % wanted)
		for prop_id in ids:
			_check(forms.size_of(prop_id) == forms.Size[wanted],
					"%s: %s reports its class" % [wanted, prop_id])

	# --- Every form: valid definition + non-slime collision -------------------
	print("[prop_forms_test] every form definition")
	for prop_id in forms.PROPS:
		var def: Dictionary = forms.PROPS[prop_id]
		_check(def.get("display_name", "") != "", "%s: has display_name" % prop_id)
		_check(ResourceLoader.exists(def.get("scene", "")), "%s: visual scene exists" % prop_id)
		var shape = forms.collision_shape(prop_id)
		_check(shape is Shape3D and not (shape is CapsuleShape3D),
				"%s: has its own non-slime collision shape" % prop_id)

	# --- Every form spawns neutral white IN THE TREE (SPEC.md 9.1) ------------
	print("[prop_forms_test] neutral-white guarantee (live in the tree)")
	for prop_id in forms.PROPS:
		var instance: Node = load(forms.PROPS[prop_id]["scene"]).instantiate()
		root.add_child(instance)  # add_child runs white_form._ready() synchronously
		await process_frame
		_check_meshes_white(instance, "form %s" % prop_id)
		root.remove_child(instance)
		instance.free()

	# --- The capsule's size key cycles through a class, wrapping ---------------
	print("[prop_forms_test] size-key cycling through a class")
	var room: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room)
	var player: CharacterBody3D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = "1"  # offline unique id -> local authority
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)
	await process_frame
	await process_frame

	var large_ids: Array = forms.prop_ids_of_size(forms.Size.LARGE)
	# First press from slime enters the class at index 0.
	player._cycle_form(forms.Size.LARGE)
	_check(player.form_id == large_ids[0],
			"first LARGE press picks index 0 (%s)" % large_ids[0])
	# Each further press steps to the next form of the class.
	var stepped_ok := true
	for i in range(1, large_ids.size()):
		player._cycle_form(forms.Size.LARGE)
		if player.form_id != large_ids[i]:
			stepped_ok = false
	_check(stepped_ok, "repeated LARGE presses step through every large form in order")
	# One more press wraps back to the start.
	player._cycle_form(forms.Size.LARGE)
	_check(player.form_id == large_ids[0], "one more press wraps back to index 0")
	# Pressing a different class jumps to that class at index 0.
	var small_ids: Array = forms.prop_ids_of_size(forms.Size.SMALL)
	player._cycle_form(forms.Size.SMALL)
	_check(player.form_id == small_ids[0],
			"switching class enters SMALL at index 0 (%s)" % small_ids[0])

	_finish()

## Every MeshInstance3D under `node` must render pure neutral white — a plain
## StandardMaterial3D, albedo (1,1,1,1), no albedo texture (SPEC.md 9.1).
func _check_meshes_white(node: Node, where: String) -> void:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() > 0, "%s: has at least one mesh" % where)
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue  # empty pivots inside a .glb carry no surfaces to color
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			var white_ok: bool = material is StandardMaterial3D \
					and material.albedo_color == WHITE \
					and material.albedo_texture == null
			_check(white_ok, "%s: %s surface %d is neutral white" % [where, mesh_instance.name, surface])
