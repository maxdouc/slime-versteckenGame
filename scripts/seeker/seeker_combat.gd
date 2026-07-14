extends Node
## Seeker combat authority (Phase 6, feature/paintball-gun).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 11: the paintball gun is the ONE weapon. Fire requests come in as
## any_peer RPCs and the HOST validates everything — role (seeker), phase
## (HUNT), liveness, claimed id vs actual network sender, and an origin
## plausibility radius around the shooter's body (no teleport shots). One
## projectile in flight per seeker (recorded decision — reads better and
## caps request spam before the cooldown branch lands). The host spawns the
## projectile through the ProjectileSpawner; flight + hit resolution live in
## scripts/seeker/paintball.gd, which reports back here.
##
## Sits as "SeekerCombat" next to "Projectiles" + "ProjectileSpawner"
## (main.tscn and the test worlds use identical relative wiring).

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const PAINTBALL_SCENE_PATH := "res://scenes/paintball.tscn"
const FIRE_ORIGIN_RADIUS := 6.0  # camera arm (3.5) + head + forward offset

signal shot_hit(seeker_id: int)
signal shot_missed(seeker_id: int)

@export var projectiles_path: NodePath = ^"../Projectiles"
@export var spawner_path: NodePath = ^"../ProjectileSpawner"
@export var players_path: NodePath = ^"../Players"

var _game_state: Node = null
var _next_shot_id := 0
var _in_flight := {}  # seeker_id -> shot_id (host only)

@onready var _projectiles: Node3D = get_node(projectiles_path)
@onready var _spawner: MultiplayerSpawner = get_node(spawner_path)

func _ready() -> void:
	_spawner.spawn_function = _spawn_paintball
	_game_state = RoundLocator.locate(self)
	if _game_state != null:
		_game_state.phase_changed.connect(_on_phase_changed)
		_game_state.round_reset.connect(_clear_projectiles)

func in_flight_of(seeker_id: int) -> bool:
	return _in_flight.has(seeker_id)

## Shooter-side entry point: clients route to the host, the host (and
## offline play) validates directly. Coordinates are PARENT-RELATIVE (the
## Players/Projectiles frame), so world offsets in tests cancel out.
func request_fire_from(seeker_id: int, origin: Vector3, dir: Vector3) -> void:
	if RoundLocator.has_real_peer(self) and not multiplayer.is_server():
		request_fire.rpc_id(1, seeker_id, origin, dir)
	else:
		request_fire(seeker_id, origin, dir)

## Runs on the HOST. any_peer: every client may ask; only the host decides.
@rpc("any_peer", "reliable")
func request_fire(seeker_id: int, origin: Vector3, dir: Vector3) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != seeker_id:
		return  # spoofed claim
	if _game_state.current_phase != _game_state.Phase.HUNT:
		return
	if not _game_state.is_seeker(seeker_id) or not _game_state.is_alive(seeker_id):
		return
	if _in_flight.has(seeker_id):
		return  # one paintball in the air per seeker
	if dir.length_squared() < 0.5:
		return
	var players_node := get_node_or_null(players_path)
	if players_node == null:
		return
	var shooter: Node3D = players_node.get_node_or_null(str(seeker_id))
	if shooter == null or shooter.position.distance_to(origin) > FIRE_ORIGIN_RADIUS:
		return  # the muzzle must be near the body
	var shot_id := _next_shot_id
	_next_shot_id += 1
	_in_flight[seeker_id] = shot_id
	_spawner.spawn([shot_id, seeker_id, origin, dir.normalized()])

## --- Reported by the projectile (host side) ---------------------------------

func report_hit(_shot_id: int, seeker_id: int) -> void:
	_in_flight.erase(seeker_id)
	shot_hit.emit(seeker_id)

## `world_pos`/`world_normal` are Vector3 for map impacts and NAN-position for
## a lifetime fizzle; the splatter branch consumes them.
func report_miss(_shot_id: int, seeker_id: int, _world_pos: Variant, _world_normal: Variant) -> void:
	_in_flight.erase(seeker_id)
	shot_missed.emit(seeker_id)

## --- Lifecycle ----------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if phase != _game_state.Phase.HUNT:
		_clear_projectiles()

## Host despawns leftovers (spawner replicates); everyone drops local state.
func _clear_projectiles() -> void:
	_in_flight.clear()
	if _game_state != null and _game_state.is_round_authority():
		for projectile in _projectiles.get_children():
			projectile.queue_free()

## spawn_function — runs on every peer with the host's data
## [shot_id, shooter_id, origin, dir].
func _spawn_paintball(data: Variant) -> Node:
	var ball: Node3D = (load(PAINTBALL_SCENE_PATH) as PackedScene).instantiate()
	ball.name = "Shot%d" % data[0]
	ball.shot_id = data[0]
	ball.shooter_id = data[1]
	ball.position = data[2]
	ball.launch_dir = data[3]
	return ball
