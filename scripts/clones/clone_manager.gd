extends Node
## Clone lifecycle authority (Phase 9, feature/clones).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 10: clones unlock through the eat table (budget =
## Progression.clones_allowed, max 3), are placed at the owner's spot, and
## never decay. The HOST validates every placement: sender identity, round
## active, alive hider, a real prop form, the budget, and the claimed
## position against its own copy of the placer. The paint snapshot rides in
## the SPAWN DATA, so the MultiplayerSpawner's late-join replay carries the
## identical image to future peers for free. Everything clears with the
## round reset (SPEC.md 5.3).
##
## Sits as "CloneManager" next to "Clones" + "CloneSpawner" (main.tscn and
## the test worlds use identical relative wiring).

const RoundLocator := preload("res://scripts/round/round_locator.gd")
const Progression := preload("res://scripts/round/progression.gd")
const PlayerForms := preload("res://scripts/player_forms.gd")

const CLONE_SCENE_PATH := "res://scenes/clone.tscn"
const MAX_CLONE_EVENTS := 1024  # spawn-data bound (8 KiB of paint events)
const PLACE_RADIUS := 2.5  # claimed position vs the host's copy of the placer

@export var clones_path: NodePath = ^"../Clones"
@export var spawner_path: NodePath = ^"../CloneSpawner"
@export var players_path: NodePath = ^"../Players"

var _game_state: Node = null
var _next_clone_id := 0

@onready var _clones: Node3D = get_node(clones_path)
@onready var _spawner: MultiplayerSpawner = get_node(spawner_path)

func _ready() -> void:
	_spawner.spawn_function = _spawn_clone
	_game_state = RoundLocator.locate(self)
	if _game_state != null:
		_game_state.round_reset.connect(_clear_clones)

func clones_of(peer_id: int) -> Array:
	var out: Array = []
	for clone in _clones.get_children():
		if clone.owner_id == peer_id:
			out.append(clone)
	return out

## Placer-side entry point: clients route to the host, the host (and offline
## play) validates directly.
func request_place_from(placer_id: int, form_id: String, at: Vector3,
		visual_yaw: float, paint_events: PackedInt64Array) -> void:
	if RoundLocator.has_real_peer(self) and not multiplayer.is_server():
		request_place.rpc_id(1, placer_id, form_id, at, visual_yaw, paint_events)
	else:
		request_place(placer_id, form_id, at, visual_yaw, paint_events)

## Runs on the HOST. Coordinates are parent-relative (the Players/Clones
## frame), like every other cross-peer position in this project.
@rpc("any_peer", "reliable")
func request_place(placer_id: int, form_id: String, at: Vector3,
		visual_yaw: float, paint_events: PackedInt64Array) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != placer_id:
		return  # spoofed claim
	if not _game_state.is_round_active():
		return
	if _game_state.role_of(placer_id) != _game_state.Role.HIDER \
			or not _game_state.is_alive(placer_id):
		return
	if not PlayerForms.is_valid(form_id) or form_id == PlayerForms.SLIME:
		return  # a clone copies a FORM — the bare slime has none
	var budget := Progression.clones_allowed(_game_state.eaten_of(placer_id))
	if clones_of(placer_id).size() >= budget:
		return  # SPEC.md 8/10: eat more to place more, hard cap 3
	var players_node := get_node_or_null(players_path)
	if players_node == null:
		return
	var placer: Node3D = players_node.get_node_or_null(str(placer_id))
	if placer == null or placer.position.distance_to(at) > PLACE_RADIUS:
		return  # the clone must appear where the body actually is
	var events := paint_events
	if events.size() > MAX_CLONE_EVENTS:
		events = events.slice(events.size() - MAX_CLONE_EVENTS)
	var clone_id := _next_clone_id
	_next_clone_id += 1
	_spawner.spawn([clone_id, placer_id, form_id, at, visual_yaw, events])

## Host-side removal — the death link (9.2) and swap-teleport (9.3) build on
## this single despawn path.
func destroy_clone(clone_id: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	for clone in _clones.get_children():
		if clone.clone_id == clone_id:
			clone.queue_free()
			return

func _clear_clones() -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	for clone in _clones.get_children():
		clone.queue_free()

## spawn_function — runs on every peer (late joiners included) with the
## host's data [clone_id, owner_id, form_id, position, visual_yaw, events].
func _spawn_clone(data: Variant) -> Node:
	var clone: Node3D = (load(CLONE_SCENE_PATH) as PackedScene).instantiate()
	clone.name = "Clone%d" % data[0]
	clone.clone_id = data[0]
	clone.owner_id = data[1]
	clone.form_id = data[2]
	clone.position = data[3]
	clone.visual_yaw = data[4]
	clone.paint_events = data[5]
	return clone
