extends RefCounted
## Per-player paint state + prop material binding (Phase 4,
## feature/paint-prototype).
##
## No class_name on purpose (repo convention — consumers preload by path).
##
## Each player capsule owns exactly one painter. The painter holds the paint
## image (TEXTURE_SIZE², RGBA8, starts BASE_COLOR white — SPEC.md 9.1) plus the
## ImageTexture pushed to the GPU, and binds them to the current prop's
## MeshInstance3D through a PER-INSTANCE duplicate of the prop's material.
## Everything is LAZY: an unpainted prop keeps the scene's pristine shared
## white material (so the Phase 3 neutral-white guarantees keep holding
## verbatim), and no image memory exists until the first stamp — the browser
## pays 256 KB per prop only while it is actually painted.
##
## Lifecycle contract (player_capsule.gd): bind_prop() on every transform into
## a prop, unbind() on returning to slime. Both RESET the paint — paint
## survives movement in the same form but never survives a form change
## (SPEC.md 9.1: props always spawn white; returning to slime wipes the job).
##
## stamp_uv() is the deterministic core: identical stamps in identical order
## produce the bit-identical image on every machine (pure integer circle
## rasterization, no blending) — the paint event sync branch builds on that.

const MeshUvLookup := preload("res://scripts/paint/mesh_uv_lookup.gd")

const TEXTURE_SIZE := 256  # web-safe: README says keep per-prop paint textures small
const BRUSH_RADIUS_PX := 10  # the one fixed-size brush (SPEC.md 9.3)
const BASE_COLOR := Color(1, 1, 1, 1)  # neutral white base (SPEC.md 9.1)

## Color the fixed brush paints with. The prototype pins a readable red; the
## eyedropper/color-picker branch turns this into the player's selected color.
var brush_color := Color(0.82, 0.13, 0.10)

var _image: Image
var _texture: ImageTexture
var _material: StandardMaterial3D
var _mesh_instance: MeshInstance3D
var _original_override: Material

## Target a freshly instanced prop form's mesh. Any previous paint is dropped —
## a new form always spawns neutral white.
func bind_prop(mesh_instance: MeshInstance3D) -> void:
	unbind()
	_mesh_instance = mesh_instance

## Back to "no paintable prop": restore the pristine shared material on the
## mesh (if it still exists and still shows our paint) and drop all state.
func unbind() -> void:
	if _material != null and is_instance_valid(_mesh_instance) \
			and _mesh_instance.get_surface_override_material(0) == _material:
		_mesh_instance.set_surface_override_material(0, _original_override)
	_mesh_instance = null
	_original_override = null
	_image = null
	_texture = null
	_material = null

func bound_mesh_instance() -> MeshInstance3D:
	return _mesh_instance

func is_painted() -> bool:
	return _image != null

## Live paint image (null while unpainted). Read-only for callers — all paint
## goes through stamp_uv() so the GPU texture stays in sync.
func image() -> Image:
	return _image

func texture() -> ImageTexture:
	return _texture

## Exact paint color at `uv` — BASE_COLOR while unpainted. The 3D eyedropper
## reads through this, so sampling a painted prop returns precisely what the
## brush laid down (same pixel mapping as stamp_uv).
func color_at_uv(uv: Vector2) -> Color:
	if _image == null:
		return BASE_COLOR
	var px := clampi(int(uv.x * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var py := clampi(int(uv.y * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	return _image.get_pixel(px, py)

## Paint one brush stamp where a raycast hit the bound mesh. Returns false when
## nothing is bound or the point cannot be mapped to a UV.
func paint_world_point(world_point: Vector3) -> bool:
	if _mesh_instance == null or not is_instance_valid(_mesh_instance):
		return false
	var uv := MeshUvLookup.uv_at_world_point(_mesh_instance, world_point)
	if uv.x < 0.0:
		return false
	stamp_uv(uv, brush_color)
	return true

## Deterministic core: stamp a filled BRUSH_RADIUS_PX circle of `color` at
## `uv` (fractions of the texture, clamped to the edges).
func stamp_uv(uv: Vector2, color: Color) -> void:
	_ensure_paint_target()
	var px := clampi(int(uv.x * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var py := clampi(int(uv.y * TEXTURE_SIZE), 0, TEXTURE_SIZE - 1)
	var solid := Color(color.r, color.g, color.b, 1.0)
	var r := BRUSH_RADIUS_PX
	for y in range(maxi(py - r, 0), mini(py + r, TEXTURE_SIZE - 1) + 1):
		for x in range(maxi(px - r, 0), mini(px + r, TEXTURE_SIZE - 1) + 1):
			var dx := x - px
			var dy := y - py
			if dx * dx + dy * dy <= r * r:
				_image.set_pixel(x, y, solid)
	_texture.update(_image)

## First paint action: allocate the white image + texture, then swap the bound
## mesh (if any) onto a per-instance duplicate of its active material. The
## duplicate keeps the prop's surface look (roughness), stays neutral-white
## tinted, and is the only material that ever sees the paint texture — the
## shared scene material is never touched.
func _ensure_paint_target() -> void:
	if _image == null:
		_image = Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		_image.fill(BASE_COLOR)
		_texture = ImageTexture.create_from_image(_image)
	if _material == null and _mesh_instance != null and is_instance_valid(_mesh_instance):
		_original_override = _mesh_instance.get_surface_override_material(0)
		var source := _mesh_instance.get_active_material(0)
		_material = source.duplicate() if source is StandardMaterial3D else StandardMaterial3D.new()
		_material.albedo_color = BASE_COLOR
		_material.albedo_texture = _texture
		# The paint image carries no mipmaps (update() per stroke would have to
		# regenerate them) — plain linear filtering matches that.
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_mesh_instance.set_surface_override_material(0, _material)
