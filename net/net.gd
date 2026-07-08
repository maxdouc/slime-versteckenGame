extends Node
## Net — the ONLY seam between gameplay and the network transport.
##
## Gameplay code must NEVER touch the peer directly. It calls Net.host_game() /
## Net.join_game(), then uses Godot's high-level multiplayer API (@rpc functions,
## MultiplayerSynchronizer, MultiplayerSpawner). Because everything above this
## layer speaks only the high-level API, swapping the transport means editing only
## the two seam functions below (_make_host_peer / _make_join_peer):
##
##   * NOW (desktop 2-PC testing):  ENetMultiplayerPeer  — built in, no addon.
##   * WEB build:                   WebRTCMultiplayerPeer — needs the godot-webrtc
##                                  GDExtension in /addons + the WebSocket signaling
##                                  server in /server (SPEC.md build step 1).
##   * STEAM (V2):                  SteamMultiplayerPeer  — via GodotSteam addon.
##
## Different transports use different setup calls, so ALL transport specifics live
## inside the seam. Nothing outside this file changes when the transport changes.

signal lobby_created(code: String)
signal lobby_joined(code: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed(reason: String)

const DEFAULT_PORT: int = 8910
const MAX_PLAYERS: int = 8   ## SPEC.md 4: 6-8 players per lobby.

var room_code: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

## Host a new lobby. Returns the 6-char room code others use to join, or "" on error.
func host_game() -> String:
	var peer := _make_host_peer()
	if peer == null:
		return ""
	multiplayer.multiplayer_peer = peer
	room_code = _generate_code()
	lobby_created.emit(room_code)
	return room_code

## Join an existing lobby. For ENet, `address` is an IP. For WebRTC/Steam the
## signaling layer resolves a room code to a connection; the seam stays here.
func join_game(address: String = "127.0.0.1") -> void:
	var peer := _make_join_peer(address)
	if peer == null:
		return
	multiplayer.multiplayer_peer = peer

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func my_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()

# --- TRANSPORT SEAM -------------------------------------------------------
# Swap THESE two functions only to change transport. See file header.
# They return a fully-configured MultiplayerPeer, or null on failure.

func _make_host_peer() -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("create_server failed (%d)" % err)
		return null
	return peer

func _make_join_peer(address: String) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, DEFAULT_PORT)
	if err != OK:
		connection_failed.emit("create_client failed (%d)" % err)
		return null
	return peer
# --------------------------------------------------------------------------

func _generate_code() -> String:
	# No 0/O/1/I to avoid confusion when players read codes aloud.
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for _i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	lobby_joined.emit(room_code)

func _on_connection_failed() -> void:
	connection_failed.emit("connection failed")
