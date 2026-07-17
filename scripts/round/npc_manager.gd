extends Node
## NPC slime lifecycle + feeding validation (Phase 5, feature/npc-slimes-feeding).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 7: sleeping NPC slimes appear at PREP start on hand-placed markers
## (group "npc_spawn"), npcs_per_hider x hider count of them, randomly chosen
## without repeats so no two rounds look alike. Feeding is HOST-validated:
## the eater's peer sends one any_peer RPC after its 1-second E-hold; the host
## checks phase, role, liveness, NPC existence and REAL distance, then
## despawns the NPC (MultiplayerSpawner replicates that) and bumps the eaten
## count in the GameState registry. Unfed NPCs vanish at HUNT start with a
## poof broadcast every peer plays locally (SPEC.md 5.2).
##
## Sits as "NpcManager" next to "Npcs" + "NpcSpawner" (main.tscn and the test
## worlds use identical relative wiring, so RPC paths match).

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const NPC_SCENE_PATH := "res://scenes/npc_slime.tscn"
const EAT_RANGE := 2.5  # meters, host-checked — prompts use the same reach

@export var npcs_path: NodePath = ^"../Npcs"
@export var spawner_path: NodePath = ^"../NpcSpawner"
@export var players_path: NodePath = ^"../Players"

var _game_state: Node = null
var _next_npc_id := 0

@onready var _npcs: Node3D = get_node(npcs_path)
@onready var _spawner: MultiplayerSpawner = get_node(spawner_path)

func _ready() -> void:
	_spawner.spawn_function = _spawn_npc
	_game_state = RoundLocator.locate(self)
	if _game_state != null:
		_game_state.phase_changed.connect(_on_phase_changed)

func living_npc_count() -> int:
	return _npcs.get_child_count()

## Nearest living NPC within `range_m` of a global position (prompt + hold
## targeting on the eater's own machine; the host re-checks on its copy).
func nearest_living_npc(global_pos: Vector3, range_m: float) -> Node3D:
	var best: Node3D = null
	var best_dist := range_m
	for npc in _npcs.get_children():
		var dist: float = npc.global_position.distance_to(global_pos)
		if dist <= best_dist:
			best_dist = dist
			best = npc
	return best

## Eater-side entry point: clients route the eat to the host; the host itself
## (and offline play) calls the validator directly — rpc_id at yourself is not
## allowed without call_local. `eater_id` is re-verified server-side.
func request_eat_from(eater_id: int, npc_id: int) -> void:
	if RoundLocator.has_real_peer(self) and not multiplayer.is_server():
		request_eat.rpc_id(1, eater_id, npc_id)
	else:
		request_eat(eater_id, npc_id)

## Runs on the HOST. any_peer: every client may ask; nobody but the host
## decides. The claimed eater id must match the actual network sender.
@rpc("any_peer", "reliable")
func request_eat(eater_id: int, npc_id: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != eater_id:
		return  # spoofed claim
	if _game_state.current_phase != _game_state.Phase.PREP:
		return  # Fressen ist nur in der Prep-Phase möglich (SPEC.md 7)
	if _game_state.role_of(eater_id) != _game_state.Role.HIDER \
			or not _game_state.is_alive(eater_id):
		return
	var npc: Node3D = _npcs.get_node_or_null("Npc%d" % npc_id)
	if npc == null:
		return
	var players_node := get_node_or_null(players_path)
	if players_node == null:
		return
	var eater: Node3D = players_node.get_node_or_null(str(eater_id))
	if eater == null or eater.global_position.distance_to(npc.global_position) > EAT_RANGE:
		return
	npc.queue_free()  # spawner replicates the despawn to every peer
	_game_state.record_eaten(eater_id)

# --- Host lifecycle -----------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	if phase == _game_state.Phase.PREP:
		_spawn_round_npcs()
	elif phase == _game_state.Phase.HUNT:
		_clear_npcs(true)
	elif phase == _game_state.Phase.LOBBY:
		_clear_npcs(false)  # safety net — normally already empty

func _spawn_round_npcs() -> void:
	_clear_npcs(false)
	var markers: Array = []
	var world := _game_state.get_parent()
	if world == null:
		return
	for marker in world.find_children("*", "Marker3D", true, false):
		if marker.is_in_group("npc_spawn"):
			markers.append(marker)
	markers.shuffle()
	var count := mini(int(_game_state.npcs_per_hider * _game_state.hider_ids().size()),
			markers.size())
	for i in count:
		var local_pos: Vector3 = _npcs.to_local(markers[i].global_position)
		_spawner.spawn([_next_npc_id, local_pos])
		_next_npc_id += 1

func _clear_npcs(with_poof: bool) -> void:
	if _npcs.get_child_count() == 0:
		return
	var positions := PackedVector3Array()
	for npc in _npcs.get_children():
		positions.append(npc.position)
		npc.queue_free()
	if with_poof:
		if RoundLocator.has_real_peer(self):
			_play_poofs.rpc(positions)
		else:
			_play_poofs(positions)

## Runs on EVERY peer: one-shot poof particles where the unfed NPCs stood
## (SPEC.md 5.2 — "verschwinden bei Jagdbeginn mit sichtbarem Poof-Partikel").
@rpc("authority", "call_local", "reliable")
func _play_poofs(positions: PackedVector3Array) -> void:
	for pos in positions:
		var poof := CPUParticles3D.new()
		poof.one_shot = true
		poof.emitting = true
		poof.amount = 12
		poof.lifetime = 0.5
		poof.explosiveness = 1.0
		poof.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		poof.emission_sphere_radius = 0.3
		poof.gravity = Vector3.ZERO
		poof.initial_velocity_min = 1.0
		poof.initial_velocity_max = 2.0
		var puff := SphereMesh.new()
		puff.radius = 0.05
		puff.height = 0.1
		poof.mesh = puff
		poof.position = pos + Vector3(0.0, 0.3, 0.0)
		_npcs.add_child(poof)
		get_tree().create_timer(1.5).timeout.connect(poof.queue_free)

## spawn_function — runs on every peer with the host's data [npc_id, position].
func _spawn_npc(data: Variant) -> Node:
	var npc: Node3D = (load(NPC_SCENE_PATH) as PackedScene).instantiate()
	npc.name = "Npc%d" % data[0]
	npc.npc_id = data[0]
	npc.position = data[1]
	return npc
