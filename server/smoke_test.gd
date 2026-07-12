extends SceneTree
## Headless end-to-end smoke test for the WebRTC transport (build step 1D).
##
## Run from the repo root:
##
##     <godot> --headless --script server/smoke_test.gd
##
## Spawns a private signaling server (child process, port 9081), then drives a
## host session and a join session IN THIS process through the real
## net/webrtc_signaling.gd code: room created -> code joined -> SDP/ICE relayed
## -> direct P2P data channels open -> one reliable packet sent each way.
## Prints PASS/FAIL and exits 0/1. Needs the WebRTC GDExtension, exactly like
## the game itself — so it also verifies the committed addon loads.

const WebRTCSession := preload("res://net/webrtc_signaling.gd")

const PORT := 9081  # private port so a manually started server (9080) is untouched
const URL := "ws://127.0.0.1:9081"
const TIMEOUT_SEC := 30.0
const CONNECT_RETRIES := 3

var _server_pid := -1
var _host: WebRTCSession = null
var _join: WebRTCSession = null
# Failed RefCounted sessions are parked here instead of freed immediately —
# never free an object while it is still emitting the signal that failed it.
var _dead_sessions: Array = []
var _room_code := ""
var _join_id := 0
var _host_link := false
var _join_link := false
var _probes_sent := false
var _ping_received := false
var _pong_received := false
var _retries_left := CONNECT_RETRIES
var _retry_at := -1.0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	if not WebRTCSession.is_webrtc_available():
		_finish(false, "WebRTC unavailable — is addons/webrtc_native missing for this platform?")
		return
	_server_pid = OS.create_process(OS.get_executable_path(),
			["--headless", "--script", "server/signaling_server.gd", "--", "--port=%d" % PORT])
	if _server_pid <= 0:
		_finish(false, "could not spawn the signaling server process")
		return
	print("[smoke] signaling server spawned (pid %d), giving it a moment to bind..." % _server_pid)
	OS.delay_msec(1500)
	_start_host()

func _process(delta: float) -> bool:
	if _done:
		return true
	_elapsed += delta
	if _retry_at >= 0.0 and _elapsed >= _retry_at:
		_retry_at = -1.0
		_start_host()
	if _host != null:
		_host.poll()
	if _join != null:
		_join.poll()
	_pump_packets()
	if _host_link and _join_link and not _probes_sent:
		_probes_sent = true
		_send_probes()
	if _ping_received and _pong_received:
		_finish(true, "P2P mesh established and data exchanged both ways (room %s, joiner id %d)" % [_room_code, _join_id])
		return true
	if _elapsed > TIMEOUT_SEC:
		_finish(false, "timed out after %.0f s (host_link=%s join_link=%s ping=%s pong=%s)" %
				[TIMEOUT_SEC, _host_link, _join_link, _ping_received, _pong_received])
		return true
	return false

func _start_host() -> void:
	_host = WebRTCSession.new()
	_host.session_ready.connect(_on_host_ready)
	_host.session_failed.connect(_on_host_failed)
	_host.host(URL)

func _on_host_failed(reason: String) -> void:
	if _retries_left > 0:
		_retries_left -= 1
		print("[smoke] host connect failed (%s) — retrying (%d left)..." % [reason, _retries_left])
		_dead_sessions.append(_host)
		_host = null
		_retry_at = _elapsed + 1.0
	else:
		_finish(false, "host session failed: %s" % reason)

func _on_host_ready(code: String) -> void:
	_room_code = code
	print("[smoke] room created: %s (host peer id %d)" % [code, _host.rtc_peer.get_unique_id()])
	_host.rtc_peer.peer_connected.connect(_on_host_p2p)
	_join = WebRTCSession.new()
	_join.session_ready.connect(_on_join_ready)
	_join.session_failed.connect(_on_join_failed)
	_join.join(URL, code)

func _on_join_failed(reason: String) -> void:
	_finish(false, "join session failed: %s" % reason)

func _on_join_ready(code: String) -> void:
	print("[smoke] joined room %s as peer %d" % [code, _join.rtc_peer.get_unique_id()])
	_join.rtc_peer.peer_connected.connect(_on_join_p2p)

func _on_host_p2p(id: int) -> void:
	print("[smoke] host: P2P link to peer %d open" % id)
	_join_id = id
	_host_link = true

func _on_join_p2p(id: int) -> void:
	print("[smoke] joiner: P2P link to peer %d open" % id)
	if id == 1:
		_join_link = true

func _send_probes() -> void:
	_host.rtc_peer.set_target_peer(_join_id)
	_host.rtc_peer.put_packet("ping".to_utf8_buffer())
	_join.rtc_peer.set_target_peer(1)
	_join.rtc_peer.put_packet("pong".to_utf8_buffer())
	print("[smoke] probe packets sent both ways")

func _pump_packets() -> void:
	if _join != null and _join.rtc_peer != null:
		while _join.rtc_peer.get_available_packet_count() > 0:
			if _join.rtc_peer.get_packet().get_string_from_utf8() == "ping":
				_ping_received = true
	if _host != null and _host.rtc_peer != null:
		while _host.rtc_peer.get_available_packet_count() > 0:
			if _host.rtc_peer.get_packet().get_string_from_utf8() == "pong":
				_pong_received = true

func _finish(ok: bool, message: String) -> void:
	if _done:
		return
	_done = true
	if ok:
		print("[smoke] PASS — %s" % message)
	else:
		printerr("[smoke] FAIL — %s" % message)
	if _server_pid > 0:
		OS.kill(_server_pid)
	quit(0 if ok else 1)
