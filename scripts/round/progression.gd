extends RefCounted
## Eat progression table (Phase 5, feature/eat-progression-table).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 8, verbatim and inverted on purpose: a hungry slime is a loose
## blob and can only slump into big, coarse shapes — eaten mass buys the
## CONTROL to compress into smaller ones. Cumulative downward: larger forms
## never lock again. Eating unlocks strength, never a downside.
##
##   eaten | forms (cumulative)      | clones
##   ------+-------------------------+-------
##     0   | large                   |   0
##     1+  | + medium                |   1
##     2+  | + small                 |   2
##     3   | everything (cap)        |   3
##
## The clone budget is consumed by Phase 9 (feature/clones); the size gate is
## enforced by player_capsule.gd while a round is active. The lobby is a free
## sandbox (recorded decision — dev testing needs untethered transforms).

const PlayerForms := preload("res://scripts/player_forms.gd")

const EAT_CAP := 3  # SPEC.md 8: Cap bei 3 gefressenen Slimes

static func is_size_unlocked(eaten: int, size: PlayerForms.Size) -> bool:
	match size:
		PlayerForms.Size.SLIME:
			return true  # the slime itself is never gated
		PlayerForms.Size.LARGE:
			return true  # everyone can start large (SPEC.md 13 map rule)
		PlayerForms.Size.MEDIUM:
			return eaten >= 1
		PlayerForms.Size.SMALL:
			return eaten >= 2
		_:
			return false

static func clones_allowed(eaten: int) -> int:
	return clampi(eaten, 0, EAT_CAP)

## Convenience for HUD/selection code: every unlocked size at this count.
static func unlocked_sizes(eaten: int) -> Array:
	var out: Array = []
	for size in [PlayerForms.Size.LARGE, PlayerForms.Size.MEDIUM, PlayerForms.Size.SMALL]:
		if is_size_unlocked(eaten, size):
			out.append(size)
	return out
