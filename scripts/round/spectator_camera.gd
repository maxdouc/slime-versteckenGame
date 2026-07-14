extends Node3D
## Free spectator camera (Phase 6, feature/spectator-mode).
##
## SPEC.md 5.3: eliminated players watch the rest of the round through a free
## camera. LOCAL-ONLY — the dead player's own machine spawns this rig next to
## the corpse; nothing about it is networked. WASD flies camera-relative,
## Space rises, Ctrl sinks, the mouse looks around. Removed on round reset.

const FLY_SPEED := 8.0
const MOUSE_SENSITIVITY := 0.003
const PITCH_LIMIT := 1.4

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	_ensure_input_actions()
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		rotation.x = clampf(rotation.x - event.relative.y * MOUSE_SENSITIVITY,
				-PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var motion := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	if Input.is_action_pressed("fly_up"):
		motion += Vector3.UP
	if Input.is_action_pressed("fly_down"):
		motion += Vector3.DOWN
	if motion != Vector3.ZERO:
		global_position += motion.normalized() * FLY_SPEED * delta

static func _ensure_input_actions() -> void:
	var bindings := {
		"fly_up": [KEY_SPACE],
		"fly_down": [KEY_CTRL],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
