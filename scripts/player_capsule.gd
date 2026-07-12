extends CharacterBody3D
## Networked player capsule with third-person movement and camera (Phase 2,
## feature/player-movement-camera).
##
## AUTHORITY — unchanged from Phase 1: each peer owns its capsule (authority =
## peer ID, taken from the node name the host assigns at spawn), simulates it
## locally, and the MultiplayerSynchronizer child broadcasts position + facing
## to everyone else. Client-authoritative on purpose for now; revisit if
## cheating ever becomes a concern.
##
## Node contract: the CharacterBody3D root never rotates. $Visual yaw-turns
## toward the movement direction (that rotation is what remote peers see via
## the synchronizer), $CameraPivot carries the mouse-orbited camera rig and
## only exists on the locally controlled capsule.

const WALK_SPEED: float = 5.0
const ACCELERATION: float = 25.0  # m/s² while there is movement input
const DECELERATION: float = 30.0  # m/s² braking toward standstill
const AIR_CONTROL: float = 0.3  # fraction of accel/decel while airborne
const TURN_WEIGHT: float = 12.0  # visual yaw smoothing, higher = snappier

const SQUASH_AMOUNT: float = 0.12  # max scale offset at full walk speed
const SQUASH_WEIGHT: float = 8.0  # squash smoothing, higher = snappier

const MOUSE_SENSITIVITY: float = 0.003
const CAMERA_PITCH_START: float = -0.35  # rad; negative looks down at the player
const CAMERA_PITCH_MIN: float = -1.2
const CAMERA_PITCH_MAX: float = 0.35

@onready var _visual: Node3D = $Visual
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _prev_position: Vector3

func _enter_tree() -> void:
	# The host names each capsule after the owning peer's ID (main.gd).
	var peer_id := str(name).to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	_ensure_input_actions()

func _ready() -> void:
	# Remote copies are driven by the synchronizer, never by local physics.
	var local := is_multiplayer_authority()
	set_physics_process(local)
	set_process_unhandled_input(local)
	_prev_position = global_position
	if local:
		_spring_arm.rotation.x = CAMERA_PITCH_START
		_spring_arm.add_excluded_object(get_rid())
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		# Remote copies need no camera rig; their facing arrives via the
		# synchronizer as $Visual rotation.
		_camera_pivot.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY,
			CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	elif event.is_action_pressed("ui_cancel"):
		# Esc frees the mouse so the lobby UI stays usable; any click that the
		# UI does not consume recaptures it.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Subtle squash while moving, derived from the position delta instead of
## velocity so remote copies (fed by the synchronizer, no local physics)
## squash the same way. Scale is (1+t, 1-t, 1+t) — symmetric around Y, so
## the synced $Visual yaw stays shear-free and nothing new needs syncing.
func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved := global_position - _prev_position
	_prev_position = global_position
	moved.y = 0.0
	var t := clampf(moved.length() / delta / WALK_SPEED, 0.0, 1.0) * SQUASH_AMOUNT
	var target := Vector3(1.0 + t, 1.0 - t, 1.0 + t)
	_visual.scale = _visual.scale.lerp(target, minf(SQUASH_WEIGHT * delta, 1.0))

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Camera-relative input: W always runs away from the camera.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Basis(Vector3.UP, _camera_pivot.rotation.y) * Vector3(input.x, 0.0, input.y)

	var rate := ACCELERATION if direction != Vector3.ZERO else DECELERATION
	if not is_on_floor():
		rate *= AIR_CONTROL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * WALK_SPEED, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if direction != Vector3.ZERO:
		var target_yaw := atan2(-direction.x, -direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(TURN_WEIGHT * delta, 1.0))

	move_and_slide()

## WASD + arrow keys, registered at runtime: project.godot is a central file
## no feature branch may touch, so its stock input map stays empty. Physical
## keycodes keep WASD in place on non-QWERTY layouts (e.g. German QWERTZ).
static func _ensure_input_actions() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
