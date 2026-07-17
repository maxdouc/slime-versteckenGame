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

## Manual-validation fix (fix/phase-5-9-manual-validation, defect 1): a clone
## spawned exactly AT the placer overlapped the placer's body, and
## move_and_slide depenetration then shoved the player unpredictably — through
## the 0.2 m floor slabs in the worst case. The clone therefore appears this
## far in FRONT of the placer's facing (largest form: 0.78 m half-diagonal +
## 0.4 m capsule radius = 1.18 m minimum separation).
const PLACE_OFFSET := 1.3
## A placed clone's base floats this far above the detected floor — keeps the
## overlap probe from touching the surface it stands on.
const FLOOR_EPSILON := 0.02
## Floor probe around the claimed base: from chest height down through the
## slab. Surfaces steeper than ~45° never count as a floor.
const FLOOR_PROBE_UP := 1.5
const FLOOR_PROBE_DOWN := 4.0
const FLOOR_MIN_NORMAL_Y := 0.7

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
	# Deterministic floor-safe placement: snap the base onto the first
	# walkable surface below the claimed spot, then reject anything that
	# would overlap an existing body (clone, wall, player). Every peer then
	# spawns from the SAME already-safe coordinates.
	var snapped: Variant = _floor_snapped(at)
	if snapped == null or _spot_blocked(form_id, snapped):
		_tell_placer_blocked(placer_id)
		return
	var events := paint_events
	if events.size() > MAX_CLONE_EVENTS:
		events = events.slice(events.size() - MAX_CLONE_EVENTS)
	var clone_id := _next_clone_id
	_next_clone_id += 1
	_spawner.spawn([clone_id, placer_id, form_id, snapped, visual_yaw, events])

## Base position with y snapped FLOOR_EPSILON above the walkable surface
## below `at` (parent-relative in, parent-relative out) — or null when there
## is no floor there (void, a body in the way, or a too-steep surface).
func _floor_snapped(at: Vector3) -> Variant:
	var from_g: Vector3 = _clones.to_global(at + Vector3.UP * FLOOR_PROBE_UP)
	var to_g: Vector3 = _clones.to_global(at - Vector3.UP * FLOOR_PROBE_DOWN)
	var space := _clones.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from_g, to_g))
	if hit.is_empty():
		return null
	if hit.collider is CharacterBody3D:
		return null  # a player is not a floor
	if hit.collider is Node and (hit.collider as Node).is_in_group("clone"):
		return null  # no clone towers — a clone's top is not a floor either
	if hit.normal.y < FLOOR_MIN_NORMAL_Y:
		return null
	var local_hit: Vector3 = _clones.to_local(hit.position)
	return Vector3(at.x, local_hit.y + FLOOR_EPSILON, at.z)

## Overlap protection: the clone's collision volume at `base` must not
## intersect anything — players, walls, furniture, other clones.
func _spot_blocked(form_id: String, base: Vector3) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = PlayerForms.collision_shape(form_id)
	params.transform = Transform3D(Basis.IDENTITY,
			_clones.to_global(base + PlayerForms.collision_origin(form_id)))
	var space := _clones.get_world_3d().direct_space_state
	return not space.intersect_shape(params, 1).is_empty()

func _tell_placer_blocked(placer_id: int) -> void:
	var my_id := multiplayer.get_unique_id() if RoundLocator.has_real_peer(self) else 1
	if placer_id == my_id:
		_notify_place_blocked()
	elif RoundLocator.has_real_peer(self):
		_notify_place_blocked.rpc_id(placer_id)

@rpc("authority", "reliable")
func _notify_place_blocked() -> void:
	get_tree().call_group("round_hud", "flash_notice",
			"Kein Platz — der Klon braucht eine freie Stelle vor dir.")

## Owner-side entry point for the Tausch-Teleport (SPEC.md 10).
func request_swap_from(peer_id: int) -> void:
	if RoundLocator.has_real_peer(self) and not multiplayer.is_server():
		request_swap.rpc_id(1, peer_id)
	else:
		request_swap(peer_id)

## Runs on the HOST: consume the MOST RECENTLY placed living clone (V1
## target selection — recorded decision) and send the owner its landing
## spot. Only the owner's machine moves the capsule (movement authority
## model); the clone despawn replicates through the spawner.
@rpc("any_peer", "reliable")
func request_swap(peer_id: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id:
		return  # spoofed claim
	if not _game_state.is_round_active():
		return
	if _game_state.role_of(peer_id) != _game_state.Role.HIDER \
			or not _game_state.is_alive(peer_id):
		return
	var mine := clones_of(peer_id)
	if mine.is_empty():
		return  # nothing to swap to — a calm no-op
	var target: Node3D = mine[0]
	for clone in mine:
		if clone.clone_id > target.clone_id:
			target = clone
	var landing: Vector3 = target.position
	var consumed_id: int = target.clone_id
	destroy_clone(consumed_id)  # consumed — SPEC.md 10
	var my_id := multiplayer.get_unique_id() if RoundLocator.has_real_peer(self) else 1
	if peer_id == my_id:
		_do_swap(landing, consumed_id)
	elif RoundLocator.has_real_peer(self):
		_do_swap.rpc_id(peer_id, landing, consumed_id)

## Runs on the OWNER's machine: land at the clone's spot. The jump counts
## as a room change and restarts the rotation timer (SPEC.md 10 — by
## definition, so no 5-second dwell).
##
## Defect-1 fix: the local copy of the consumed clone may still be solid for
## a moment (the host's queue_free is end-of-frame, and the spawner despawn
## has no ordering guarantee against this RPC) — landing inside it caused a
## depenetration shove through the floor. Disarm its collision FIRST, then
## land on the floor-safe base the clone stood on.
@rpc("authority", "reliable")
func _do_swap(landing: Vector3, consumed_id: int) -> void:
	_disarm_clone_collision(consumed_id)
	var players_node := get_node_or_null(players_path)
	if players_node == null:
		return
	var my_id := multiplayer.get_unique_id() if RoundLocator.has_real_peer(self) else 1
	var capsule := players_node.get_node_or_null(str(my_id))
	if capsule != null:
		capsule.swap_teleport_to(landing)

func _disarm_clone_collision(clone_id: int) -> void:
	for clone in _clones.get_children():
		if clone.clone_id == clone_id:
			clone.collision_layer = 0
			var shape: CollisionShape3D = clone.get_node_or_null(^"CollisionShape3D")
			if shape != null:
				shape.set_deferred("disabled", true)
			return

## Host-side removal — the death link (9.2) and swap-teleport (9.3) build on
## this single despawn path. Collision disarms immediately: queue_free only
## frees at end of frame, and nobody may collide with a consumed clone.
func destroy_clone(clone_id: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	for clone in _clones.get_children():
		if clone.clone_id == clone_id:
			_disarm_clone_collision(clone_id)
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
