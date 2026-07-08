extends Node
## GameState — authoritative round phase machine.
##
## The host owns the truth and drives phase changes; clients follow. All timings
## are the host-adjustable defaults from SPEC.md section 4 (Among-Us principle).
## Full round flow (prep -> hunt -> end), feeding, the eat table, and the rotation
## timer are built in build step 4 (SPEC.md 15). This scaffold pins the phase
## machine and the defaults so later systems have a stable spine to attach to.

signal phase_changed(phase: Phase)

enum Phase { LOBBY, PREP, HUNT, END }

# Defaults — SPEC.md 4. Host-configurable at lobby time.
var prep_seconds: float = 60.0
var hunt_seconds: float = 240.0
var rotation_seconds: float = 60.0     ## per-hider rotation timer (SPEC.md 6)
var paintball_cooldown: float = 4.0    ## seeker miss penalty (SPEC.md 11)

var current_phase: Phase = Phase.LOBBY
var _timer: float = 0.0

func _process(delta: float) -> void:
	if current_phase == Phase.PREP or current_phase == Phase.HUNT:
		_timer -= delta
		if _timer <= 0.0:
			_advance_phase()

## Called by the host to begin a round from the lobby.
func start_round() -> void:
	_set_phase(Phase.PREP)

func _advance_phase() -> void:
	match current_phase:
		Phase.PREP:
			_set_phase(Phase.HUNT)
		Phase.HUNT:
			_set_phase(Phase.END)
		_:
			pass

func _set_phase(p: Phase) -> void:
	current_phase = p
	match p:
		Phase.PREP:
			_timer = prep_seconds
		Phase.HUNT:
			_timer = hunt_seconds
		_:
			_timer = 0.0
	phase_changed.emit(p)

func time_left() -> float:
	return maxf(_timer, 0.0)

func phase_name() -> String:
	return Phase.keys()[current_phase]
