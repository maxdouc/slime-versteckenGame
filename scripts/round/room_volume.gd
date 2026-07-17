extends Area3D
## Room volume (Phase 5, feature/rotation-timer).
##
## Marks one room of a map for the rotation rule (SPEC.md 6). Maps place one
## Area3D per room with a single BoxShape3D CollisionShape3D child covering
## the room; the rotation tracker asks contains_global() instead of relying
## on physics overlap events — pure math, deterministic in headless runs,
## and no collision-layer coupling.
##
## Convention (consumed by rotation_tracker.gd and every map from Map 1 on):
## group "room_volume", unique room_id per map, child named CollisionShape3D.

@export var room_id: String = ""

func _ready() -> void:
	add_to_group("room_volume")

func contains_global(point: Vector3) -> bool:
	var shape_node: CollisionShape3D = get_node_or_null(^"CollisionShape3D")
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return false
	var local: Vector3 = shape_node.global_transform.affine_inverse() * point
	var half: Vector3 = (shape_node.shape as BoxShape3D).size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z
