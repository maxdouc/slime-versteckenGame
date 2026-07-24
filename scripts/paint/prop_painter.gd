extends RefCounted
## Per-player paint state + prop material binding (Phase 4,
## feature/paint-prototype; multi-mesh forms, fix/paint-all-meshes).
##
## No class_name on purpose (repo convention — consumers preload by path).
##
## Each player capsule owns exactly one painter. A form can be MULTI-PART — a
## Kenney furniture piece is several MeshInstance3D nodes (pot + plant, bed +
## blanket, basin + tap). The painter therefore holds a LIST of paint TARGETS,
## one per mesh, in the exact order the capsule traverses them
## (find_children("*", "MeshInstance3D", true, false) — the SAME order
## scripts/props/white_form.gd whitens, so "paintable" and "white" stay
## deckungsgleich). That list index is the stable network id a stroke carries
## (paint_sync.gd): traversal order is identical on every machine, so peer B
## paints the same part peer A did — never the wrong one, and never a fragile
## node instance id.
##
## Each target lazily owns a TEXTURE_SIZE² RGBA8 paint image (starts white,
## SPEC.md 9.1), its GPU ImageTexture, and a PER-INSTANCE duplicate of the
## mesh's material that is applied to ALL of that mesh's surfaces — so a mesh
## with several surfaces still paints fully, on ONE small texture (web budget:
## one 256² per mesh, never one per surface). Everything is LAZY: an unpainted
## target keeps the scene's pristine shared white material and allocates no
## image, so the browser pays 256 KB only per part actually painted.
##
## Lifecycle contract (player_capsule.gd): rebind_meshes() on every transform;
## the paint LIFETIME belongs to paint_epoch (the capsule wipes there on form
## change), so rebind KEEPS the images and only retargets them — network events
## may race the form change either way, and only an epoch bump wipes.
##
## stamp_uv() is the deterministic core: identical stamps in identical order on
## identical targets produce the bit-identical image on every machine (pure
## integer circle rasterization, no blending) — the paint event sync builds on
## that.

const MeshUvLookup := preload("res://scripts/paint/mesh_uv_lookup.gd")

const TEXTURE_SIZE := 256  # web-safe: README says keep per-prop paint textures small
const BRUSH_RADIUS_PX := 10  # the one fixed-size brush (SPEC.md 9.3)
const BASE_COLOR := Color(1, 1, 1, 1)  # neutral white base (SPEC.md 9.1)

## Hard cap on paintable meshes per form: the stroke event carries the target
## index in 5 bits (paint_sync.encode_stroke). Furniture forms have a handful
## of parts — this is only a guard against a pathological model.
const MAX_TARGETS := 32

## Color the fixed brush paints with. The prototype pins a readable red; the
## eyedropper/color-picker branch turns this into the player's selected color.
var brush_color := Color(0.82, 0.13, 0.10)

## One paintable mesh of the current form. Lazy: image/texture/material stay
## null until the part is first painted; original_overrides remembers the
## pristine per-surface override so unbind/clear restore the prop exactly.
class Target:
	var mesh: MeshInstance3D
	var image: Image
	var texture: ImageTexture
	var material: StandardMaterial3D
	var original_overrides: Array = []

## Targets in traversal (= network id) order. Index i is what a stroke event
## for this mesh carries; every peer resolves it against the same-ordered list.
var _targets: Array = []

## Whole-form base coat color (Grundieren), or null. A target created or
## re-bound after a fill starts from this instead of white, so every mesh of a
## multi-part form keeps the base coat — even when a paint event outruns the
## form change (paint_sync.gd epoch race) and a mesh is bound only afterwards.
var _fill_color = null

## Target a freshly instanced prop form's single mesh, dropping any paint — a
## new form always spawns neutral white. Kept for single-mesh callers (clones,
## focused tests); the capsule uses rebind_meshes() for the whole form.
func bind_prop(mesh_instance: MeshInstance3D) -> void:
	unbind()
	if mesh_instance != null:
		var t := Target.new()
		t.mesh = mesh_instance
		_targets.append(t)

## Bind every mesh of a form, dropping any paint. Order MUST be the capsule's
## traversal order so the target index matches the network id.
func bind_meshes(meshes: Array) -> void:
	unbind()
	for m in meshes:
		if m != null:
			var t := Target.new()
			t.mesh = m
			_targets.append(t)

## Re-target onto a new form's meshes KEEPING the paint state. Used by the
## capsule's _apply_form: the paint LIFETIME belongs to paint_epoch (wiped
## there), so the visual rebind must not wipe. Retained images follow BY INDEX
## onto the new meshes; a prior base coat re-covers all of them.
func rebind_meshes(meshes: Array) -> void:
	var kept_images: Array = []
	var kept_textures: Array = []
	for t in _targets:
		_restore_target(t)
		kept_images.append(t.image)
		kept_textures.append(t.texture)
	_targets = []
	for i in meshes.size():
		var t := Target.new()
		t.mesh = meshes[i]
		if i < kept_images.size():
			t.image = kept_images[i]
			t.texture = kept_textures[i]
		_targets.append(t)
	# Re-apply retained paint (and any base coat) onto the new meshes.
	for t in _targets:
		if t.image != null or _fill_color != null:
			_ensure_target_paint(t)

## Back to "no paintable prop": restore each mesh's pristine material and drop
## all state.
func unbind() -> void:
	for t in _targets:
		_restore_target(t)
	_targets = []
	_fill_color = null

## Alles-Löschen (SPEC.md 9.3): back to neutral white on EVERY part. A full
## reset to the lazy unpainted state — the pristine shared materials return and
## the paint memory is released — but the meshes stay bound, so painting can
## continue.
func clear_paint() -> void:
	for t in _targets:
		_restore_target(t)
		t.image = null
		t.texture = null
	_fill_color = null

## Primary bound mesh — the first still-valid one. Kept single-value for the
## eyedropper and focused tests; multi-part callers use world_point_to_target().
func bound_mesh_instance() -> MeshInstance3D:
	for t in _targets:
		if t.mesh != null and is_instance_valid(t.mesh):
			return t.mesh
	return null

func is_painted() -> bool:
	for t in _targets:
		if t.image != null:
			return true
	return false

## Live paint image of the primary painted part (null while unpainted).
## Read-only for callers — all paint goes through stamp_uv()/fill() so the GPU
## textures stay in sync. Multi-part callers read a specific part via its index.
func image() -> Image:
	for t in _targets:
		if t.image != null:
			return t.image
	return null

func texture() -> ImageTexture:
	for t in _targets:
		if t.texture != null:
			return t.texture
	return null

## Exact paint color at `uv` on target `index` — the base coat (or BASE_COLOR
## white) while that part is unpainted. The 3D eyedropper reads through this, so
## sampling a painted prop returns precisely what the brush laid down.
func color_at_uv(uv: Vector2, index := 0) -> Color:
	var t = _target_at(index)
	if t == null or t.image == null:
		return _fill_color if _fill_color != null else BASE_COLOR
	var px := clampi(int(uv.x * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var py := clampi(int(uv.y * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	return t.image.get_pixel(px, py)

## The paint TARGET (mesh index) and UV under a raycast hit — the closest mesh
## the point actually lands on, so a multi-part form paints the part the player
## aims at. {"target": -1, "uv": NO_UV} when nothing maps (unbound / off every
## paintable surface). The capsule turns this into a stroke EVENT carrying the
## target index; live painting never stamps directly since the event-sync branch.
func world_point_to_target(world_point: Vector3) -> Dictionary:
	var best_index := -1
	var best_dist := INF
	var best_uv: Vector2 = MeshUvLookup.NO_UV
	for i in _targets.size():
		var m: MeshInstance3D = _targets[i].mesh
		if m == null or not is_instance_valid(m):
			continue
		var res := MeshUvLookup.closest_at_world_point(m, world_point)
		if res["uv"].x < 0.0:
			continue
		if res["dist"] < best_dist:
			best_dist = res["dist"]
			best_uv = res["uv"]
			best_index = i
	return {"target": best_index, "uv": best_uv}

## UV of the closest paintable part under a world point (NO_UV when none). Thin
## wrapper for callers that only need the coordinate (paint_world_point).
func world_point_to_uv(world_point: Vector3) -> Vector2:
	return world_point_to_target(world_point)["uv"]

## Paint one brush stamp where a raycast hit the bound form — on the part the
## point lands on. Returns false when nothing maps. Local-only helper; the
## networked path goes target+uv -> PaintSync event -> stamp_uv on every peer.
func paint_world_point(world_point: Vector3) -> bool:
	var res := world_point_to_target(world_point)
	if int(res["target"]) < 0:
		return false
	stamp_uv(res["uv"], brush_color, int(res["target"]))
	return true

## One-click base coat (SPEC.md 9.3 Grundieren): cover EVERY pixel of EVERY
## part with `color`. Deterministic like stamp_uv, and it obsoletes all earlier
## strokes on the whole form — the event-sync branch compacts its history on this.
func fill(color: Color) -> void:
	var solid := Color(color.r, color.g, color.b, 1.0)
	_fill_color = solid
	if _targets.is_empty():
		_ensure_target(0)  # free painter (focused tests): fill still records paint
	for t in _targets:
		_ensure_target_paint(t)
		t.image.fill(solid)
		t.texture.update(t.image)

## Deterministic core: stamp a filled BRUSH_RADIUS_PX circle of `color` at `uv`
## (fractions of the texture, clamped to the edges) on target `index`.
func stamp_uv(uv: Vector2, color: Color, index := 0) -> void:
	var t = _ensure_target(index)
	_ensure_target_paint(t)
	var px := clampi(int(uv.x * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var py := clampi(int(uv.y * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var solid := Color(color.r, color.g, color.b, 1.0)
	var r := BRUSH_RADIUS_PX
	for y in range(maxi(py - r, 0), mini(py + r, TEXTURE_SIZE - 1) + 1):
		for x in range(maxi(px - r, 0), mini(px + r, TEXTURE_SIZE - 1) + 1):
			var dx := x - px
			var dy := y - py
			if dx * dx + dy * dy <= r * r:
				t.image.set_pixel(x, y, solid)
	t.texture.update(t.image)

## The target at `index`, or null when it does not exist — used by read-only
## paths (color_at_uv) that must not allocate.
func _target_at(index: int):
	if index < 0 or index >= _targets.size():
		return null
	return _targets[index]

## The target at `index`, growing the list with mesh-less targets as needed —
## covers the free painter (no bound mesh) and a paint event that outran the
## form change (a later rebind_meshes retargets the retained image by index).
func _ensure_target(index: int) -> Target:
	if index < 0:
		index = 0
	while _targets.size() <= index and _targets.size() < MAX_TARGETS:
		_targets.append(Target.new())
	if index >= _targets.size():  # clamped by MAX_TARGETS — treat as the last
		index = _targets.size() - 1
	return _targets[index]

## First paint action on a target: allocate its white (or base-coat) image +
## texture, then swap the bound mesh (if any) onto a per-instance duplicate of
## its active material, applied to ALL of that mesh's surfaces. The duplicate
## keeps the prop's look (roughness), stays neutral-white tinted, and is the
## only material that ever sees the paint texture — shared scene materials are
## never touched.
func _ensure_target_paint(t: Target) -> void:
	if t.image == null:
		t.image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		t.image.fill(_fill_color if _fill_color != null else BASE_COLOR)
		t.texture = ImageTexture.create_from_image(t.image)
	elif t.texture == null:
		t.texture = ImageTexture.create_from_image(t.image)
	if t.material == null and t.mesh != null and is_instance_valid(t.mesh) and t.mesh.mesh != null:
		var count := t.mesh.mesh.get_surface_count()
		t.original_overrides = []
		for s in count:
			t.original_overrides.append(t.mesh.get_surface_override_material(s))
		var source := t.mesh.get_active_material(0)
		t.material = source.duplicate() if source is StandardMaterial3D else StandardMaterial3D.new()
		t.material.albedo_color = BASE_COLOR
		t.material.albedo_texture = t.texture
		# The paint image carries no mipmaps (update() per stroke would have to
		# regenerate them) — plain linear filtering matches that.
		t.material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		for s in count:
			t.mesh.set_surface_override_material(s, t.material)

## Restore a target's pristine per-surface materials (if its mesh still exists
## and still shows our paint material) and drop the material binding. Keeps the
## image untouched — callers decide whether paint survives.
func _restore_target(t: Target) -> void:
	if t.material != null and t.mesh != null and is_instance_valid(t.mesh) and t.mesh.mesh != null:
		var count := t.mesh.mesh.get_surface_count()
		for s in count:
			if t.mesh.get_surface_override_material(s) == t.material:
				var orig = t.original_overrides[s] if s < t.original_overrides.size() else null
				t.mesh.set_surface_override_material(s, orig)
	t.material = null
	t.original_overrides = []
