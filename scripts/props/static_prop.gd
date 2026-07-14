extends StaticBody3D
## Static decoy prop (Phase 7, feature/map1-prop-slots).
##
## SPEC.md 13: maps offer plausible standing objects so transformed hiders
## blend in — every room has room for a LARGE one. Decoys are COLORED on
## purpose (never pure white): white is reserved as the "not camouflaged
## yet" tell on players (SPEC.md 9.1), and matching a decoy's color is
## exactly the paint gameplay. The Kenney dressing pass swaps the meshes;
## the slot convention (group + size_class) stays.

@export var size_class: String = "large"  # "large" | "medium" | "small"

func _ready() -> void:
	add_to_group("prop_slot")
