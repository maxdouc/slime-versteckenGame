extends SceneTree
## Headless test — slime <-> white placeholder prop transformation (Phase 3,
## feature/transform-white-props).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/transform_test.gd
##
## Exercises the real player scene (scenes/player_capsule.tscn) plus the form
## registry (scripts/player_forms.gd) inside the real gray room: slime -> each
## prop size -> back to slime, repeated cycles, collision swaps, neutral-white
## material guarantees, and the remote-copy camera contract. Local only — the
## networked form sync is a later branch (feature/network-transform-state).
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
		printerr("[transform_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[transform_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[transform_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _run_tests() -> void:
	await process_frame

	# --- Form registry ------------------------------------------------------
	print("[transform_test] form registry")
	var forms: GDScript = null
	if ResourceLoader.exists(FORMS_SCRIPT_PATH):
		forms = load(FORMS_SCRIPT_PATH)
	_check(forms != null, "scripts/player_forms.gd exists and loads")

	var prop_ids: Array = []
	if forms != null and forms.get("PROPS") != null and forms.get("Size") != null:
		var sizes: Dictionary = forms.Size
		_check(sizes.has("SLIME") and sizes.has("SMALL") and sizes.has("MEDIUM") and sizes.has("LARGE"),
				"Size enum covers SLIME/SMALL/MEDIUM/LARGE")
		_check(forms.get("SLIME") is String and forms.SLIME != "",
				"SLIME form id is a non-empty String")
		for wanted in ["SMALL", "MEDIUM", "LARGE"]:
			var prop_id: String = forms.first_prop_of_size(sizes[wanted])
			_check(prop_id != "", "registry has a %s prop" % wanted)
			if prop_id != "":
				prop_ids.append(prop_id)
		for prop_id in prop_ids:
			var def: Dictionary = forms.PROPS[prop_id]
			_check(def.get("display_name", "") != "", "%s: has display_name" % prop_id)
			_check(ResourceLoader.exists(def.get("scene", "")), "%s: visual scene exists" % prop_id)
			var shape = forms.collision_shape(prop_id)
			_check(shape is Shape3D and not (shape is CapsuleShape3D),
					"%s: has its own non-slime collision shape" % prop_id)
		var slime_shape = forms.collision_shape(forms.SLIME)
		_check(slime_shape is CapsuleShape3D
				and is_equal_approx(slime_shape.radius, 0.4)
				and is_equal_approx(slime_shape.height, 1.8)
				and forms.collision_origin(forms.SLIME).is_equal_approx(Vector3(0.0, 0.9, 0.0)),
				"slime collision matches the Phase 2 capsule (r 0.4, h 1.8, y 0.9)")
	else:
		_check(false, "registry exposes PROPS + Size (skipping registry detail checks)")

	# --- Prop visual scenes are neutral white -------------------------------
	print("[transform_test] prop scenes")
	for prop_id in prop_ids:
		var scene: PackedScene = load(forms.PROPS[prop_id]["scene"])
		var instance: Node = scene.instantiate()
		_check_meshes_white(instance, "scene %s" % prop_id)
		instance.free()

	# --- Local player: baseline slime state ---------------------------------
	print("[transform_test] local player baseline")
	var room: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room)
	var player: CharacterBody3D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = "1"  # matches the offline unique id -> local authority
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)
	await physics_frame
	await physics_frame
	for i in 90:  # let the spawn drop finish before judging floor contact
		if player.is_on_floor():
			break
		await physics_frame
	_check(player.is_on_floor(), "slime settles on the floor after spawn")

	var slime_visual: Node3D = player.get_node_or_null("Visual/SlimeVisual")
	var prop_anchor: Node3D = player.get_node_or_null("Visual/PropAnchor")
	var collision: CollisionShape3D = player.get_node_or_null("CollisionShape3D")
	_check(slime_visual != null, "player has $Visual/SlimeVisual")
	_check(prop_anchor != null, "player has $Visual/PropAnchor")
	_check(player.get_node_or_null("Visual") != null, "synced $Visual node path unchanged")
	_check(player.has_method("transform_to_prop") and player.has_method("transform_to_slime"),
			"player exposes transform_to_prop()/transform_to_slime()")
	_check(player.get("form_id") != null, "player exposes form_id")
	if forms == null or slime_visual == null or prop_anchor == null \
			or not player.has_method("transform_to_prop") or player.get("form_id") == null:
		_check(false, "transform API missing — skipping behavior checks")
		_finish()
		return

	_check(player.form_id == forms.SLIME, "spawns in slime form")
	_check(slime_visual.visible, "slime visual visible on spawn")
	_check(prop_anchor.get_child_count() == 0, "prop anchor empty on spawn")
	_check(collision.shape is CapsuleShape3D, "slime collision is the capsule")
	_check(player.get_node_or_null("CameraPivot") != null, "local player keeps its camera rig")

	# --- Transform into each size, largest first ----------------------------
	for wanted in ["LARGE", "MEDIUM", "SMALL"]:
		var prop_id: String = forms.first_prop_of_size(forms.Size[wanted])
		print("[transform_test] transform -> %s (%s)" % [prop_id, wanted])
		player.transform_to_prop(prop_id)
		_check(player.form_id == prop_id, "%s: form_id updated" % prop_id)
		_check(not slime_visual.visible, "%s: slime visual hidden" % prop_id)
		_check(prop_anchor.get_child_count() == 1, "%s: exactly one prop visual" % prop_id)
		_check(collision.shape == forms.collision_shape(prop_id),
				"%s: collision shape swapped from the registry" % prop_id)
		_check(collision.position.is_equal_approx(forms.collision_origin(prop_id)),
				"%s: collision origin from the registry" % prop_id)
		_check_meshes_white(prop_anchor, "instanced %s" % prop_id)
		for i in 45:
			if player.is_on_floor():
				break
			await physics_frame
		_check(player.is_on_floor(), "%s: stands on the floor" % prop_id)
		_check(player.position.y > -0.5 and player.position.y < 1.5,
				"%s: did not sink or launch (y=%.2f)" % [prop_id, player.position.y])

	# --- Back to slime -------------------------------------------------------
	print("[transform_test] back to slime")
	player.transform_to_slime()
	_check(player.form_id == forms.SLIME, "form_id back to slime")
	_check(slime_visual.visible, "slime visual visible again")
	_check(prop_anchor.get_child_count() == 0, "prop anchor emptied")
	_check(collision.shape is CapsuleShape3D
			and is_equal_approx(collision.shape.radius, 0.4)
			and is_equal_approx(collision.shape.height, 1.8),
			"slime capsule restored (r 0.4, h 1.8)")
	_check(collision.position.is_equal_approx(Vector3(0.0, 0.9, 0.0)),
			"slime collision origin restored")

	# --- Idempotence + unknown ids -------------------------------------------
	print("[transform_test] idempotence and bad input")
	var large_id: String = forms.first_prop_of_size(forms.Size.LARGE)
	player.transform_to_prop(large_id)
	player.transform_to_prop(large_id)
	_check(prop_anchor.get_child_count() == 1, "same-form transform twice keeps one visual")
	print("  (an engine WARNING about an unknown prop id is expected next)")
	player.transform_to_prop("no_such_prop")
	_check(player.form_id == large_id, "unknown prop id leaves the form unchanged")
	_check(prop_anchor.get_child_count() == 1, "unknown prop id leaves one visual")
	player.transform_to_slime()
	player.transform_to_slime()
	_check(slime_visual.visible and prop_anchor.get_child_count() == 0,
			"double transform_to_slime stays clean")

	# --- Repeated cycles never stack visuals ---------------------------------
	print("[transform_test] repeated transform cycles")
	var cycle_clean := true
	for cycle in 3:
		for wanted in ["SMALL", "LARGE", "MEDIUM"]:
			player.transform_to_prop(forms.first_prop_of_size(forms.Size[wanted]))
			if prop_anchor.get_child_count() != 1 or slime_visual.visible:
				cycle_clean = false
		player.transform_to_slime()
		if prop_anchor.get_child_count() != 0 or not slime_visual.visible:
			cycle_clean = false
		await physics_frame
	_check(cycle_clean, "3 full cycles: always exactly one visible form")

	# --- Slime cosmetics must never leak into prop color ----------------------
	print("[transform_test] slime color independence (SPEC.md 9.1)")
	var body: MeshInstance3D = player.get_node("Visual/SlimeVisual/Body")
	var green: StandardMaterial3D = body.get_active_material(0).duplicate()
	green.albedo_color = Color(0.2, 0.9, 0.3, 1.0)
	body.set_surface_override_material(0, green)
	for prop_id in prop_ids:
		player.transform_to_prop(prop_id)
		_check_meshes_white(prop_anchor, "%s with green slime skin" % prop_id)
	player.transform_to_slime()

	# --- Remote copy contract (regression from Phase 2) -----------------------
	print("[transform_test] remote copy contract")
	var remote: CharacterBody3D = load(PLAYER_SCENE_PATH).instantiate()
	remote.name = "2"  # not the offline unique id -> remote copy
	remote.position = Vector3(2.0, 1.0, 0.0)
	root.add_child(remote)
	await process_frame
	await process_frame
	_check(remote.get_node_or_null("CameraPivot") == null, "remote copy frees its camera rig")
	# Since the ghost-collider hardening, copies DO keep _physics_process — but
	# only to pin their collider to the synced transform. The contract is
	# behavioral: a copy never SIMULATES itself (no gravity, no movement).
	var parked: Vector3 = remote.position
	remote.velocity = Vector3(3.0, 0.0, 0.0)  # a simulating body would drift
	for _i in 12:
		await process_frame
	_check(remote.position.is_equal_approx(parked),
			"remote copy runs no local simulation (parked in mid-air, no drift)")
	var local_cam: Camera3D = player.get_node("CameraPivot/SpringArm3D/Camera3D")
	_check(root.get_camera_3d() == local_cam, "the local player's camera stays current")
	_check(remote.get_node_or_null("Visual/SlimeVisual") != null
			and remote.get_node("Visual/SlimeVisual").visible,
			"remote copy spawns visible as slime")

	_finish()

## Every MeshInstance3D under `node` must render pure neutral white — a plain
## StandardMaterial3D, albedo (1,1,1,1), no albedo texture (SPEC.md 9.1).
func _check_meshes_white(node: Node, where: String) -> void:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() > 0, "%s: has at least one mesh" % where)
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			_check(false, "%s: %s has no mesh resource" % [where, mesh_instance.name])
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			var white_ok: bool = material is StandardMaterial3D \
					and material.albedo_color == WHITE \
					and material.albedo_texture == null
			_check(white_ok, "%s: %s surface %d is neutral white" % [where, mesh_instance.name, surface])
