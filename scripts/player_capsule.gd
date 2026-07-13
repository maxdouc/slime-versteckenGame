extends CharacterBody3D
## Networked player capsule: third-person movement + camera (Phase 2) and the
## slime <-> white-prop transform system (Phase 3, feature/transform-white-props).
##
## AUTHORITY — unchanged from Phase 1: each peer owns its capsule (authority =
## peer ID, taken from the node name the host assigns at spawn), simulates it
## locally, and the MultiplayerSynchronizer child broadcasts position + facing
## to everyone else. Client-authoritative on purpose for now; revisit if
## cheating ever becomes a concern.
##
## Node contract: the CharacterBody3D root never rotates. $Visual yaw-turns
## toward the movement direction (that rotation is what remote peers see via
## the synchronizer) and holds exactly one visible form at a time — the slime
## meshes in $Visual/SlimeVisual OR one prop scene instanced under
## $Visual/PropAnchor. $CameraPivot carries the mouse-orbited camera rig and
## only exists on the locally controlled capsule.
##
## FORMS: form_id names the current form (PlayerForms registry). Transforming
## swaps visuals + collision volume and scales the top speed (SPEC.md 9.2:
## slime 100 %, small 80 %, medium 60 %, large 40 % — see max_speed()); props
## always spawn neutral white (SPEC.md 9.1). TEMPORARY debug keys until the
## real selection UX exists: 1 = slime, 2 = small, 3 = medium, 4 = large.
## form_id replicates through the MultiplayerSynchronizer — on change plus
## spawn state, so every peer (late joiners included) shows the same form.
## Only the owning peer may transform itself; _set_form_id is the single
## write path shared by local input and the synchronizer.
##
## PAINT (Phase 4, feature/paint-prototype): every capsule owns a PropPainter;
## _apply_form binds it to the current prop mesh and thereby wipes paint on any
## form change (SPEC.md 9.1). P toggles paint mode while transformed: the mouse
## is freed, LMB paints the OWN prop under the cursor, RMB-drag orbits the
## camera around the body (SPEC.md 9.3), P/Esc leaves. Raycasts run from
## _physics_process (input events only queue screen points — the physics space
## may be locked during input callbacks). Local-only for now; the stroke event
## sync is a later Phase 4 branch.

const PlayerForms := preload("res://scripts/player_forms.gd")
const PropPainter := preload("res://scripts/paint/prop_painter.gd")

const WALK_SPEED: float = 5.0  # slime base speed; forms scale it — max_speed()
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

const PAINT_RAY_LENGTH: float = 50.0  # cursor ray reach; the own prop is always near
const PAINT_QUEUE_MAX: int = 32  # queued stamps per physics tick (mouse-move bursts)

@onready var _visual: Node3D = $Visual
@onready var _slime_visual: Node3D = $Visual/SlimeVisual
@onready var _prop_anchor: Node3D = $Visual/PropAnchor
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _prev_position: Vector3

## Paint state + prop material binding for this capsule's current form. Exists
## on every copy (remote strokes arrive with the later event-sync branch);
## driven locally only through paint mode.
var painter := PropPainter.new()

var _paint_mode := false
var _paint_dragging := false
var _orbit_dragging := false
var _pending_paint := PackedVector2Array()  # screen points waiting for the physics tick

## Current form: PlayerForms.SLIME or a PlayerForms.PROPS key. Replicated via
## the MultiplayerSynchronizer (on change + spawn state); remote copies and
## late joiners apply it through the setter.
var form_id: String = PlayerForms.SLIME:
	set = _set_form_id

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
	_apply_form()

func _unhandled_input(event: InputEvent) -> void:
	if _paint_mode and _handle_paint_mode_input(event):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit_camera(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		# Esc frees the mouse so the lobby UI stays usable; any click that the
		# UI does not consume recaptures it.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not _paint_mode and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("paint_mode"):
		_enter_paint_mode()
	elif event.is_action_pressed("form_slime"):
		transform_to_slime()
	elif event.is_action_pressed("form_small"):
		transform_to_prop(PlayerForms.first_prop_of_size(PlayerForms.Size.SMALL))
	elif event.is_action_pressed("form_medium"):
		transform_to_prop(PlayerForms.first_prop_of_size(PlayerForms.Size.MEDIUM))
	elif event.is_action_pressed("form_large"):
		transform_to_prop(PlayerForms.first_prop_of_size(PlayerForms.Size.LARGE))

## Paint-mode input, handled before everything else: LMB paints the own prop
## under the cursor (hold to drag a stroke), RMB-drag orbits the camera around
## the body (SPEC.md 9.3), P/Esc leaves paint mode. Returns false for events
## paint mode does not own — the form keys keep working, so switching props
## while painting is allowed (key 1 exits via transform_to_slime()).
func _handle_paint_mode_input(event: InputEvent) -> bool:
	if event.is_action_pressed("paint_mode") or event.is_action_pressed("ui_cancel"):
		_exit_paint_mode()
		return true
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_paint_dragging = event.pressed
				if event.pressed:
					_queue_paint(event.position)
				return true
			MOUSE_BUTTON_RIGHT:
				_orbit_dragging = event.pressed
				return true
		return false
	if event is InputEventMouseMotion:
		if _orbit_dragging:
			_orbit_camera(event.relative)
			return true
		if _paint_dragging:
			_queue_paint(event.position)
			return true
	return false

func _orbit_camera(relative: Vector2) -> void:
	_camera_pivot.rotation.y -= relative.x * MOUSE_SENSITIVITY
	_spring_arm.rotation.x = clampf(
		_spring_arm.rotation.x - relative.y * MOUSE_SENSITIVITY,
		CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)

## Paint mode is only meaningful while transformed — the slime itself is never
## painted (paint lives on prop forms, SPEC.md 9.1/9.3).
func _enter_paint_mode() -> void:
	if form_id == PlayerForms.SLIME:
		return
	_paint_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_paint_mode() -> void:
	_paint_mode = false
	_paint_dragging = false
	_orbit_dragging = false
	_pending_paint.clear()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Raycasts must not run inside input callbacks (the physics space may be
## locked there); queue the screen point and resolve it next physics tick.
func _queue_paint(screen_pos: Vector2) -> void:
	if _pending_paint.size() < PAINT_QUEUE_MAX:
		_pending_paint.append(screen_pos)

## Resolve queued paint points: cursor ray into the world; only hits on the
## OWN body (whose collision volume is the current prop form) paint.
func _drain_paint_queue() -> void:
	if _pending_paint.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for screen_pos in _pending_paint:
		var origin := _camera.project_ray_origin(screen_pos)
		var target := origin + _camera.project_ray_normal(screen_pos) * PAINT_RAY_LENGTH
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target))
		if not hit.is_empty() and hit.collider == self:
			painter.paint_world_point(hit.position)
	_pending_paint.clear()

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
	var t := clampf(moved.length() / delta / max_speed(), 0.0, 1.0) * SQUASH_AMOUNT
	var target := Vector3(1.0 + t, 1.0 - t, 1.0 + t)
	_visual.scale = _visual.scale.lerp(target, minf(SQUASH_WEIGHT * delta, 1.0))

func _physics_process(delta: float) -> void:
	_drain_paint_queue()

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Camera-relative input: W always runs away from the camera.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Basis(Vector3.UP, _camera_pivot.rotation.y) * Vector3(input.x, 0.0, input.y)

	var rate := ACCELERATION if direction != Vector3.ZERO else DECELERATION
	if not is_on_floor():
		rate *= AIR_CONTROL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * max_speed(), rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if direction != Vector3.ZERO:
		var target_yaw := atan2(-direction.x, -direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(TURN_WEIGHT * delta, 1.0))

	move_and_slide()

## Effective top speed for the current form: the slime base speed scaled by
## the SPEC.md 9.2 size tier (slime 100 %, small 80 %, medium 60 %, large
## 40 %). Queried every frame — movement AND squash — so a transform changes
## the speed immediately and the waddle animation stays proportional to each
## form's own top speed.
func max_speed() -> float:
	return WALK_SPEED * PlayerForms.speed_multiplier(form_id)

## Transform into a prop form (a PlayerForms.PROPS key). The prop spawns
## neutral white no matter what the slime looks like — SPEC.md 9.1's anti-P2W
## rule: the prop scenes own their white material, nothing is inherited.
## Authority-only: remote copies change form exclusively via the synchronizer.
func transform_to_prop(prop_id: String) -> void:
	if not is_multiplayer_authority():
		return
	form_id = prop_id

## Back to slime, allowed at any time (SPEC.md 9.1) — this wipes the paint job
## (_apply_form unbinds the painter) and ends paint mode.
func transform_to_slime() -> void:
	if not is_multiplayer_authority():
		return
	if _paint_mode:
		_exit_paint_mode()
	form_id = PlayerForms.SLIME

## Single write path for the form — local input and inbound synchronizer
## values both land here. Unknown ids (bad input, bad packet) are rejected so
## a broken peer can never blank out someone's visuals.
func _set_form_id(value: String) -> void:
	if not PlayerForms.is_valid(value):
		push_warning("Ignoring unknown form id '%s' — keeping '%s'." % [value, form_id])
		return
	if value == form_id:
		return
	form_id = value
	if is_node_ready():
		_apply_form()  # before ready, _ready()'s _apply_form picks the value up

## Make the tree match form_id: exactly one visible form — the slime meshes OR
## one prop scene under $Visual/PropAnchor — plus the registry's collision
## volume. Stale prop visuals are detached immediately so no frame ever shows
## two forms at once. The painter re-targets on every change, which is what
## wipes the paint on ANY form change (props always spawn white, SPEC.md 9.1).
func _apply_form() -> void:
	for stale in _prop_anchor.get_children():
		_prop_anchor.remove_child(stale)
		stale.free()
	var is_slime := form_id == PlayerForms.SLIME
	_slime_visual.visible = is_slime
	if is_slime:
		painter.unbind()
	else:
		var prop: Node = load(PlayerForms.scene_path(form_id)).instantiate()
		_prop_anchor.add_child(prop)
		painter.bind_prop(_find_prop_mesh(prop))
	_collision.shape = PlayerForms.collision_shape(form_id)
	_collision.position = PlayerForms.collision_origin(form_id)

## The paintable surface of an instanced prop: its first MeshInstance3D. The
## placeholder props have exactly one; a future multi-mesh prop would paint its
## first mesh until the registry says otherwise.
func _find_prop_mesh(prop: Node) -> MeshInstance3D:
	if prop is MeshInstance3D:
		return prop
	var meshes := prop.find_children("*", "MeshInstance3D", true, false)
	return meshes[0] if meshes.size() > 0 else null

## WASD + arrow keys, registered at runtime: project.godot is a central file
## no feature branch may touch, so its stock input map stays empty. Physical
## keycodes keep WASD in place on non-QWERTY layouts (e.g. German QWERTZ).
static func _ensure_input_actions() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		# TEMPORARY Phase 3 debug keys — form selection by size class. The real
		# unlock-driven selection UX arrives with the eat progression (SPEC.md 8).
		"form_slime": [KEY_1],
		"form_small": [KEY_2],
		"form_medium": [KEY_3],
		"form_large": [KEY_4],
		# Paint mode toggle (Phase 4). P as in Pinsel; E stays reserved for the
		# Fressen interaction (SPEC.md 7).
		"paint_mode": [KEY_P],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
