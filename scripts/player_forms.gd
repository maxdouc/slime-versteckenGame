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
## categories; each now offers MULTIPLE forms so a hider can disguise as the
## furniture that actually stands in Map 1 (feature/prop-set-matches-map), not
## just the three primitive placeholders.
##
## The visual scenes in scenes/props/ are neutral white: the "prop_*"
## placeholders are primitive meshes with a baked-in white material, the
## "form_*" furniture reuses the Map 1 Kenney meshes but strips them to white
## via scripts/props/white_form.gd. Either way the transform logic is scene-
## agnostic — everything gameplay needs (size class, collision volume) lives
## HERE, not in the scenes.
##
## Form ids are deliberately short strings: player_capsule.gd replicates
## form_id through its MultiplayerSynchronizer (on change only), and the
## paint system will key its stroke events off the same ids later.

## Form id of the untransformed slime. Prop form ids are the PROPS keys.
const SLIME := "slime"

enum Size { SLIME, SMALL, MEDIUM, LARGE }

## prop_id -> definition. "collision" describes the CharacterBody3D volume
## while the form is held: box or cylinder dims in meters plus the local
## offset of the CollisionShape3D node (props sit on the floor, so origin.y is
## half the height). Dims must match the meshes in the visual scenes.
##
## Two families share this table:
##   * The three "prop_*" placeholders (carton/bucket/cup) — primitive white
##     meshes, kept first so first_prop_of_size() and the id-hardcoding tests
##     stay stable.
##   * The "form_*" furniture forms (feature/prop-set-matches-map) — the SAME
##     Kenney meshes the Map 1 decoys use, but forced neutral white by
##     scripts/props/white_form.gd (SPEC.md 9.1). Their collision boxes are the
##     AABB volumes measured for the dressing pass, verbatim per model, so a
##     form's hitbox matches the decoy it hides among. Size class here drives
##     ONLY the speed tier (SPEC.md 9.2) and the eat-table gate (SPEC.md 8) —
##     it is chosen so the player can disguise as furniture that plausibly
##     stands in the house, not from the decoy's own slot size.
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
	# --- LARGE furniture forms (SPEC.md 8: Fass/Regal-Klasse) ----------------
	"form_bathtub": {
		"display_name": "Badewanne (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/form_bathtub.tscn",
		"collision": {"type": "box", "size": Vector3(1.7, 0.6, 0.8), "origin": Vector3(0.0, 0.3, 0.0)},
	},
	"form_fridge": {
		"display_name": "Kühlschrank (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/form_fridge.tscn",
		"collision": {"type": "box", "size": Vector3(0.86, 1.84, 0.634), "origin": Vector3(0.0, 0.92, 0.0)},
	},
	"form_bed_double": {
		"display_name": "Doppelbett (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/form_bed_double.tscn",
		"collision": {"type": "box", "size": Vector3(1.275, 0.5, 1.5), "origin": Vector3(0.0, 0.25, 0.0)},
	},
	"form_sofa": {
		"display_name": "Sofa (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/form_sofa.tscn",
		"collision": {"type": "box", "size": Vector3(1.598, 0.75, 0.668), "origin": Vector3(0.0, 0.375, 0.0)},
	},
	"form_bookcase": {
		"display_name": "Regal (groß)",
		"size": Size.LARGE,
		"scene": "res://scenes/props/form_bookcase.tscn",
		"collision": {"type": "box", "size": Vector3(0.88, 1.87, 0.55), "origin": Vector3(0.0, 0.935, 0.0)},
	},
	# --- MEDIUM furniture forms (SPEC.md 8: Eimer/Hocker-Klasse) -------------
	"form_kitchen_sink": {
		"display_name": "Waschbecken (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/form_kitchen_sink.tscn",
		"collision": {"type": "box", "size": Vector3(0.79, 0.9, 0.827), "origin": Vector3(0.0, 0.45, 0.0)},
	},
	"form_toilet": {
		"display_name": "WC (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/form_toilet.tscn",
		"collision": {"type": "box", "size": Vector3(0.52, 0.75, 0.794), "origin": Vector3(0.0, 0.375, 0.0)},
	},
	"form_trashcan": {
		"display_name": "Mülleimer (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/form_trashcan.tscn",
		"collision": {"type": "cylinder", "radius": 0.175, "height": 0.635, "origin": Vector3(0.0, 0.318, 0.0)},
	},
	"form_nightstand": {
		"display_name": "Nachttisch (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/form_nightstand.tscn",
		"collision": {"type": "box", "size": Vector3(0.606, 0.6, 0.495), "origin": Vector3(0.0, 0.3, 0.0)},
	},
	"form_television": {
		"display_name": "Fernseher (mittel)",
		"size": Size.MEDIUM,
		"scene": "res://scenes/props/form_television.tscn",
		"collision": {"type": "box", "size": Vector3(1.054, 0.7, 0.198), "origin": Vector3(0.0, 0.35, 0.0)},
	},
	# --- SMALL furniture forms (SPEC.md 8: Flasche/Becher/Buch-Klasse) ------
	"form_potted_plant": {
		"display_name": "Blumentopf (klein)",
		"size": Size.SMALL,
		"scene": "res://scenes/props/form_potted_plant.tscn",
		"collision": {"type": "cylinder", "radius": 0.17, "height": 0.643, "origin": Vector3(0.0, 0.322, 0.0)},
	},
	"form_radio": {
		"display_name": "Radio (klein)",
		"size": Size.SMALL,
		"scene": "res://scenes/props/form_radio.tscn",
		"collision": {"type": "box", "size": Vector3(0.315, 0.228, 0.0975), "origin": Vector3(0.0, 0.114, 0.0)},
	},
	"form_books": {
		"display_name": "Bücher (klein)",
		"size": Size.SMALL,
		"scene": "res://scenes/props/form_books.tscn",
		"collision": {"type": "box", "size": Vector3(0.301, 0.208, 0.189), "origin": Vector3(0.0, 0.104, 0.0)},
	},
	"form_lamp": {
		"display_name": "Lampe (klein)",
		"size": Size.SMALL,
		"scene": "res://scenes/props/form_lamp.tscn",
		"collision": {"type": "box", "size": Vector3(0.12, 0.29, 0.12), "origin": Vector3(0.0, 0.145, 0.0)},
	},
}

## Slime collision — MUST stay identical to the Phase 2 capsule in
## scenes/player_capsule.tscn (radius 0.4, height 1.8, shape node at y 0.9),
## otherwise transforming back would change how the slime moves.
const SLIME_COLLISION := {"type": "capsule", "radius": 0.4, "height": 1.8, "origin": Vector3(0.0, 0.9, 0.0)}

## Top speed per size class relative to the slime base speed — the SPEC.md 9.2
## table, verbatim: slime 100 %, small 80 %, medium 60 %, large 40 %. Smaller
## forms are strictly faster, so eating never unlocks a downside (SPEC.md 8).
const SPEED_MULTIPLIERS := {
	Size.SLIME: 1.0,
	Size.SMALL: 0.8,
	Size.MEDIUM: 0.6,
	Size.LARGE: 0.4,
}

## Shape3D resources are built once per form and shared by every player —
## they are read-only at runtime, so sharing is safe and cheap.
static var _shape_cache: Dictionary = {}

static func is_valid(form_id: String) -> bool:
	return form_id == SLIME or PROPS.has(form_id)

static func size_of(form_id: String) -> Size:
	if PROPS.has(form_id):
		return PROPS[form_id]["size"]
	return Size.SLIME

static func speed_multiplier(form_id: String) -> float:
	return SPEED_MULTIPLIERS[size_of(form_id)]

static func scene_path(prop_id: String) -> String:
	return PROPS[prop_id]["scene"]

## Every registered prop of a size class, in registry order — the capsule's
## form keys blit through this list to browse the forms of one class
## (player_capsule._cycle_form). The placeholder of the class comes first
## (see PROPS ordering), so index 0 equals first_prop_of_size().
static func prop_ids_of_size(size: Size) -> Array:
	var out: Array = []
	for prop_id in PROPS:
		if PROPS[prop_id]["size"] == size:
			out.append(prop_id)
	return out

## First registered prop of a size class. Kept for the tests and any caller
## that just wants one form of a size; the cycling UX uses prop_ids_of_size().
static func first_prop_of_size(size: Size) -> String:
	var ids := prop_ids_of_size(size)
	return ids[0] if not ids.is_empty() else ""

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
