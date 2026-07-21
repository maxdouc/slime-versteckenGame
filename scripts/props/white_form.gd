extends Node3D
## Neutral-white transform form (Phase 3 extension, feature/prop-set-matches-map).
##
## SPEC.md 9.1 — a transformation provides ONLY the shape and ALWAYS spawns
## neutral white (anti-P2W; white also reads instantly as "not camouflaged
## yet"). The Kenney furniture forms reuse the SAME .glb meshes the map decoys
## are dressed with, but a decoy is COLORED on purpose and a form must never be.
## So forms and decoys stay separate scenes: this script force-overrides every
## surface of the instanced model with a plain white StandardMaterial3D on
## _ready, stripping the model's baked colors/textures no matter what the .glb
## ships.
##
## The player capsule instances the form under $Visual/PropAnchor (add_child →
## _ready runs synchronously here) before the painter binds the first mesh, so
## by the time PropPainter reads get_active_material(0) it sees this white
## material and duplicates it for the paint texture (prop_painter.gd). The
## placeholder prop scenes (prop_carton/bucket/cup) bake their white override
## straight into the .tscn instead — either path yields the same neutral white.

func _ready() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1, 1)
	white.roughness = 0.55
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, white)
