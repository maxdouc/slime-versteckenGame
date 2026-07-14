extends Node3D
## Paintball projectile (Phase 6, feature/paintball-gun).
##
## SPEC.md 11: visible projectile, direct hit = immediate elimination. The
## HOST simulates the flight and resolves impacts; every other peer just
## renders the position streamed by the MultiplayerSynchronizer. Flight is
## RAY-SWEPT segment by segment — at 35 m/s an area overlap would tunnel
## straight through 0.2 m walls between physics frames.
##
## Hit rules (host): an alive HIDER dies through the Phase 5 entry
## (GameState.eliminate_player, reason "paintball"); anything else — walls,
## floor, seekers, ghosts (their collision layer is 0 and invisible to the
## sweep) — resolves as a miss. The splatter branch turns map misses into
## permanent paint; until then the impact data just reaches SeekerCombat.

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const SPEED := 35.0
const GRAVITY := 4.0  # light arc — a paintball, not a bullet
const LIFETIME := 3.0

var shot_id := -1
var shooter_id := -1
var launch_dir := Vector3.FORWARD

var _velocity := Vector3.ZERO
var _age := 0.0
var _resolved := false
var _combat: Node = null
var _splatter_manager: Node = null
var _game_state: Node = null
var _exclude: Array = []  # the shooter's body RID — you cannot shoot yourself

func _ready() -> void:
	_combat = RoundLocator.locate_named(self, ^"SeekerCombat")
	_splatter_manager = RoundLocator.locate_named(self, ^"SplatterManager")
	_game_state = RoundLocator.locate(self)
	_velocity = launch_dir.normalized() * SPEED
	if not is_multiplayer_authority():
		set_physics_process(false)  # replicas follow the synchronizer
		return
	var players := RoundLocator.locate_named(self, ^"Players")
	if players != null:
		var shooter: Node = players.get_node_or_null(str(shooter_id))
		if shooter is CollisionObject3D:
			_exclude = [shooter.get_rid()]

func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_age += delta
	_velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		if _age >= LIFETIME:
			_resolve_miss(Vector3(NAN, NAN, NAN), Vector3.UP)  # fizzled mid-air
		return
	global_position = hit.position
	_resolve_impact(hit.collider, hit.position, hit.normal)

func _resolve_impact(collider: Object, at: Vector3, normal: Vector3) -> void:
	if collider is CharacterBody3D and _game_state != null:
		var victim := str((collider as Node).name).to_int()
		if victim > 0 and _game_state.role_of(victim) == _game_state.Role.HIDER \
				and _game_state.is_alive(victim):
			_resolved = true
			_game_state.eliminate_player(victim, "paintball")
			if _combat != null:
				_combat.report_hit(shot_id, shooter_id)
			queue_free()
			return
	_resolve_miss(at, normal)

func _resolve_miss(at: Vector3, normal: Vector3) -> void:
	_resolved = true
	# A map impact leaves permanent paint (SPEC.md 11); a mid-air fizzle
	# (NAN position) leaves nothing.
	if _splatter_manager != null and at.x == at.x:
		_splatter_manager.add_world_splatter(at, normal)
	if _combat != null:
		_combat.report_miss(shot_id, shooter_id, at, normal)
	queue_free()
