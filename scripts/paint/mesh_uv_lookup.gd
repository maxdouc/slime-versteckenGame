extends RefCounted
## Surface point -> stable UV coordinate for the paint system (Phase 4,
## feature/paint-prototype).
##
## No class_name on purpose: consumers preload this script by path (repo
## convention, see scripts/player_forms.gd) so headless --script runs never
## depend on the editor's global class cache.
##
## Why triangles instead of per-primitive math: raycast hits land on the
## COLLISION volume (player_forms.gd swaps the CharacterBody3D shape), which on
## the tapered props (bucket, cup) is not the visual surface — hits can sit a
## few centimeters off the mesh. Mapping a hit through the actual render
## triangles — closest triangle, then barycentric UV interpolation — is exact
## on the surface, tolerant to off-surface points, and works for ANY future
## mesh (Kenney props) without knowing its UV layout. It is also fully
## deterministic, which the paint event sync depends on.
##
## Triangle tables are cached per mesh RID. The placeholder prop meshes are
## shared resources, so each table builds once (box: 12 triangles, the
## cylinders: ~768) and the cache stays a handful of entries.

## Returned when a mesh has no usable triangles/UVs; callers test `uv.x < 0.0`.
## Every VALID uv is wrapped into [0,1) before it is returned (see _wrap01), so
## this negative sentinel is never confused with a real coordinate — the Kenney
## furniture meshes use tiled atlas UVs that run far outside [0,1] (bed cover
## reaches ±74, the potted plant ±21), and the GPU samples their REPEAT-mode
## textures wrapped. Painting must hit the SAME texel the surface shows, so the
## lookup wraps too; without it out-of-range UVs would be rejected (negative) or
## clamped onto the texture border (a smear) instead of landing under the brush.
const NO_UV := Vector2(-1.0, -1.0)

static var _cache: Dictionary = {}

## World-space variant: transforms through the mesh instance's global
## transform, which absorbs the capsule's visual yaw and the squash
## animation's non-uniform scale.
static func uv_at_world_point(mesh_instance: MeshInstance3D, world_point: Vector3) -> Vector2:
	return closest_at_world_point(mesh_instance, world_point)["uv"]

## UV at the point on the mesh surface closest to `local_point`.
static func uv_at_local_point(mesh: Mesh, local_point: Vector3) -> Vector2:
	return _closest_local(mesh, local_point)["uv"]

## Closest surface point of ONE mesh instance to `world_point`, as
## {"uv": Vector2, "dist": float} in WORLD units — so a caller holding several
## meshes (a multi-part form) can pick the one the ray actually points at.
## Returns {"uv": NO_UV, "dist": INF} for a mesh with no paintable triangles.
static func closest_at_world_point(mesh_instance: MeshInstance3D, world_point: Vector3) -> Dictionary:
	if mesh_instance == null or mesh_instance.mesh == null:
		return {"uv": NO_UV, "dist": INF}
	var xf := mesh_instance.global_transform
	var res := _closest_local(mesh_instance.mesh, xf.affine_inverse() * world_point)
	if res["uv"].x < 0.0:
		return {"uv": NO_UV, "dist": INF}
	var world_closest: Vector3 = xf * res["point"]
	return {"uv": res["uv"], "dist": world_point.distance_to(world_closest)}

## UV plus the closest surface point (local space) for `local_point`, as
## {"uv": Vector2, "point": Vector3}. UV is NO_UV when the mesh has no
## paintable triangles.
static func _closest_local(mesh: Mesh, local_point: Vector3) -> Dictionary:
	var tris: Array = _triangles(mesh)
	var verts: PackedVector3Array = tris[0]
	var uvs: PackedVector2Array = tris[1]
	if verts.is_empty():
		return {"uv": NO_UV, "point": Vector3.ZERO}
	var best_dist := INF
	var best_uv := NO_UV
	var best_point := Vector3.ZERO
	for t in range(0, verts.size(), 3):
		var bary := _closest_point_barycentric(local_point, verts[t], verts[t + 1], verts[t + 2])
		var closest := verts[t] * bary.x + verts[t + 1] * bary.y + verts[t + 2] * bary.z
		var dist := local_point.distance_squared_to(closest)
		if dist < best_dist:
			best_dist = dist
			best_uv = uvs[t] * bary.x + uvs[t + 1] * bary.y + uvs[t + 2] * bary.z
			best_point = closest
	# Wrap into [0,1) to mirror GPU REPEAT sampling (tiled atlas meshes) — an
	# in-range uv, including exactly 1.0, is left untouched so the placeholder
	# props map identically to before.
	return {"uv": Vector2(_wrap01(best_uv.x), _wrap01(best_uv.y)), "point": best_point}

## Fold a UV component into [0,1). Values already in [0,1] (the placeholder
## props) pass through unchanged; out-of-range atlas UVs wrap like the shader's
## repeat mode.
static func _wrap01(v: float) -> float:
	if v >= 0.0 and v <= 1.0:
		return v
	return fposmod(v, 1.0)

## Flat triangle table [PackedVector3Array verts, PackedVector2Array uvs],
## three entries per triangle, indices resolved. Surfaces without UVs are
## skipped — they cannot carry paint.
static func _triangles(mesh: Mesh) -> Array:
	var key := mesh.get_rid()
	if _cache.has(key):
		return _cache[key]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var surface_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_uvs = arrays[Mesh.ARRAY_TEX_UV]
		if surface_uvs == null:
			continue
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() > 0:
			for i in indices:
				verts.append(surface_verts[i])
				uvs.append(surface_uvs[i])
		else:
			for i in surface_verts.size():
				verts.append(surface_verts[i])
				uvs.append(surface_uvs[i])
	var entry := [verts, uvs]
	_cache[key] = entry
	return entry

## Barycentric coordinates of the point on triangle abc closest to p —
## "Real-Time Collision Detection" (Ericson) 5.1.5, all vertex/edge/face
## regions handled, so off-surface points clamp onto the triangle instead of
## extrapolating outside it.
static func _closest_point_barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1.0, 0.0, 0.0)  # vertex a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0.0, 1.0, 0.0)  # vertex b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3) if d1 - d3 != 0.0 else 0.0
		return Vector3(1.0 - v, v, 0.0)  # edge ab
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0.0, 0.0, 1.0)  # vertex c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6) if d2 - d6 != 0.0 else 0.0
		return Vector3(1.0 - w, 0.0, w)  # edge ac
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		var w2 := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0.0, 1.0 - w2, w2)  # edge bc
	var denom := va + vb + vc
	if denom == 0.0:
		return Vector3(1.0, 0.0, 0.0)  # degenerate sliver — treat as vertex a
	var v2 := vb / denom
	var w3 := vc / denom
	return Vector3(1.0 - v2 - w3, v2, w3)  # face interior
