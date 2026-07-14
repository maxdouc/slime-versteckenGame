extends Node3D
## Boot scene + host-driven player spawning (build step 1C).
##
## Spawning is HOST-authoritative: only the host adds/removes capsules under
## $Players, and the MultiplayerSpawner replicates that to every client,
## including late joiners. Each capsule is named after the owning peer's ID —
## player_capsule.gd reads its own name to claim movement authority (a Phase 1
## test setup; see that script's header).

const PLAYER_CAPSULE: PackedScene = preload("res://scenes/player_capsule.tscn")
const SPAWN_RING_RADIUS: float = 2.0

@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner

## Found by GROUP, not by path: the map decides where players spawn
## (Phase 7 — gray_room.tscn and maps/map1_house.tscn both tag a
## player_spawn marker, so swapping maps never touches this script).
var _spawn_point: Marker3D = null

func _ready() -> void:
	print("[Slime-Verstecken] Boot OK — Godot ", Engine.get_version_info()["string"])
	print("[Net] autoload ready, max players = ", Net.MAX_PLAYERS)
	print("[GameState] starting phase = ", GameState.phase_name())
	var spawn_markers := get_tree().get_nodes_in_group("player_spawn")
	if spawn_markers.size() > 0:
		_spawn_point = spawn_markers[0]

	_spawner.spawn_function = _spawn_capsule
	Net.lobby_created.connect(_on_lobby_created)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)

func _on_lobby_created(_code: String) -> void:
	_spawner.spawn([Net.my_id(), _spawn_position(0)])

func _on_peer_connected(id: int) -> void:
	# peer_connected fires on every peer; only the host may spawn.
	if Net.is_host():
		_spawner.spawn([id, _spawn_position(_players.get_child_count())])

func _on_peer_disconnected(id: int) -> void:
	if not Net.is_host():
		return
	var capsule := _players.get_node_or_null(str(id))
	if capsule != null:
		capsule.queue_free()

## spawn_function: runs on EVERY peer with the host's spawn data. The position
## must travel in the spawn data — synchronizer spawn-state cannot be trusted
## for it, because the joining peer takes authority over its own capsule the
## moment it enters the tree and then ignores state coming from the host
## (verified: without this, the joiner's capsule spawns at a stale position).
func _spawn_capsule(data: Variant) -> Node:
	var capsule := PLAYER_CAPSULE.instantiate()
	capsule.name = str(data[0])
	capsule.position = data[1]
	return capsule

func _spawn_position(slot: int) -> Vector3:
	# Fan spawns in a ring around the marker so capsules never stack.
	var center := _spawn_point.global_position if _spawn_point != null else Vector3(0, 1, 0)
	var angle := float(slot) * TAU / float(Net.MAX_PLAYERS)
	return center + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RING_RADIUS
