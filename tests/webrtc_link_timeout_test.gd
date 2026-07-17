extends SceneTree
## Headless test — bounded WebRTC peer-link failure
## (fix/phase-5-9-manual-validation, defect 2 regression).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/webrtc_link_timeout_test.gd
##
## Manual validation found: when signaling succeeded but the P2P link itself
## never came up (e.g. the host's browser tab was frozen by occlusion
## throttling, or a network blocks ICE), the joiner hung in the lobby
## FOREVER with zero feedback — nothing watched the peer connections after
## session_ready. The fix gives every negotiated pair a deadline:
##
##   * a JOINER whose link to the HOST (peer 1) dies or times out fails the
##     whole session visibly (session_failed -> lobby error), and
##   * a HOST losing a link to one peer only drops that peer with a warning
##     (the room keeps running for everyone else).
##
## Both paths are driven here against real WebRTCPeerConnections whose
## remote side simply never answers — no network needed. The happy path
## (links opening) is covered end-to-end by server/smoke_test.gd.
## Exits 0 / 1.

const WebRTCSession := preload("res://net/webrtc_signaling.gd")
const TIMEOUT_SEC := 30.0
const LINK_TIMEOUT_MS := 800

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		_failures += 1  # a timeout is a failure even if every ran check passed
		printerr("[webrtc_link_timeout_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
		_finish()
	return _done

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)

func _finish() -> void:
	if _done:
		return
	_done = true
	if _failures == 0:
		print("[webrtc_link_timeout_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[webrtc_link_timeout_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _until(predicate: Callable, budget_sec: float) -> bool:
	var deadline := _elapsed + budget_sec
	while _elapsed < deadline and not _done:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _run_tests() -> void:
	await process_frame
	_check(WebRTCSession.is_webrtc_available(),
			"webrtc_native available (required for this test)")

	# --- Joiner: a dead host link fails the SESSION, visibly ------------------
	print("[webrtc_link_timeout_test] joiner: host link timeout is fatal")
	var joiner: RefCounted = WebRTCSession.new()
	joiner.peer_connect_timeout_ms = LINK_TIMEOUT_MS
	joiner._join_code = "ABCDEF"  # this session is a joiner
	joiner._ws_gone = true        # signaling already done and gone
	_check(joiner._start_mesh(7), "joiner mesh created (id 7)")
	joiner._create_connection(1)  # the host that will never answer
	var failure_reasons: Array = []
	joiner.session_failed.connect(func(reason: String) -> void:
		failure_reasons.append(reason))
	var failed_pred := func() -> bool: return not failure_reasons.is_empty()
	var t0 := _elapsed
	var poll_failed := func() -> bool:
		joiner.poll()
		return failed_pred.call()
	_check(await _until(poll_failed, 6.0),
			"joiner session FAILED instead of hanging")
	_check(_elapsed - t0 < 5.0,
			"…within a bounded time (%.1f s elapsed)" % (_elapsed - t0))
	var reason: String = str(failure_reasons[0]) if not failure_reasons.is_empty() else ""
	_check("no direct P2P connection to the host" in reason,
			"failure reason names the dead host link")
	_check("candidates" in reason,
			"failure reason carries the diagnostic detail")
	_check(not joiner.rtc_peer.has_peer(1), "dead connection removed from the mesh")
	for _i in 8:  # keep polling — a second emission would be a regression
		joiner.poll()
		await process_frame
	_check(failure_reasons.size() == 1, "the failure fires exactly once")

	# --- Host: one dead peer link is dropped, the session survives ------------
	print("[webrtc_link_timeout_test] host: one dead peer is non-fatal")
	var host: RefCounted = WebRTCSession.new()
	host.peer_connect_timeout_ms = LINK_TIMEOUT_MS
	host._ws_gone = true  # hosting, signaling connection already gone
	_check(host._start_mesh(1), "host mesh created (id 1)")
	host._create_connection(5)  # a joiner that will never answer
	var host_failures: Array = []
	host.session_failed.connect(func(reason: String) -> void:
		host_failures.append(reason))
	var host_dropped := func() -> bool:
		host.poll()
		return not host.rtc_peer.has_peer(5)
	_check(await _until(host_dropped, 6.0),
			"host dropped the dead peer from the mesh")
	_check(host_failures.is_empty(),
			"host session did NOT fail (room keeps running)")

	joiner.close()
	host.close()
	_finish()
