extends StaticBody3D
## One placed clone (Phase 9, feature/clones).
##
## SPEC.md 10: a STATIC copy of the owner's form INCLUDING the paint at
## placement time. Every peer builds it locally from the spawn data — the
## prop scene by form id, the collision volume from the forms registry, and
## the paint replayed from the owner's compacted stroke-event snapshot
## (events, never a texture — SPEC.md 9.3). No auto-decay: it stands until
## used or destroyed (death link and swap-teleport are later branches).

const PlayerForms := preload("res://scripts/player_forms.gd")
const PropPainter := preload("res://scripts/paint/prop_painter.gd")
const PaintSync := preload("res://scripts/paint/paint_sync.gd")

var clone_id := -1
var owner_id := -1
var form_id := ""
var visual_yaw := 0.0
var paint_events := PackedInt64Array()

var _painter: RefCounted = null  # PropPainter

func _ready() -> void:
	add_to_group("clone")
	if not PlayerForms.is_valid(form_id) or form_id == PlayerForms.SLIME:
		return
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = visual_yaw
	add_child(visual)
	var prop: Node = load(PlayerForms.scene_path(form_id)).instantiate()
	visual.add_child(prop)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = PlayerForms.collision_shape(form_id)
	collision.position = PlayerForms.collision_origin(form_id)
	add_child(collision)
	_painter = PropPainter.new()
	_painter.bind_prop(_find_prop_mesh(prop))
	for event in paint_events:
		match PaintSync.decode_type(event):
			PaintSync.EVENT_STROKE:
				_painter.stamp_uv(PaintSync.decode_uv(event), PaintSync.decode_color(event))
			PaintSync.EVENT_FILL:
				_painter.fill(PaintSync.decode_color(event))
			PaintSync.EVENT_CLEAR:
				_painter.clear_paint()

## Live paint image of this clone (null while unpainted) — tests and the
## eyedropper read through this.
func paint_image() -> Image:
	return _painter.image() if _painter != null else null

func _find_prop_mesh(prop: Node) -> MeshInstance3D:
	if prop is MeshInstance3D:
		return prop
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	return meshes[0] if meshes.size() > 0 else null
