extends SceneTree
## Headless WebSocket signaling server for the WebRTC transport (build step 1D).
##
## Start it from the repo root (the Godot project folder):
##
##     <godot> --headless --script server/signaling_server.gd
##     <godot> --headless --script server/signaling_server.gd -- --port=9090
##
## The server never carries game traffic. It only
##   1. creates rooms, issuing the real 6-char room codes and per-room peer IDs
##      (the host is always peer 1), and
##   2. relays the WebRTC handshake (SDP offers/answers + ICE candidates)
##      between peers of one room until their direct P2P links are up.
## Message protocol: JSON text frames — documented in server/README.md.

const DEFAULT_PORT := 9080
const MAX_PEERS_PER_ROOM := 8         # mirrors Net.MAX_PLAYERS (SPEC.md 4)
const WS_HANDSHAKE_TIMEOUT_MS := 5000
# Mirrors Net._generate_code(): no 0/O/1/I — codes get read aloud on Discord.
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6

var _server := TCPServer.new()
var _pending: Array[Dictionary] = []  # { ws, deadline } — WS handshake running
var _clients: Array[Dictionary] = []  # { ws, room, id }
var _rooms: Dictionary = {}           # code -> { peer_id (int): client Dictionary }

func _initialize() -> void:
	# Signaling is a few small messages per join; 100 polls/s is plenty and
	# keeps the headless process from busy-spinning a core.
	Engine.max_fps = 100
	var port := DEFAULT_PORT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var err := _server.listen(port, "*")
	if err != OK:
		printerr("[signaling] cannot listen on port %d (error %d) — is another instance running?" % [port, err])
		quit(1)
		return
	_log("listening on port %d (all interfaces). Ctrl+C stops the server." % port)

func _process(_delta: float) -> bool:
	if not _server.is_listening():
		return false
	_accept_new_connections()
	_poll_pending()
	_poll_clients()
	return false

func _accept_new_connections() -> void:
	while _server.is_connection_available():
		var ws := WebSocketPeer.new()
		var err := ws.accept_stream(_server.take_connection())
		if err != OK:
			_log("rejected TCP connection (accept_stream error %d)" % err)
			continue
		_pending.append({
			"ws": ws,
			"deadline": Time.get_ticks_msec() + WS_HANDSHAKE_TIMEOUT_MS,
		})

func _poll_pending() -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var entry: Dictionary = _pending[i]
		var ws: WebSocketPeer = entry.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_pending.remove_at(i)
				_clients.append({"ws": ws, "room": "", "id": 0})
				_log("client connected (%d total)" % _clients.size())
			WebSocketPeer.STATE_CLOSED:
				_pending.remove_at(i)
			_:
				if Time.get_ticks_msec() > int(entry.deadline):
					ws.close()
					_pending.remove_at(i)
					_log("dropped connection: WebSocket handshake timeout")

func _poll_clients() -> void:
	for i in range(_clients.size() - 1, -1, -1):
		var client: Dictionary = _clients[i]
		var ws: WebSocketPeer = client.ws
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_clients.remove_at(i)
			_drop_client(client)
			continue
		while ws.get_available_packet_count() > 0:
			_handle_message(client, ws.get_packet().get_string_from_utf8())

func _handle_message(client: Dictionary, raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_error(client, "malformed message")
		return
	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		"host":
			_handle_host(client)
		"join":
			_handle_join(client, str(msg.get("code", "")))
		"offer", "answer", "candidate":
			_relay(client, msg)
		_:
			_send_error(client, "unknown message type")

func _handle_host(client: Dictionary) -> void:
	if client.room != "":
		_send_error(client, "already in a room")
		return
	var code := _generate_room_code()
	client.room = code
	client.id = 1
	_rooms[code] = {1: client}
	_send(client, {"type": "room_created", "code": code, "id": 1})
	_log("room %s created" % code)

func _handle_join(client: Dictionary, raw_code: String) -> void:
	if client.room != "":
		_send_error(client, "already in a room")
		return
	var code := raw_code.strip_edges().to_upper()
	if not _rooms.has(code):
		_send_error(client, "unknown room code '%s'" % code)
		return
	var room: Dictionary = _rooms[code]
	if room.size() >= MAX_PEERS_PER_ROOM:
		_send_error(client, "room %s is full (%d players)" % [code, MAX_PEERS_PER_ROOM])
		return
	var id := _generate_peer_id(room)
	client.room = code
	client.id = id
	_send(client, {"type": "room_joined", "code": code, "id": id, "peers": room.keys()})
	for other in room.values():
		_send(other, {"type": "peer_joined", "id": id})
	room[id] = client
	_log("peer %d joined room %s (%d/%d)" % [id, code, room.size(), MAX_PEERS_PER_ROOM])

func _relay(client: Dictionary, msg: Dictionary) -> void:
	if client.room == "":
		_send_error(client, "not in a room")
		return
	var room: Dictionary = _rooms.get(client.room, {})
	var to := int(msg.get("to", 0))
	if not room.has(to):
		_send_error(client, "unknown target peer %d" % to)
		return
	var fwd := msg.duplicate()
	fwd.erase("to")
	fwd["from"] = client.id
	_send(room[to], fwd)
	_log("room %s: relayed %s %d -> %d" % [client.room, msg.type, client.id, to])

## Called after the client is already out of _clients (WS closed).
func _drop_client(client: Dictionary) -> void:
	if client.room == "":
		_log("client disconnected (%d total)" % _clients.size())
		return
	var code: String = client.room
	var room: Dictionary = _rooms.get(code, {})
	room.erase(client.id)
	if client.id == 1:
		# Host gone: the room cannot accept joins anymore. A running game keeps
		# playing over its direct P2P links; this only closes the signaling room.
		for other in room.values():
			other.room = ""
			other.id = 0
			_send(other, {"type": "room_closed"})
		_rooms.erase(code)
		_log("room %s closed (host disconnected)" % code)
	else:
		for other in room.values():
			_send(other, {"type": "peer_left", "id": client.id})
		_log("peer %d left room %s" % [client.id, code])

func _generate_room_code() -> String:
	while true:
		var code := ""
		for _i in CODE_LENGTH:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not _rooms.has(code):
			return code
	return ""  # unreachable; makes the analyzer happy

func _generate_peer_id(room: Dictionary) -> int:
	# High-level multiplayer peer IDs are positive int32; 1 is the host.
	while true:
		var id := randi_range(2, 2147483647)
		if not room.has(id):
			return id
	return 0  # unreachable

func _send(client: Dictionary, msg: Dictionary) -> void:
	client.ws.send_text(JSON.stringify(msg))

func _send_error(client: Dictionary, message: String) -> void:
	_send(client, {"type": "error", "message": message})
	_log("error to peer %d: %s" % [client.id, message])

func _log(text: String) -> void:
	print("[signaling %s] %s" % [Time.get_time_string_from_system(), text])
