extends Node3D
## One splatter mark (Phase 6, feature/seeker-splatter).
##
## Built ENTIRELY from a seed: every peer receives {position, normal, seed}
## and constructs the identical blob cluster locally — the event IS the
## splatter, nothing visual ever crosses the wire (SPEC.md 9.3 spirit).
## Purely cosmetic: no collision, paint marks don't block paintballs.

const BLOB_COLOR_BASE := Color(0.95, 0.2, 0.75)  # the paintball's magenta

func build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var blob_count := 3 + rng.randi_range(0, 2)
	for i in blob_count:
		var blob := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var radius := 0.1 + rng.randf() * 0.18
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.01
		disc.radial_segments = 10
		blob.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BLOB_COLOR_BASE.lightened(rng.randf() * 0.25)
		mat.roughness = 0.25
		blob.material_override = mat
		# Slight per-blob height steps keep overlapping discs from z-fighting.
		blob.position = Vector3(rng.randf_range(-0.25, 0.25), 0.004 * (i + 1),
				rng.randf_range(-0.25, 0.25))
		add_child(blob)
