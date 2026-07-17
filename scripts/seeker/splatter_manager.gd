extends Node
## Permanent seeker splatter (Phase 6, feature/seeker-splatter).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 11: a missed paintball leaves paint on the map for the rest of the
## round — the seeker himself changes the camouflage surfaces. Sync is pure
## EVENTS: the host broadcasts {parent-relative position, normal, seed} and
## every peer builds the identical seeded blob cluster (scenes/splatter.tscn).
## The host keeps a bounded history for late joiners; the oldest marks fall
## off both the history and the scene when the cap is hit. Everything clears
## with the round reset (SPEC.md 5.3).
##
## A miss landing within PROP_SPRAY_RADIUS of a transformed, alive hider also
## sprays that hider's prop — "Angesprühte Verstecker müssen übermalen oder
## fliegen auf". The spray is routed through the OWNER's own PaintSync stroke
## events (each peer only ever paints its OWN prop), so live peers and late
## joiners replay it exactly like hand-painted strokes.

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const SPLATTER_SCENE_PATH := "res://scenes/splatter.tscn"
const PROP_SPRAY_RADIUS := 1.5

@export var max_splatters := 512
@export var splatters_path: NodePath = ^"../Splatters"
@export var players_path: NodePath = ^"../Players"

var _game_state: Node = null
var _history: Array = []  # host only: [[local_pos, normal, seed], ...]

@onready var _splatters: Node3D = get_node(splatters_path)

func _ready() -> void:
	_game_state = RoundLocator.locate(self)
	if _game_state != null:
		_game_state.round_reset.connect(_clear_all)
	multiplayer.peer_connected.connect(_on_peer_connected)

func splatter_count() -> int:
	return _splatters.get_child_count()

## HOST entry point — the paintball reports world misses here (global coords).
func add_world_splatter(global_pos: Vector3, global_normal: Vector3) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var local_pos := _splatters.to_local(global_pos)
	var seed_value := randi() & 0x7FFFFFFF
	if RoundLocator.has_real_peer(self):
		_spawn_splatter.rpc(local_pos, global_normal, seed_value)
	else:
		_spawn_splatter(local_pos, global_normal, seed_value)

@rpc("authority", "call_local", "reliable")
func _spawn_splatter(local_pos: Vector3, normal: Vector3, seed_value: int) -> void:
	_add_local(local_pos, normal, seed_value, true)
	if _game_state != null and _game_state.is_round_authority():
		_history.append([local_pos, normal, seed_value])
		while _history.size() > max_splatters:
			_history.pop_front()

## Late joiners get the surviving history in one packet — replays are never
## "fresh": the prop spray already lives in the owners' paint histories.
@rpc("authority", "reliable")
func _sync_history(entries: Array) -> void:
	for entry in entries:
		_add_local(entry[0], entry[1], entry[2], false)

func _add_local(local_pos: Vector3, normal: Vector3, seed_value: int, fresh: bool) -> void:
	var splat: Node3D = (load(SPLATTER_SCENE_PATH) as PackedScene).instantiate()
	_splatters.add_child(splat)
	splat.position = local_pos + normal.normalized() * 0.02
	splat.transform.basis = _basis_from_normal(normal)
	splat.build(seed_value)
	while _splatters.get_child_count() > max_splatters:
		var oldest := _splatters.get_child(0)
		_splatters.remove_child(oldest)
		oldest.free()
	if fresh:
		_notify_prop_spray(local_pos, seed_value)

## Owner-side translation: only the capsule this PEER controls converts the
## splatter into its own paint events — exactly-once across the session.
func _notify_prop_spray(local_pos: Vector3, seed_value: int) -> void:
	var players := get_node_or_null(players_path)
	if players == null:
		return
	var global_hit := _splatters.to_global(local_pos)
	for capsule in players.get_children():
		if capsule is CharacterBody3D and capsule.is_multiplayer_authority() \
				and capsule.global_position.distance_to(global_hit) <= PROP_SPRAY_RADIUS:
			capsule.apply_splatter_spray(global_hit, seed_value)

func _on_peer_connected(id: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	if not RoundLocator.has_real_peer(self) or _history.is_empty():
		return
	_sync_history.rpc_id(id, _history)

func _clear_all() -> void:
	_history.clear()
	for splat in _splatters.get_children():
		splat.queue_free()

static func _basis_from_normal(normal: Vector3) -> Basis:
	var up := normal.normalized()
	var tangent := up.cross(Vector3.RIGHT)
	if tangent.length_squared() < 0.01:
		tangent = up.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(up)
	return Basis(tangent, up, bitangent).orthonormalized()
