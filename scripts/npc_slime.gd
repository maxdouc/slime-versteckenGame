extends StaticBody3D
## Sleeping NPC slime (Phase 5, feature/npc-slimes-feeding).
##
## SPEC.md 7: same body as the player slime but smaller, neutral pale color,
## eyes closed, never moves, never resists — sleeping explains all of it and
## reads instantly as "food". Spawned/despawned exclusively by the host
## through the NpcSpawner; this script only carries identity and the local
## slurp cosmetic while an eater holds E next to it.

var npc_id: int = -1

@onready var _visual: Node3D = $Visual

## Local-only feeding cosmetic: the body shrinks toward the eater's hold
## progress (0..1). Purely visual — the authoritative despawn comes from the
## host once the hold completes and validates.
func set_slurp(progress: float) -> void:
	var s := 1.0 - 0.7 * clampf(progress, 0.0, 1.0)
	_visual.scale = Vector3(s, s, s)

func reset_slurp() -> void:
	_visual.scale = Vector3.ONE
