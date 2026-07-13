extends Node
## Paint event sync (Phase 4, feature/paint-event-sync).
##
## SPEC.md 9.3 netcode rule: brush strokes are synchronized as EVENTS and
## replayed on every client — whole textures/images are NEVER transmitted.
## Everything goes through Godot's high-level multiplayer API (@rpc on this
## node, which the player scene instances under the same path on every peer);
## no transport code — the Net seam stays untouched.
##
## EVENTS: one int64 per action — type(2 bit) | uv.x(u16) | uv.y(u16) |
## rgb(24 bit). The OWNER quantizes once at the source; every peer (owner
## included, via call_local) applies the same DEQUANTIZED values through the
## same code path, so all paint images stay bit-identical.
##
## ORDERING: form changes travel via the MultiplayerSynchronizer, events via
## RPC — there is no cross-ordering guarantee between the two. The capsule's
## paint_epoch (bumped by the owner on every form change, replicated with
## spawn state) tags every event: a newer epoch wipes the old paint first,
## stale epochs are dropped. Whichever of {event, synchronizer} arrives
## first, the result converges.
##
## LATE JOIN: the owner keeps a bounded per-epoch history. A fill (Grundieren)
## obsoletes everything before it — natural compaction; Alles-Löschen empties
## the history, form changes reset it. Joiners request the history and replay
## it through the normal event path. If a marathon painter ever exceeds
## MAX_HISTORY strokes since the last fill, the oldest are dropped: live
## peers stay perfect, only a late joiner would miss the (long since
## overpainted) oldest stamps.
##
## No class_name on purpose (repo convention — preload/load by path).

const EVENT_STROKE := 0
const EVENT_FILL := 1
const EVENT_CLEAR := 2

const MAX_HISTORY := 4096  # 8 bytes per event -> worst-case replay 32 KiB
const REQUEST_RETRY_SEC := 1.0
const REQUEST_MAX_TRIES := 5

var _history := PackedInt64Array()  # owner only: events of the current epoch
var _history_epoch := 0
var _last_stroke_event := -1  # owner only: suppress identical consecutive stamps
var _history_received := false  # replicas: replay arrived, stop retrying
var _request_tries := 0
var _retry_timer: Timer

@onready var _capsule: CharacterBody3D = get_parent()

func _ready() -> void:
	if is_multiplayer_authority():
		return
	# Replica of someone else's capsule: fetch the paint laid down before this
	# peer joined. The FIRST request waits one timer tick on purpose — right
	# after a spawn, other worlds may not have this capsule yet (host-relayed
	# spawns and direct RPCs have no cross-ordering), and a freshly spawned
	# capsule has nothing to replay anyway. Retries cover slow mesh links.
	_retry_timer = Timer.new()
	_retry_timer.wait_time = REQUEST_RETRY_SEC
	_retry_timer.timeout.connect(_on_retry_timeout)
	add_child(_retry_timer)
	_retry_timer.start()

## --- Owner-side entry points (the capsule's input paths call these) --------

func local_stroke(uv: Vector2, color: Color) -> void:
	if not is_multiplayer_authority():
		return
	var event := encode_stroke(uv, color)
	if event == _last_stroke_event:
		return  # identical quantized stamp — repainting the same pixels
	_last_stroke_event = event
	_broadcast(event)

func local_fill(color: Color) -> void:
	if not is_multiplayer_authority():
		return
	_broadcast(encode_fill(color))

func local_clear() -> void:
	if not is_multiplayer_authority():
		return
	_broadcast(encode_clear())

func _broadcast(event: int) -> void:
	_record(event)
	_apply_paint_event.rpc(_capsule.paint_epoch, event)

## Called by the capsule whenever paint_epoch advances: the previous
## lifetime's events can never be replayed again — release them eagerly.
func reset_history() -> void:
	_history.clear()
	_history_epoch = -1  # the next _record rotates onto the current epoch
	_last_stroke_event = -1

## Bounded late-join history. A fill covers every pixel, so everything before
## it can never show through — drop it; a clear means "white", which is what
## an empty history replays to.
func _record(event: int) -> void:
	var epoch: int = _capsule.paint_epoch
	if _history_epoch != epoch:
		_history.clear()
		_history_epoch = epoch
		_last_stroke_event = -1
	match decode_type(event):
		EVENT_FILL:
			_history.clear()
			_history.append(event)
			_last_stroke_event = -1
		EVENT_CLEAR:
			_history.clear()
			_last_stroke_event = -1
		_:
			_history.append(event)
			if _history.size() > MAX_HISTORY:
				_history = _history.slice(_history.size() - MAX_HISTORY)

## --- Replication ------------------------------------------------------------

## Broadcast by the owner; call_local makes the owner apply through the exact
## same path as every replica — one deterministic code path for all peers.
@rpc("authority", "call_local", "reliable")
func _apply_paint_event(epoch: int, event: int) -> void:
	if epoch < _capsule.paint_epoch:
		return  # stale: painted before a form change that already reached us
	if epoch > _capsule.paint_epoch:
		_capsule.paint_epoch = epoch  # event outran the synchronizer — wipe now
	match decode_type(event):
		EVENT_STROKE:
			_capsule.painter.stamp_uv(decode_uv(event), decode_color(event))
		EVENT_FILL:
			_capsule.painter.fill(decode_color(event))
		EVENT_CLEAR:
			_capsule.painter.clear_paint()

## Joiner -> owner: "send me the paint so far". Runs on the owner's machine.
@rpc("any_peer", "reliable")
func _send_history_request() -> void:
	if not is_multiplayer_authority():
		return  # only the owner's own instance answers
	var requester := multiplayer.get_remote_sender_id()
	if requester == 0:
		return
	var events := _history if _history_epoch == _capsule.paint_epoch else PackedInt64Array()
	_apply_history.rpc_id(requester, _capsule.paint_epoch, events)

## Owner -> joiner: the replay. Reliable and ordered per sender, so any live
## event sent after this response also arrives after it; a duplicate replay
## (retry crossing a response) is idempotent — clear + same events, same image.
@rpc("authority", "reliable")
func _apply_history(epoch: int, events: PackedInt64Array) -> void:
	_history_received = true
	if _retry_timer != null:
		_retry_timer.stop()
	if epoch < _capsule.paint_epoch:
		return  # a form change already obsoleted this replay
	if epoch > _capsule.paint_epoch:
		_capsule.paint_epoch = epoch  # setter wipes
	else:
		_capsule.painter.clear_paint()  # replay from scratch
	for event in events:
		_apply_paint_event(epoch, event)

func _request_history() -> void:
	_request_tries += 1
	var owner_id := get_multiplayer_authority()
	if multiplayer.multiplayer_peer == null or not multiplayer.get_peers().has(owner_id):
		return  # offline, or the mesh link to the owner is still building
	_send_history_request.rpc_id(owner_id)

func _on_retry_timeout() -> void:
	if _history_received or _request_tries >= REQUEST_MAX_TRIES:
		_retry_timer.stop()
		return
	_request_history()

## --- Event encoding -----------------------------------------------------------

static func encode_stroke(uv: Vector2, color: Color) -> int:
	var qu := clampi(roundi(uv.x * 65535.0), 0, 65535)
	var qv := clampi(roundi(uv.y * 65535.0), 0, 65535)
	return (EVENT_STROKE << 56) | (qu << 40) | (qv << 24) | _encode_rgb(color)

static func encode_fill(color: Color) -> int:
	return (EVENT_FILL << 56) | _encode_rgb(color)

static func encode_clear() -> int:
	return EVENT_CLEAR << 56

static func decode_type(event: int) -> int:
	return (event >> 56) & 0x3

static func decode_uv(event: int) -> Vector2:
	return Vector2(((event >> 40) & 0xFFFF) / 65535.0, ((event >> 24) & 0xFFFF) / 65535.0)

static func decode_color(event: int) -> Color:
	var rgb := event & 0xFFFFFF
	return Color(((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0,
			(rgb & 0xFF) / 255.0, 1.0)

static func _encode_rgb(color: Color) -> int:
	return (clampi(roundi(color.r * 255.0), 0, 255) << 16) \
			| (clampi(roundi(color.g * 255.0), 0, 255) << 8) \
			| clampi(roundi(color.b * 255.0), 0, 255)
