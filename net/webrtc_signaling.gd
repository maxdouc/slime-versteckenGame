extends RefCounted
## One WebRTC session for the Net autoload — transport-seam internals, nothing
## outside /net may touch this file.
##
## Owns a single WebSocket to the signaling server (server/signaling_server.gd)
## and the WebRTCMultiplayerPeer mesh that Net installs into the high-level
## multiplayer API. Flow:
##
##   connect WS -> send host/join -> server answers room_created/room_joined
##   with our peer ID -> build the mesh -> session_ready (Net installs rtc_peer)
##   -> SDP offers/answers + ICE candidates relayed over the WS until every
##   peer pair holds a direct P2P link.
##
## The WS stays open afterwards only so the room can accept late joiners; game
## traffic never touches it. Any failure BEFORE the session is ready emits
## session_failed with a concrete reason — never a silent fallback (branch 1D
## team decision).

signal session_ready(code: String)
signal session_failed(reason: String)

const ICE_CONFIG := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const SIGNALING_TIMEOUT_MS := 10_000
## Manual-validation fix (defect 2): signaling used to be the ONLY watched
## stage — when the P2P link itself never came up (ICE failure), the joiner
## hung in the lobby forever with zero feedback. Every peer pair now has this
## long to open its data channels, then the failure becomes visible.
## A var (not const) so the regression test can shrink it.
var peer_connect_timeout_ms := 20_000

const _CONN_STATES := ["NEW", "CONNECTING", "CONNECTED", "DISCONNECTED", "FAILED", "CLOSED"]
const _GATHER_STATES := ["NEW", "GATHERING", "COMPLETE"]
const _SIG_STATES := ["STABLE", "HAVE_LOCAL_OFFER", "HAVE_REMOTE_OFFER",
		"HAVE_LOCAL_PRANSWER", "HAVE_REMOTE_PRANSWER", "CLOSED"]

var rtc_peer: WebRTCMultiplayerPeer = null

var _ws := WebSocketPeer.new()
var _url := ""
var _join_code := ""  # "" = hosting
var _my_id := 0
var _conns: Dictionary = {}  # peer_id -> WebRTCPeerConnection
var _hello_sent := false
var _ready_done := false
var _failed := false
var _ws_gone := false
var _deadline_ms := 0
## peer_id -> {conn/gath/sig: last logged state, open: bool, deadline: ms,
## cand_in/cand_out: int} — drives the per-link console diagnostics and the
## bounded link-failure detection.
var _diag: Dictionary = {}

## Browsers implement WebRTC natively; desktop/editor builds need the pinned
## addons/webrtc_native GDExtension. Without an implementation the engine hands
## out a stub whose initialize() reports failure — that is what we probe here.
static func is_webrtc_available() -> bool:
	return WebRTCPeerConnection.new().initialize({}) == OK

func host(server_url: String) -> void:
	_join_code = ""
	_open(server_url)

func join(server_url: String, code: String) -> void:
	_join_code = code.strip_edges().to_upper()
	_open(server_url)

func close() -> void:
	if not _ws_gone:
		_ws.close()

## Must be called every frame (Net._process does). Services the signaling WS;
## also polls the mesh so the handshake advances even before/without the
## high-level MultiplayerAPI polling it (extra polls are harmless).
func poll() -> void:
	if rtc_peer != null:
		rtc_peer.poll()
		if not _failed:
			_poll_link_diagnostics()
	if _failed or _ws_gone:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if Time.get_ticks_msec() > _deadline_ms:
				_fail("Signaling server at %s did not answer (connect timeout)." % _url)
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_hello_sent = true
				if _join_code == "":
					_send({"type": "host"})
				else:
					_send({"type": "join", "code": _join_code})
			while _ws.get_available_packet_count() > 0:
				_handle_message(_ws.get_packet().get_string_from_utf8())
			if not _ready_done and Time.get_ticks_msec() > _deadline_ms:
				_fail("Signaling server at %s accepted the connection but never answered." % _url)
		WebSocketPeer.STATE_CLOSED:
			if _ready_done:
				# The P2P mesh lives on; only late joins are affected.
				_ws_gone = true
				push_warning("[net] signaling connection lost (code %d, '%s') — room can no longer accept new players" %
						[_ws.get_close_code(), _ws.get_close_reason()])
			else:
				_fail("Could not reach the signaling server at %s (closed with code %d, '%s'). Is it running? See server/README.md." %
						[_url, _ws.get_close_code(), _ws.get_close_reason()])
		_:
			pass

func _open(server_url: String) -> void:
	_url = server_url
	_deadline_ms = Time.get_ticks_msec() + SIGNALING_TIMEOUT_MS
	var err := _ws.connect_to_url(server_url)
	if err != OK:
		_fail("Invalid signaling server address '%s' (error %d)." % [server_url, err])

func _handle_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[net] ignoring malformed signaling message")
		return
	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		"room_created":
			if _start_mesh(int(msg.get("id", 0))):
				_ready_done = true
				session_ready.emit(str(msg.get("code", "")))
		"room_joined":
			if _start_mesh(int(msg.get("id", 0))):
				_ready_done = true
				# Emit first: Net must install rtc_peer into the MultiplayerAPI
				# before the first peer handshakes begin.
				session_ready.emit(str(msg.get("code", "")))
				for p in msg.get("peers", []):
					_create_connection(int(p))
		"peer_joined":
			_create_connection(int(msg.get("id", 0)))
		"peer_left":
			var id := int(msg.get("id", 0))
			if _conns.has(id):
				print("[net] peer %d left the room" % id)
				_drop_connection(id)
		"offer", "answer":
			var from := int(msg.get("from", 0))
			var pc: WebRTCPeerConnection = _conns.get(from)
			if pc == null:
				push_warning("[net] %s from unknown peer %d ignored" % [msg.type, from])
				return
			print("[net] <- %s from peer %d" % [msg.type, from])
			var err := pc.set_remote_description(str(msg.type), str(msg.get("sdp", "")))
			if err != OK:
				push_warning("[net] set_remote_description(%s) from %d failed (error %d)" % [msg.type, from, err])
		"candidate":
			var from := int(msg.get("from", 0))
			var pc: WebRTCPeerConnection = _conns.get(from)
			if pc != null:
				# The candidate address reveals WHAT the browsers try to pair:
				# obfuscated ".local" mDNS names vs real LAN/public addresses —
				# the deciding evidence when a link times out (defect 2).
				var cand := str(msg.get("name", ""))
				if _diag.has(from):
					_diag[from]["cand_in"] += 1
				print("[net] <- ICE candidate from peer %d: %s" % [from, cand.substr(0, 70)])
				var cand_err := pc.add_ice_candidate(str(msg.get("media", "")),
						int(msg.get("index", 0)), cand)
				if cand_err != OK:
					push_warning("[net] add_ice_candidate from %d failed (error %d)" % [from, cand_err])
		"room_closed":
			if _ready_done:
				push_warning("[net] host left the signaling room — running game continues over P2P")
			else:
				_fail("The host closed the room before the connection finished.")
		"error":
			var message := str(msg.get("message", "unknown error"))
			if _ready_done:
				push_warning("[net] signaling server error: %s" % message)
			else:
				_fail("Signaling server: %s" % message)
		_:
			push_warning("[net] unknown signaling message type ignored")

func _start_mesh(my_id: int) -> bool:
	if my_id < 1:
		_fail("Signaling server sent an invalid peer ID.")
		return false
	rtc_peer = WebRTCMultiplayerPeer.new()
	var err := rtc_peer.create_mesh(my_id)
	if err != OK:
		_fail("WebRTCMultiplayerPeer.create_mesh failed (error %d)." % err)
		return false
	_my_id = my_id
	return true

func _create_connection(peer_id: int) -> void:
	if peer_id < 1 or _conns.has(peer_id) or rtc_peer == null:
		return
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize(ICE_CONFIG)
	if err != OK:
		_fail("WebRTCPeerConnection.initialize failed (error %d) — desktop builds need the addons/webrtc_native GDExtension." % err)
		return
	pc.session_description_created.connect(_on_session_description.bind(peer_id))
	pc.ice_candidate_created.connect(_on_ice_candidate.bind(peer_id))
	rtc_peer.add_peer(pc, peer_id)
	_conns[peer_id] = pc
	_diag[peer_id] = {"conn": -1, "gath": -1, "sig": -1, "open": false,
			"deadline": Time.get_ticks_msec() + peer_connect_timeout_ms,
			"cand_in": 0, "cand_out": 0}
	print("[net] negotiating P2P link to peer %d (timeout %d s)"
			% [peer_id, peer_connect_timeout_ms / 1000])
	# Exactly one side of each pair creates the offer: the HIGHER peer ID.
	# The host is always ID 1 and therefore never offers; joiners offer to it
	# (same rule as the official Godot webrtc_signaling demo).
	if peer_id < _my_id:
		pc.create_offer()

func _on_session_description(type: String, sdp: String, peer_id: int) -> void:
	var pc: WebRTCPeerConnection = _conns.get(peer_id)
	if pc == null:
		return
	print("[net] -> %s to peer %d" % [type, peer_id])
	pc.set_local_description(type, sdp)
	_send({"type": type, "to": peer_id, "sdp": sdp})

func _on_ice_candidate(media: String, index: int, name: String, peer_id: int) -> void:
	if _diag.has(peer_id):
		_diag[peer_id]["cand_out"] += 1
	print("[net] -> ICE candidate to peer %d: %s" % [peer_id, name.substr(0, 70)])
	_send({"type": "candidate", "to": peer_id, "media": media, "index": index, "name": name})

## Watches every negotiated pair: logs each state transition to the console
## (the evidence trail defect 2 was missing) and turns a link that FAILED or
## ran out its deadline into a visible outcome instead of an eternal hang —
## fatal for a joiner's link to the host, a warning for any other pair.
func _poll_link_diagnostics() -> void:
	var lost: Array = []
	for peer_id in _conns:
		var pc: WebRTCPeerConnection = _conns[peer_id]
		var d: Dictionary = _diag[peer_id]
		var conn := pc.get_connection_state()
		if conn != d["conn"]:
			d["conn"] = conn
			print("[net] peer %d connection state: %s" % [peer_id, _CONN_STATES[conn]])
		var gath := pc.get_gathering_state()
		if gath != d["gath"]:
			d["gath"] = gath
			print("[net] peer %d gathering state: %s" % [peer_id, _GATHER_STATES[gath]])
		var sig := pc.get_signaling_state()
		if sig != d["sig"]:
			d["sig"] = sig
			print("[net] peer %d signaling state: %s" % [peer_id, _SIG_STATES[sig]])
		if d["open"]:
			continue
		if rtc_peer.has_peer(peer_id) and rtc_peer.get_peer(peer_id).get("connected", false):
			d["open"] = true
			print("[net] P2P link to peer %d OPEN (candidates: %d out / %d in)"
					% [peer_id, d["cand_out"], d["cand_in"]])
			continue
		var dead_state: bool = conn == WebRTCPeerConnection.STATE_FAILED \
				or conn == WebRTCPeerConnection.STATE_CLOSED
		if dead_state or Time.get_ticks_msec() > int(d["deadline"]):
			lost.append(peer_id)
	for peer_id in lost:
		_handle_link_loss(peer_id)

func _handle_link_loss(peer_id: int) -> void:
	var d: Dictionary = _diag[peer_id]
	var detail := "connection=%s, %d candidates sent / %d received" \
			% [_CONN_STATES[maxi(int(d["conn"]), 0)], d["cand_out"], d["cand_in"]]
	_drop_connection(peer_id)
	if _join_code != "" and peer_id == 1:
		# A joiner without a host link never gets into the game — fail loudly.
		_fail("Signaling succeeded, but no direct P2P connection to the host "
				+ "could be established within %d s (%s). " % [peer_connect_timeout_ms / 1000, detail]
				+ "Keep BOTH game windows visible while joining (browsers freeze "
				+ "hidden tabs), or the network is blocking WebRTC peer traffic "
				+ "(ICE). See server/README.md.")
	else:
		push_warning("[net] P2P link to peer %d failed (%s) — removed from the mesh" % [peer_id, detail])

func _drop_connection(peer_id: int) -> void:
	var pc: WebRTCPeerConnection = _conns.get(peer_id)
	_conns.erase(peer_id)
	_diag.erase(peer_id)
	if rtc_peer != null and rtc_peer.has_peer(peer_id):
		rtc_peer.remove_peer(peer_id)
	if pc != null:
		pc.close()

func _send(msg: Dictionary) -> void:
	if not _ws_gone and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))

func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	session_failed.emit(reason)
