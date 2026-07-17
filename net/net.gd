extends Node
## Net — the ONLY seam between gameplay and the network transport.
##
## Gameplay code must NEVER touch the peer directly. It calls Net.host_game() /
## Net.join_game(), then uses Godot's high-level multiplayer API (@rpc functions,
## MultiplayerSynchronizer, MultiplayerSpawner). Because everything above this
## layer speaks only the high-level API, swapping the transport means editing
## only the seam below — nothing outside /net changes.
##
##   * WEBRTC (primary, build step 1D): WebRTCMultiplayerPeer mesh negotiated
##     through the WebSocket signaling server in /server. Room codes are REAL:
##     the server issues them and resolves them to peers. Desktop/editor builds
##     need the pinned addons/webrtc_native GDExtension; the Web export uses
##     the browser's built-in WebRTC (no extension involved).
##   * ENET (explicit developer fallback): direct IP + port for quick desktop
##     tests; its room code is still a placeholder. Selected only via the lobby
##     UI — there is NO automatic fallback from WebRTC to ENet. If WebRTC or
##     the signaling server is unavailable, the attempt fails with a visible
##     error instead (team decision, branch 1D).
##   * STEAM (V2): SteamMultiplayerPeer via GodotSteam — a future seam swap.
##
## host_game()/join_game() are asynchronous: outcomes arrive via the signals
## below (lobby_created / lobby_joined / connection_failed), never as return
## values — WebRTC needs a signaling round-trip before a peer even exists.

signal lobby_created(code: String)
signal lobby_joined(code: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed(reason: String)

enum Transport { WEBRTC, ENET }

const WebRTCSession := preload("res://net/webrtc_signaling.gd")

const DEFAULT_PORT: int = 8910    ## ENet fallback port.
const SIGNALING_PORT: int = 9080  ## default port of server/signaling_server.gd
const MAX_PLAYERS: int = 8        ## SPEC.md 4: 6-8 players per lobby.

## Transport used by the NEXT host_game()/join_game() call. The lobby UI is the
## only writer; WEBRTC is the shipping default.
var transport: Transport = Transport.WEBRTC

## Where to reach the signaling server (WebRTC only): "ip", "ip:port" or a full
## "ws://…" URL. Hosts usually run the server on their own machine (127.0.0.1);
## joiners enter the host's LAN or Tailscale address. See server/README.md.
var signaling_address: String = "127.0.0.1"

var room_code: String = ""

var _webrtc: WebRTCSession = null
var _lobby_joined_emitted: bool = false
var _web_pump_cb: JavaScriptObject = null  # keep a ref or the callback is GC'd

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_setup_web_pump()

func _process(_delta: float) -> void:
	if _webrtc != null:
		_webrtc.poll()

## Manual-validation fix (defect 2 root cause): in the browser, Godot's whole
## frame loop — including _process and with it every transport poll — rides on
## requestAnimationFrame, which the browser FREEZES for hidden or fully
## occluded tabs. A host whose window goes behind the joiner's therefore
## stops answering offers, and the join hangs although the signaling log
## looks complete. This JS interval keeps the transport polled while the tab
## is hidden (hidden-tab timers are clamped to ~1 Hz, which is plenty for the
## handshake; pages with active WebRTC are exempt from deeper throttling).
func _setup_web_pump() -> void:
	if not OS.has_feature("web"):
		return
	_web_pump_cb = JavaScriptBridge.create_callback(_on_web_pump)
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.__slimeNetPump = _web_pump_cb
	JavaScriptBridge.eval(
			"window.__slimeNetPumpTimer = window.__slimeNetPumpTimer || " +
			"setInterval(function(){ if (window.__slimeNetPump) window.__slimeNetPump(); }, 250);",
			true)

func _on_web_pump(_args: Array) -> void:
	# Runs on the browser main thread between engine iterations — never
	# concurrently with them. Harmlessly redundant while the tab is visible.
	if _webrtc != null:
		_webrtc.poll()
	if multiplayer.multiplayer_peer != null:
		multiplayer.poll()

## Host a new lobby on the selected transport. Emits lobby_created(code) once
## the room exists, or connection_failed(reason).
func host_game() -> void:
	_reset_session()
	match transport:
		Transport.WEBRTC:
			if not _begin_webrtc():
				return
			_webrtc.host(_signaling_url())
		Transport.ENET:
			var peer := _make_enet_host_peer()
			if peer == null:
				return
			multiplayer.multiplayer_peer = peer
			room_code = _generate_code()  # placeholder — only WebRTC codes are joinable
			lobby_created.emit(room_code)

## Join an existing lobby. WEBRTC: `target` is the 6-char room code. ENET:
## `target` is the host's IP. Emits lobby_joined or connection_failed(reason).
func join_game(target: String = "") -> void:
	_reset_session()
	match transport:
		Transport.WEBRTC:
			var code := target.strip_edges().to_upper()
			if code.length() != 6:
				connection_failed.emit("Enter the 6-character room code shown on the host's screen.")
				return
			if not _begin_webrtc():
				return
			_webrtc.join(_signaling_url(), code)
		Transport.ENET:
			var peer := _make_enet_join_peer(target if target != "" else "127.0.0.1")
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
# Swap or extend THESE functions only to change transport. See file header.

func _begin_webrtc() -> bool:
	if not WebRTCSession.is_webrtc_available():
		connection_failed.emit(
				"WebRTC is not available in this build. Desktop builds need the "
				+ "addons/webrtc_native GDExtension (committed in /addons — see its "
				+ "VERSION.md). There is no automatic fallback; switch the lobby "
				+ "dropdown to ENet yourself for a transport-less desktop test.")
		return false
	_webrtc = WebRTCSession.new()
	_webrtc.session_ready.connect(_on_webrtc_session_ready)
	_webrtc.session_failed.connect(_on_webrtc_session_failed)
	return true

func _on_webrtc_session_ready(code: String) -> void:
	# Install the mesh peer immediately so the high-level API drives every peer
	# handshake from the first frame on.
	multiplayer.multiplayer_peer = _webrtc.rtc_peer
	room_code = code
	if is_host():
		lobby_created.emit(code)
	# Joiners emit lobby_joined once the P2P link to the host (peer 1) is open —
	# see _on_peer_connected.

func _on_webrtc_session_failed(reason: String) -> void:
	_reset_session()
	connection_failed.emit(reason)

func _make_enet_host_peer() -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if err != OK:
		connection_failed.emit("create_server failed (%d)" % err)
		return null
	return peer

func _make_enet_join_peer(address: String) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, DEFAULT_PORT)
	if err != OK:
		connection_failed.emit("create_client failed (%d)" % err)
		return null
	return peer

func _signaling_url() -> String:
	var addr := signaling_address.strip_edges()
	if addr == "":
		addr = "127.0.0.1"
	if addr.begins_with("ws://") or addr.begins_with("wss://"):
		return addr
	if ":" in addr:
		return "ws://%s" % addr
	return "ws://%s:%d" % [addr, SIGNALING_PORT]

func _reset_session() -> void:
	room_code = ""
	_lobby_joined_emitted = false
	if _webrtc != null:
		_webrtc.close()
		_webrtc = null
	multiplayer.multiplayer_peer = null
# --------------------------------------------------------------------------

## ENet placeholder only. Real, joinable codes are issued by the signaling
## server (same alphabet: no 0/O/1/I, codes get read aloud).
func _generate_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for _i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	# The WebRTC mesh has no connected_to_server moment; a joiner counts as "in
	# the lobby" once its P2P link to the host (peer 1) opens. ENet reports via
	# _on_connected_to_server instead — the guard makes both paths emit once.
	if id == 1 and not is_host():
		_emit_lobby_joined()

func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)

func _on_connected_to_server() -> void:
	_emit_lobby_joined()

func _on_connection_failed() -> void:
	connection_failed.emit("connection failed")

func _emit_lobby_joined() -> void:
	if _lobby_joined_emitted:
		return
	_lobby_joined_emitted = true
	lobby_joined.emit(room_code)
