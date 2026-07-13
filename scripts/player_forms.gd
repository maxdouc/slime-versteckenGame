extends RefCounted
## Form registry for the transform system (Phase 3, feature/transform-white-props).
##
## No class_name on purpose: consumers preload this script by path (the same
## convention as net/net.gd -> webrtc_signaling.gd), so headless --script runs
## and tests never depend on the editor's global class cache in .godot/.
##
## SPEC.md 9.1: a transformation provides ONLY the shape. Every prop spawns
## neutral white regardless of any slime cosmetic (anti-P2W rule; white also
## reads instantly as "not camouflaged yet"). SPEC.md 8 names the size
## categories — one placeholder per category for now, the final 15-prop list
## is an open point (SPEC.md 16).
##
## The visual scenes in scenes/props/ are plain white meshes. Swapping them
## for real assets later must not touch the transform logic, so everything
## gameplay needs (size class, collision volume) lives HERE, not in the scenes.
##
## Speed tiers per size (SPEC.md 9.2) arrive in feature/prop-speed-tiers.
## Networked form state arrives in feature/network-transform-state.

## Form id of the untransformed slime. Prop form ids are the PROPS keys.
const SLIME := "slime"

enum Size { SLIME, SMALL, MEDIUM, LARGE }

## prop_id -> definition. "collision" describes the CharacterBody3D volume
## while the form is held: box or cylinder dims in meters plus the local
## offset of the CollisionShape3D node (props sit on the floor, so origin.y is
## half the height). Dims must match the meshes in the visual scenes.
const PROPS := {
	"carton": {
		"display_name": "Karton (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/prop_carton.tscn",
		"collision": {"type": "box", "size": Vector3(1.1, 1.1, 1.1), "origin": Vector3(0.0, 0.55, 0.0)},
	},
	"bucket": {
		"display_name": "Eimer (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/prop_bucket.tscn",
		"collision": {"type": "cylinder", "radius": 0.32, "height": 0.55, "origin": Vector3(0.0, 0.275, 0.0)},
	},
	"cup": {
		"display_name": "Becher (klein)",
		"size": Size.SMALL,
		"scene": "res://scenes/props/prop_cup.tscn",
		"collision": {"type": "cylinder", "radius": 0.13, "height": 0.24, "origin": Vector3(0.0, 0.12, 0.0)},
	},
}

## Slime collision — MUST stay identical to the Phase 2 capsule in
## scenes/player_capsule.tscn (radius 0.4, height 1.8, shape node at y 0.9),
## otherwise transforming back would change how the slime moves.
const SLIME_COLLISION := {"type": "capsule", "radius": 0.4, "height": 1.8, "origin": Vector3(0.0, 0.9, 0.0)}

## Shape3D resources are built once per form and shared by every player —
## they are read-only at runtime, so sharing is safe and cheap.
static var _shape_cache: Dictionary = {}

static func is_prop(form_id: String) -> bool:
	return PROPS.has(form_id)

static func is_valid(form_id: String) -> bool:
	return form_id == SLIME or PROPS.has(form_id)

static func size_of(form_id: String) -> Size:
	if PROPS.has(form_id):
		return PROPS[form_id]["size"]
	return Size.SLIME

static func scene_path(prop_id: String) -> String:
	return PROPS[prop_id]["scene"]

## First registered prop of a size class — the Phase 3 debug keys select forms
## by size only, because there is exactly one placeholder per class so far.
static func first_prop_of_size(size: Size) -> String:
	for prop_id in PROPS:
		if PROPS[prop_id]["size"] == size:
			return prop_id
	return ""

static func collision_shape(form_id: String) -> Shape3D:
	if not _shape_cache.has(form_id):
		_shape_cache[form_id] = _build_shape(_collision_data(form_id))
	return _shape_cache[form_id]

static func collision_origin(form_id: String) -> Vector3:
	return _collision_data(form_id)["origin"]

static func _collision_data(form_id: String) -> Dictionary:
	return PROPS[form_id]["collision"] if PROPS.has(form_id) else SLIME_COLLISION

static func _build_shape(data: Dictionary) -> Shape3D:
	match data["type"]:
		"box":
			var box := BoxShape3D.new()
			box.size = data["size"]
			return box
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = data["radius"]
			cylinder.height = data["height"]
			return cylinder
		_:
			var capsule := CapsuleShape3D.new()
			capsule.radius = data["radius"]
			capsule.height = data["height"]
			return capsule
