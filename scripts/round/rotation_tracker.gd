extends Node
## Per-hider rotation timer (Phase 5, feature/rotation-timer).
##
## SPEC.md 6, the core identity: an individual timer per hider, starting when
## a room is entered, running ONLY during HUNT. A room change counts only
## after rotation_dwell_seconds of continuous stay in the new room (no
## door-sill pendling — the old room's timer keeps running meanwhile). On
## expiry the slime loses cohesion: the drip puddle grows over the grace
## window (rotation_grace_seconds), then the player requests its own
## elimination (reason "rotation") — the HOST validates and flips the
## registry; the full death behavior belongs to feature/win-lose-reset.
##
## Runs exclusively on the capsule's OWNING peer (client-tracked like
## movement itself — the same trust model). Remote peers see the drip via the
## replicated rotation_drip property. Timings come from the world's GameState
## (the host's values arrive through the settings broadcast).

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const WARN_WINDOW := 10.0  # HUD turns urgent below this many seconds

var _game_state: Node = null
var _capsule: CharacterBody3D = null
var _volumes: Array = []

var _current_room := ""
var _pending_room := ""
var _pending_for := 0.0
var _time_left := 0.0
var _expired := false
var _grace_left := 0.0
var _requested := false
var _was_active := false

func _ready() -> void:
	_capsule = get_parent()
	_game_state = RoundLocator.locate(self)
	if _game_state == null or not _capsule.is_multiplayer_authority():
		set_physics_process(false)
		return
	_game_state.phase_changed.connect(_on_phase_changed)

## Phase 9 (clone swap-teleport) hook: the jump counts as a room change and
## restarts the timer immediately — no dwell, by SPEC.md 10 definition.
func reset_timer() -> void:
	if _current_room == "":
		return
	var room := _room_at(_capsule.global_position)
	_enter_room(room if room != "" else _current_room)

func time_left() -> float:
	return maxf(_time_left, 0.0)

func current_room() -> String:
	return _current_room

func _on_phase_changed(_phase: int) -> void:
	_reset_state()

func _physics_process(delta: float) -> void:
	if not _is_active():
		if _was_active:
			_reset_state()
		return
	_was_active = true
	var room := _room_at(_capsule.global_position)
	if _current_room == "":
		if room != "":
			_enter_room(room)  # first room of this hunt — the timer starts here
		return
	_track_room_change(room, delta)
	if not _expired:
		_time_left -= delta
		if _time_left <= 0.0:
			_expired = true
			_grace_left = float(_game_state.rotation_grace_seconds)
		_push_hud()
	else:
		_grace_left -= delta
		var grace_total := maxf(float(_game_state.rotation_grace_seconds), 0.001)
		_capsule.rotation_drip = clampf(1.0 - _grace_left / grace_total, 0.0, 1.0)
		_push_hud()
		if _grace_left <= 0.0 and not _requested:
			_requested = true
			_game_state.request_elimination("rotation")

func _is_active() -> bool:
	if _game_state == null:
		return false
	if _game_state.current_phase != _game_state.Phase.HUNT:
		return false
	var me := _capsule.get_multiplayer_authority()
	return _game_state.role_of(me) == _game_state.Role.HIDER and _game_state.is_alive(me)

func _track_room_change(room: String, delta: float) -> void:
	if room == _current_room or room == "":
		# Back home (or in no room at all): any pending change is abandoned —
		# that is exactly the door-sill pendling the dwell exists to stop.
		_pending_room = ""
		_pending_for = 0.0
		return
	if room != _pending_room:
		_pending_room = room
		_pending_for = 0.0
	_pending_for += delta
	if _pending_for >= float(_game_state.rotation_dwell_seconds):
		_enter_room(room)

func _enter_room(room: String) -> void:
	_current_room = room
	_pending_room = ""
	_pending_for = 0.0
	_time_left = float(_game_state.rotation_seconds)
	_expired = false
	_grace_left = 0.0
	_requested = false
	_capsule.rotation_drip = 0.0

func _reset_state() -> void:
	_current_room = ""
	_pending_room = ""
	_pending_for = 0.0
	_time_left = 0.0
	_expired = false
	_grace_left = 0.0
	_requested = false
	_was_active = false
	_capsule.rotation_drip = 0.0
	get_tree().call_group("round_hud", "set_rotation_status", "", false)

func _room_at(global_pos: Vector3) -> String:
	if _volumes.is_empty():
		_collect_volumes()
	for volume in _volumes:
		if is_instance_valid(volume) and volume.contains_global(global_pos):
			return volume.room_id
	return ""

## Room volumes of THIS capsule's world (the GameState's parent), cached —
## maps are static while a round runs.
func _collect_volumes() -> void:
	_volumes.clear()
	var world := _game_state.get_parent()
	if world == null:
		return
	for area in world.find_children("*", "Area3D", true, false):
		if area.is_in_group("room_volume"):
			_volumes.append(area)

func _push_hud() -> void:
	var text: String
	var warn: bool
	if _expired:
		text = "DU ZERLÄUFST! Raum wechseln: %.1f s" % maxf(_grace_left, 0.0)
		warn = true
	else:
		text = "Raumwechsel in %d s" % ceili(maxf(_time_left, 0.0))
		warn = _time_left < WARN_WINDOW
	get_tree().call_group("round_hud", "set_rotation_status", text, warn)
