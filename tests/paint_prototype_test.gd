extends SceneTree
## Headless test — raycast paint prototype (Phase 4, feature/paint-prototype).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/paint_prototype_test.gd
##
## Covers the three paint-prototype pieces without any networking:
##   1. mesh_uv_lookup.gd — surface point -> stable UV via closest-triangle
##      barycentric interpolation, layout-agnostic (ground truth comes from the
##      mesh's own surface arrays), robust to points slightly off the visual
##      surface (the collision volume is not the visual mesh on tapered props).
##   2. prop_painter.gd — 256x256 web-safe paint texture per painter, lazy
##      material binding (an unpainted prop keeps the pristine shared white
##      material, SPEC.md 9.1), fixed-size brush stamps, per-instance
##      independence (painting one prop instance never touches another one or
##      the shared scene material).
##   3. player_capsule.gd integration — every capsule owns a painter; the
##      painter binds/unbinds with the transform lifecycle and paint dies on
##      any form change (SPEC.md 9.1: back to slime wipes the paint job).
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const UV_LOOKUP_PATH := "res://scripts/paint/mesh_uv_lookup.gd"
const PAINTER_PATH := "res://scripts/paint/prop_painter.gd"
const FORMS_SCRIPT_PATH := "res://scripts/player_forms.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const CARTON_SCENE_PATH := "res://scenes/props/prop_carton.tscn"
const TIMEOUT_SEC := 60.0
const WHITE := Color(1, 1, 1, 1)
const UV_EPS := 0.002

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		printerr("[paint_prototype_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[paint_prototype_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[paint_prototype_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

## RGBA8 storage quantizes colors, so compare with a tolerance of ~1.5/255.
func _color_close(a: Color, b: Color, tol := 0.007) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
			and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol

func _run_tests() -> void:
	await process_frame

	# --- Scripts exist and load ------------------------------------------------
	print("[paint_prototype_test] scripts load")
	var lookup: GDScript = load(UV_LOOKUP_PATH) if ResourceLoader.exists(UV_LOOKUP_PATH) else null
	var painter_script: GDScript = load(PAINTER_PATH) if ResourceLoader.exists(PAINTER_PATH) else null
	_check(lookup != null, "scripts/paint/mesh_uv_lookup.gd exists and loads")
	_check(painter_script != null, "scripts/paint/prop_painter.gd exists and loads")
	if lookup == null or painter_script == null:
		_finish()
		return

	# --- UV lookup: triangle centroids map to UV centroids (layout-agnostic) ---
	print("[paint_prototype_test] uv lookup: triangle centroids")
	var box := BoxMesh.new()
	box.size = Vector3(1.1, 1.1, 1.1)
	_check_centroids(lookup, box, 1, "BoxMesh (carton)")
	var bucket := CylinderMesh.new()
	bucket.top_radius = 0.32
	bucket.bottom_radius = 0.26
	bucket.height = 0.55
	_check_centroids(lookup, bucket, 37, "CylinderMesh (bucket, tapered)")

	# --- UV lookup: known box atlas cell ---------------------------------------
	# Godot's BoxMesh atlas puts +Y in u [1/3..2/3], v [1/2..1]; its face center
	# must land in the cell center. Pins the box top for the capsule test below.
	var top_uv: Vector2 = lookup.uv_at_local_point(box, Vector3(0.0, 0.55, 0.0))
	_check(top_uv.distance_to(Vector2(0.5, 0.75)) < UV_EPS,
			"box +Y face center maps to its atlas cell center (got %s)" % top_uv)

	# --- UV lookup: points slightly OFF the surface still map ------------------
	# The bucket's collision cylinder (r 0.32 everywhere) sticks out past the
	# tapered visual near the floor; a raycast hit there must still paint.
	var off_uv: Vector2 = lookup.uv_at_local_point(bucket, Vector3(0.32, -0.22, 0.0))
	_check(off_uv.x >= -0.0001 and off_uv.x <= 1.0001
			and off_uv.y >= -0.0001 and off_uv.y <= 0.5001,
			"point outside the tapered bucket maps into the side UV band (got %s)" % off_uv)
	var above_uv: Vector2 = lookup.uv_at_local_point(box, Vector3(0.1, 0.60, 0.1))
	var exact_uv: Vector2 = lookup.uv_at_local_point(box, Vector3(0.1, 0.55, 0.1))
	_check(exact_uv.x >= 0.0 and above_uv.distance_to(exact_uv) < UV_EPS,
			"point 5 cm above the box top maps like the surface point")

	# --- UV lookup: world-space variant handles full transforms ----------------
	print("[paint_prototype_test] uv lookup: world transform")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	root.add_child(mesh_instance)
	mesh_instance.position = Vector3(3.0, 2.0, 1.0)
	mesh_instance.rotation.y = 0.7
	mesh_instance.scale = Vector3(1.1, 0.9, 1.1)  # squash-like non-uniform scale
	var local_probe := Vector3(0.2, 0.55, -0.3)
	var world_probe: Vector3 = mesh_instance.global_transform * local_probe
	var world_uv: Vector2 = lookup.uv_at_world_point(mesh_instance, world_probe)
	var local_uv: Vector2 = lookup.uv_at_local_point(box, local_probe)
	_check(local_uv.x >= 0.0 and world_uv.distance_to(local_uv) < UV_EPS,
			"world-space lookup matches local lookup under translate+yaw+scale")
	root.remove_child(mesh_instance)
	mesh_instance.free()

	# --- Painter: fresh state is unpainted and lazy ----------------------------
	print("[paint_prototype_test] painter: lazy neutral-white baseline")
	var carton_scene: PackedScene = load(CARTON_SCENE_PATH)
	var prop_a: Node = carton_scene.instantiate()
	var prop_b: Node = carton_scene.instantiate()
	root.add_child(prop_a)
	root.add_child(prop_b)
	var mesh_a: MeshInstance3D = prop_a.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh_b: MeshInstance3D = prop_b.find_children("*", "MeshInstance3D", true, false)[0]
	var shared_material: StandardMaterial3D = mesh_a.get_active_material(0)
	_check(shared_material == mesh_b.get_active_material(0),
			"precondition: both carton instances share one scene material")

	# The prop scenes ship their shared white material in the OVERRIDE slot
	# (surface_material_override/0 in the .tscn), so "pristine" means "override
	# still is that shared material" — and unbinding must restore it.
	var painter_a: RefCounted = painter_script.new()
	var painter_b: RefCounted = painter_script.new()
	_check(painter_a.get("brush_color") != null, "painter exposes brush_color")
	_check(int(painter_a.TEXTURE_SIZE) == 256, "paint texture is 256x256 (web-safe)")
	_check(not painter_a.is_painted(), "fresh painter reports unpainted")
	_check(painter_a.image() == null, "fresh painter allocates no image (lazy)")
	painter_a.bind_prop(mesh_a)
	painter_b.bind_prop(mesh_b)
	_check(painter_a.bound_mesh_instance() == mesh_a, "bind_prop remembers the mesh")
	_check(not painter_a.is_painted(), "binding alone does not paint")
	_check(mesh_a.get_surface_override_material(0) == shared_material,
			"binding alone leaves the pristine shared white material in place (lazy)")

	# --- Painter: one stamp paints a circle at the UV --------------------------
	print("[paint_prototype_test] painter: fixed-size brush stamp")
	var red := Color(0.82, 0.13, 0.10)
	painter_a.stamp_uv(Vector2(0.5, 0.75), red)
	_check(painter_a.is_painted(), "stamp marks the painter painted")
	var image_a: Image = painter_a.image()
	_check(image_a != null and image_a.get_width() == 256 and image_a.get_height() == 256,
			"stamp lazily allocates the 256x256 image")
	if image_a == null:
		_check(false, "no image — skipping the remaining painter checks")
		_finish()
		return
	_check(_color_close(image_a.get_pixel(128, 192), red),
			"pixel at the stamp center took the brush color")
	var radius: int = painter_a.BRUSH_RADIUS_PX
	_check(_color_close(image_a.get_pixel(128 + radius - 1, 192), red),
			"pixel just inside the brush radius is painted")
	_check(_color_close(image_a.get_pixel(128 + radius + 2, 192), WHITE),
			"pixel just outside the brush radius stays white")
	_check(_color_close(image_a.get_pixel(4, 4), WHITE), "far corner stays neutral white")

	# --- Painter: material binds lazily, per instance, neutral base -----------
	print("[paint_prototype_test] painter: per-instance material")
	var override_a: StandardMaterial3D = mesh_a.get_surface_override_material(0)
	_check(override_a != null, "first stamp binds an override material")
	if override_a != null:
		_check(override_a != shared_material, "override is a per-instance duplicate")
		_check(override_a.albedo_texture == painter_a.texture(),
				"override shows the painter's texture")
		_check(override_a.albedo_color == WHITE, "override keeps the neutral white base tint")
		_check(is_equal_approx(override_a.roughness, shared_material.roughness),
				"override inherits the prop's surface look (roughness)")
	_check(shared_material.albedo_texture == null,
			"the shared scene material never gains a texture")
	_check(mesh_b.get_surface_override_material(0) == shared_material,
			"painting instance A leaves instance B pristine")
	_check(not painter_b.is_painted(), "painter B stays unpainted")

	painter_b.stamp_uv(Vector2(0.1, 0.1), Color(0.1, 0.3, 0.9))
	var image_b: Image = painter_b.image()
	_check(image_b != null and painter_b.texture() != painter_a.texture(),
			"painter B gets its own texture")
	_check(mesh_b.get_surface_override_material(0) != override_a,
			"painter B gets its own material")
	_check(_color_close(image_a.get_pixel(25, 25), WHITE),
			"B's stamp did not bleed into A's image")

	# --- Painter: edge stamps clamp, world-point painting works ----------------
	print("[paint_prototype_test] painter: edges and world points")
	painter_a.stamp_uv(Vector2(1.0, 1.0), red)
	_check(_color_close(painter_a.image().get_pixel(255, 255), red),
			"stamp at uv (1,1) clamps to the last pixel without errors")
	var top_center: Vector3 = mesh_a.global_transform * Vector3(0.0, 0.55, 0.0)
	var painted: bool = painter_a.paint_world_point(top_center)
	_check(painted, "paint_world_point hits the bound mesh")
	_check(_color_close(painter_a.image().get_pixel(128, 192), painter_a.brush_color),
			"paint_world_point stamps the brush color at the box-top UV")

	# --- Painter: stateless stamps (no bound mesh) still record paint ----------
	var painter_free: RefCounted = painter_script.new()
	painter_free.stamp_uv(Vector2(0.5, 0.5), red)
	_check(painter_free.is_painted() and painter_free.image() != null,
			"stamping without a bound mesh still records paint state")

	# --- Painter: unbind restores the pristine prop -----------------------------
	painter_a.unbind()
	_check(mesh_a.get_surface_override_material(0) == shared_material,
			"unbind restores the shared white override material")
	_check(not painter_a.is_painted() and painter_a.image() == null,
			"unbind resets the paint state")

	root.remove_child(prop_a)
	prop_a.free()
	root.remove_child(prop_b)
	prop_b.free()

	# --- Capsule integration: painter follows the transform lifecycle ----------
	print("[paint_prototype_test] capsule: painter lifecycle")
	var forms: GDScript = load(FORMS_SCRIPT_PATH)
	var player: CharacterBody3D = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	player.name = "1"  # offline unique id -> local authority
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)
	await process_frame
	if player.get("painter") == null:
		_check(false, "capsule exposes a painter — skipping capsule checks")
	else:
		_check(true, "capsule exposes a painter")
		_check(InputMap.has_action("paint_mode"), "paint_mode input action is registered")
		_check(player.painter.bound_mesh_instance() == null, "slime spawn: painter unbound")

		player.transform_to_prop("carton")
		var prop_mesh: MeshInstance3D = null
		var anchor_meshes: Array[Node] = player.get_node("Visual/PropAnchor") \
				.find_children("*", "MeshInstance3D", true, false)
		if anchor_meshes.size() > 0:
			prop_mesh = anchor_meshes[0]
		_check(prop_mesh != null and player.painter.bound_mesh_instance() == prop_mesh,
				"transforming binds the painter to the prop mesh")
		_check(not player.painter.is_painted(), "fresh prop starts unpainted")

		var pristine_override: Material = prop_mesh.get_surface_override_material(0)
		var world_top: Vector3 = prop_mesh.global_transform * Vector3(0.0, 0.55, 0.0)
		_check(player.painter.paint_world_point(world_top), "painting own prop works")
		_check(player.painter.is_painted(), "capsule painter records the stroke")
		var stroke_override: Material = prop_mesh.get_surface_override_material(0)
		_check(stroke_override != pristine_override and stroke_override is StandardMaterial3D
				and stroke_override.albedo_texture == player.painter.texture(),
				"stroke binds the per-instance paint material on the capsule prop")

		player.transform_to_prop("bucket")
		_check(not player.painter.is_painted(),
				"switching to another form wipes the paint (props spawn white)")
		_check(player.painter.bound_mesh_instance() != prop_mesh,
				"painter rebinds to the new form's mesh")

		var bucket_mesh: MeshInstance3D = player.painter.bound_mesh_instance()
		if bucket_mesh != null:
			var side_point: Vector3 = bucket_mesh.global_transform * Vector3(0.0, 0.0, 0.29)
			player.painter.paint_world_point(side_point)
		_check(player.painter.is_painted(), "painting the bucket works after rebind")

		player.transform_to_slime()
		_check(not player.painter.is_painted(),
				"returning to slime wipes the paint (SPEC.md 9.1)")
		_check(player.painter.bound_mesh_instance() == null,
				"returning to slime unbinds the painter")

	player.queue_free()
	await process_frame
	_finish()

## Every triangle's centroid must map to the centroid of its UVs — exact for
## barycentric interpolation, no assumptions about the mesh's UV layout.
## `stride` samples every Nth triangle to keep big meshes fast.
func _check_centroids(lookup: GDScript, mesh: Mesh, stride: int, label: String) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tri_count := idx.size() / 3
	var tested := 0
	var bad := 0
	var t := 0
	while t < tri_count:
		var a := verts[idx[t * 3]]
		var b := verts[idx[t * 3 + 1]]
		var c := verts[idx[t * 3 + 2]]
		var uv_want := (uvs[idx[t * 3]] + uvs[idx[t * 3 + 1]] + uvs[idx[t * 3 + 2]]) / 3.0
		var uv_got: Vector2 = lookup.uv_at_local_point(mesh, (a + b + c) / 3.0)
		tested += 1
		if uv_got.distance_to(uv_want) > UV_EPS:
			bad += 1
			if bad <= 3:
				printerr("    tri %d: want %s got %s" % [t, uv_want, uv_got])
		t += stride
	_check(bad == 0, "%s: %d sampled triangle centroids map exactly (bad: %d)" % [label, tested, bad])
