extends RefCounted
## 3D eyedropper (Phase 4, feature/eyedropper-and-colorpicker).
##
## SPEC.md 9.3: "Nimmt die exakte Farbe jeder angepeilten Oberfläche auf" —
## the eyedropper reads the SOURCE color of the aimed surface, never a lit
## screen pixel. Screen sampling would bake lighting and shadows into the
## result: non-deterministic, and a color nobody could reproduce by painting.
##
## Sampling rules, in order:
##   1. A painted player prop (any collider owning a `painter`) samples the
##      painted pixel at the hit point — exactly what the brush laid down.
##   2. Otherwise the first VISIBLE MeshInstance3D under the collider decides:
##      its albedo texture (if readable) sampled at the hit UV, modulated by
##      the albedo tint — for plain materials just the albedo color. This is
##      what the gray room and later flat-colored map surfaces resolve to.
##   3. No mesh or no readable StandardMaterial3D -> null; the caller keeps
##      its current color.
##
## No class_name on purpose (repo convention — preload by path).

const MeshUvLookup := preload("res://scripts/paint/mesh_uv_lookup.gd")

## Exact surface color at `world_point` on `collider`, or null when the
## surface offers nothing to sample.
static func sample_color(collider: Object, world_point: Vector3) -> Variant:
	if collider == null or not (collider is Node):
		return null
	# Painted player props sample their own paint pixels.
	var painter = collider.get("painter")
	if painter != null and painter.is_painted():
		var prop_mesh: MeshInstance3D = painter.bound_mesh_instance()
		if prop_mesh != null and is_instance_valid(prop_mesh):
			var uv := MeshUvLookup.uv_at_world_point(prop_mesh, world_point)
			if uv.x >= 0.0:
				return painter.color_at_uv(uv)
	var mesh_instance := _visible_mesh(collider)
	if mesh_instance == null or mesh_instance.mesh == null:
		return null
	var material := mesh_instance.get_active_material(0)
	if not (material is StandardMaterial3D):
		return null
	var tint: Color = material.albedo_color
	var texel = _sample_albedo_texture(material, mesh_instance, world_point)
	if texel is Color:
		return Color(tint.r * texel.r, tint.g * texel.g, tint.b * texel.b, 1.0)
	return Color(tint.r, tint.g, tint.b, 1.0)

## Godot multiplies albedo_color with the albedo texture — mirror that here.
## Returns the texel Color, or null when there is no readable texture.
static func _sample_albedo_texture(material: StandardMaterial3D,
		mesh_instance: MeshInstance3D, world_point: Vector3) -> Variant:
	var tex := material.albedo_texture
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img = img.duplicate()
		if img.decompress() != OK:
			return null  # unreadable (e.g. GPU-only format) — tint-only fallback
	var uv := MeshUvLookup.uv_at_world_point(mesh_instance, world_point)
	if uv.x < 0.0:
		return null
	var px := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
	var py := clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(px, py)

## First MeshInstance3D under `node` that is actually shown. A transformed
## capsule keeps its slime meshes in the tree but hidden — visibility decides
## which surface the player is really aiming at. Falls back to the first mesh
## found when nothing reports visible (out-of-tree previews).
static func _visible_mesh(node: Node) -> MeshInstance3D:
	var first: MeshInstance3D = null
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		if first == null:
			first = mesh_instance
		if mesh_instance.is_inside_tree() and mesh_instance.is_visible_in_tree():
			return mesh_instance
	return first
