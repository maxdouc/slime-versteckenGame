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
##
## COLOR (feature/eyedropper-and-colorpicker): the local player gets a
## PaintHud (color wheel + HSV, shown in paint mode) whose picks drive
## painter.brush_color, and Q samples the aimed surface's exact source color
## through the 3D eyedropper (SPEC.md 9.3) — into the brush and the HUD.
## UI clicks never paint: consumed events skip _unhandled_input, and queued
## strokes are dropped while the cursor hovers any control.
##
## BASE COAT (feature/grundieren-button): Grundieren (HUD button or G) covers
## the whole prop with the current brush color in one click — SPEC.md 9.3
## calls this mandatory for the rotation loop. Alles-Löschen (HUD button)
## resets to neutral white but keeps the form.
##
## EVENT SYNC (feature/paint-event-sync): every local paint action goes
## through $PaintSync as a compact event (never a texture — SPEC.md 9.3) and
## is applied identically on every peer, owner included (call_local).
## paint_epoch counts paint lifetimes: the owner bumps it on every form
## change, it replicates on change + spawn state, and whoever learns of a
## newer epoch first (synchronizer or event) wipes the old paint — that is
## how strokes racing a transform stay consistent. _apply_form therefore
## REBINDS the painter without wiping; only epochs wipe.

const PlayerForms := preload("res://scripts/player_forms.gd")
const PropPainter := preload("res://scripts/paint/prop_painter.gd")
const Eyedropper := preload("res://scripts/paint/eyedropper.gd")
const RoundLocator := preload("res://scripts/round/round_locator.gd")
const Progression := preload("res://scripts/round/progression.gd")
const PaintHudScene := preload("res://scenes/paint_hud.tscn")
const SpectatorCameraScene := preload("res://scenes/spectator_camera.tscn")

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
@onready var _paint_sync: Node = $PaintSync
@onready var _drip_puddle: MeshInstance3D = $DripPuddle

var _prev_position: Vector3

## Paint state + prop material binding for this capsule's current form. Exists
## on every copy (remote strokes arrive with the later event-sync branch);
## driven locally only through paint mode.
var painter := PropPainter.new()

var _paint_mode := false
var _paint_dragging := false
var _orbit_dragging := false
var _pending_paint := PackedVector2Array()  # screen points waiting for the physics tick
var _eyedrop_pending := false  # Q pressed; resolves next physics tick
var _paint_hud: CanvasLayer  # local player only (like the camera rig)

## Round state (Phase 5) — resolved via the ancestor-walk locator, null when
## no GameState exists above this capsule (focused tests spawn bare capsules).
var _game_state: Node = null
var _npc_manager: Node = null
var _seeker_combat: Node = null

const EAT_HOLD_SECONDS := 1.0  # E-hold to slurp an NPC (SPEC.md 7)
const EAT_REACH := 2.5  # prompt range; the host validates the same reach

var _eat_hold := 0.0
var _slurp_npc: Node3D = null

## Ghost state (feature/win-lose-reset): eliminated players and mid-round
## joiners are invisible, non-colliding and input-dead until the round resets
## (SPEC.md 5.3). Derived from the replicated registry on EVERY peer, so
## remote copies ghost themselves. On the OWNING machine, ghosting also
## hands the view to the free spectator rig (feature/spectator-mode).
var _ghosted := false
var _spectator_rig: Node3D = null

## Current form: PlayerForms.SLIME or a PlayerForms.PROPS key. Replicated via
## the MultiplayerSynchronizer (on change + spawn state); remote copies and
## late joiners apply it through the setter.
var form_id: String = PlayerForms.SLIME:
	set = _set_form_id

## Paint lifetime counter: the OWNER bumps it on every form change; replicated
## on change + spawn state, and also carried by every paint event. Whoever
## learns of a newer epoch first wipes the old paint, so the stroke-vs-
## transform ordering race always converges. Never decreases.
var paint_epoch: int = 0:
	set = _set_paint_epoch

## Loss-of-cohesion drip, 0..1 (SPEC.md 6): written by the RotationTracker on
## the owning peer during the grace window, replicated on change, and drawn
## as a growing puddle under the body on EVERY peer via the setter.
var rotation_drip: float = 0.0:
	set = _set_rotation_drip

func _enter_tree() -> void:
	# The host names each capsule after the owning peer's ID (main.gd).
	var peer_id := str(name).to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	_ensure_input_actions()

func _ready() -> void:
	# Remote copies are driven by the synchronizer, never by local physics —
	# but they DO keep _physics_process to pin their collider (see below).
	var local := is_multiplayer_authority()
	set_process_unhandled_input(local)
	_prev_position = global_position
	if local:
		_spring_arm.rotation.x = CAMERA_PITCH_START
		_spring_arm.add_excluded_object(get_rid())
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_paint_hud = PaintHudScene.instantiate()
		_paint_hud.name = "PaintHud"
		add_child(_paint_hud)
		_paint_hud.color_changed.connect(_on_paint_color_picked)
		_paint_hud.grundieren_pressed.connect(_on_grundieren)
		_paint_hud.clear_pressed.connect(_on_clear_paint)
		_paint_hud.set_color(painter.brush_color)
	else:
		# Remote copies need no camera rig; their facing arrives via the
		# synchronizer as $Visual rotation.
		_camera_pivot.queue_free()
	_game_state = RoundLocator.locate(self)
	if _game_state != null:
		_game_state.roles_assigned.connect(_on_round_roles_assigned)
		_game_state.phase_changed.connect(_on_round_phase_changed)
		_game_state.registry_changed.connect(_refresh_ghost)
		_game_state.round_reset.connect(_on_round_reset)
	_npc_manager = RoundLocator.locate_named(self, ^"NpcManager")
	_seeker_combat = RoundLocator.locate_named(self, ^"SeekerCombat")
	_apply_form()
	_set_rotation_drip(rotation_drip)  # spawn state may precede @onready
	_refresh_ghost()  # late joiners may spawn into an already-running round

func _unhandled_input(event: InputEvent) -> void:
	if _ghosted:
		return  # the dead don't paint, transform, or recapture the mouse
	if _paint_mode and _handle_paint_mode_input(event):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit_camera(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		# Esc frees the mouse so the lobby UI stays usable; any click that the
		# UI does not consume recaptures it.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not _paint_mode and event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# Any click the UI ignores recaptures the mouse (Phase 2 behavior).
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT and _is_armed_seeker():
			_fire_paintball()
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
	if event.is_action_pressed("eyedropper"):
		_eyedrop_pending = true
		return true
	if event.is_action_pressed("grundieren"):
		_on_grundieren()
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
	if _paint_hud != null:
		_paint_hud.set_color(painter.brush_color)
		_paint_hud.visible = true

func _exit_paint_mode() -> void:
	_paint_mode = false
	_paint_dragging = false
	_orbit_dragging = false
	_pending_paint.clear()
	_eyedrop_pending = false
	if _paint_hud != null:
		_paint_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_paint_color_picked(color: Color) -> void:
	painter.brush_color = color

## One-click base coat with the current brush color (SPEC.md 9.3 Grundieren —
## the mandatory speed tool for the 60-s rotation loop: sample, prime, go).
func _on_grundieren() -> void:
	if form_id == PlayerForms.SLIME:
		return
	_paint_sync.local_fill(painter.brush_color)

## Alles-Löschen: back to neutral white, form and binding stay.
func _on_clear_paint() -> void:
	if form_id == PlayerForms.SLIME:
		return
	_paint_sync.local_clear()

## Raycasts must not run inside input callbacks (the physics space may be
## locked there); queue the screen point and resolve it next physics tick.
## Points over any UI control are dropped — clicking the color picker must
## never paint through it.
func _queue_paint(screen_pos: Vector2) -> void:
	if get_viewport().gui_get_hovered_control() != null:
		return
	if _pending_paint.size() < PAINT_QUEUE_MAX:
		_pending_paint.append(screen_pos)

## Resolve queued paint points and eyedrops. Strokes only land on the OWN body
## (whose collision volume is the current prop form); the eyedropper samples
## ANY surface under the cursor (SPEC.md 9.3).
func _drain_paint_queue() -> void:
	if _pending_paint.is_empty() and not _eyedrop_pending:
		return
	var space := get_world_3d().direct_space_state
	for screen_pos in _pending_paint:
		var hit := _cursor_raycast(space, screen_pos)
		if not hit.is_empty() and hit.collider == self:
			var uv: Vector2 = painter.world_point_to_uv(hit.position)
			if uv.x >= 0.0:
				_paint_sync.local_stroke(uv, painter.brush_color)
	_pending_paint.clear()
	if _eyedrop_pending:
		_eyedrop_pending = false
		var sample_hit := _cursor_raycast(space, get_viewport().get_mouse_position())
		if not sample_hit.is_empty():
			var sampled = Eyedropper.sample_color(sample_hit.collider, sample_hit.position)
			if sampled is Color:
				painter.brush_color = sampled
				if _paint_hud != null:
					_paint_hud.set_color(sampled)

func _cursor_raycast(space: PhysicsDirectSpaceState3D, screen_pos: Vector2) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_pos)
	var target := origin + _camera.project_ray_normal(screen_pos) * PAINT_RAY_LENGTH
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target))

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
	if not is_multiplayer_authority():
		# Remote copies never simulate, but their COLLIDERS must follow the
		# synced node transform — the engine-side propagation for these
		# never-simulated bodies proved unreliable after ghost episodes
		# (stale phantom colliders lingered at death spots and launched
		# players parked there; found via the rotation-timer flake). Pinning
		# the body every tick is cheap (≤ 8 players) and also keeps the
		# host-side paintball raycasts honest.
		PhysicsServer3D.body_set_state(get_rid(),
				PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
		return
	if _ghosted:
		return  # frozen where it died; Phase 6 gives the dead a free camera
	_drain_paint_queue()
	_update_feeding(delta)

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
## While a round runs, the SPEC.md 8 eat table gates the size (hiders) and
## seekers may not transform at all; the lobby stays a free sandbox.
func transform_to_prop(prop_id: String) -> void:
	if not is_multiplayer_authority():
		return
	if not _may_transform_to(prop_id):
		return
	form_id = prop_id

## The eat-table gate (SPEC.md 8). Runs only on the owning peer — remote
## copies follow the synchronizer, whose values the owner already validated.
func _may_transform_to(prop_id: String) -> bool:
	if _game_state == null or not _game_state.is_round_active():
		return true  # lobby sandbox / bare test capsules
	var me := get_multiplayer_authority()
	var role: int = _game_state.role_of(me)
	if role == _game_state.Role.SEEKER:
		_flash_notice("Sucher verwandeln sich nicht.")
		return false
	if role != _game_state.Role.HIDER:
		return false  # mid-round spectators have no body to disguise
	if not Progression.is_size_unlocked(_game_state.eaten_of(me), PlayerForms.size_of(prop_id)):
		_flash_notice("Noch nicht freigeschaltet — friss NPC-Slimes!")
		return false
	return true

func _flash_notice(text: String) -> void:
	get_tree().call_group("round_hud", "flash_notice", text)

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
		if is_multiplayer_authority():
			paint_epoch += 1  # owner: a new form is a new paint lifetime (wipes)
		_apply_form()  # before ready, _ready()'s _apply_form picks the value up

## Single write path for the drip — tracker (owner) and synchronizer
## (replicas) both land here; the puddle visual follows on every peer.
func _set_rotation_drip(value: float) -> void:
	rotation_drip = clampf(value, 0.0, 1.0)
	if _drip_puddle == null:
		return  # spawn state before @onready — _ready() re-applies
	_drip_puddle.visible = rotation_drip > 0.01
	var s := maxf(rotation_drip, 0.01)
	_drip_puddle.scale = Vector3(s, 1.0, s)

## Single write path for the epoch — owner bumps, synchronizer, and inbound
## paint events all land here. An increase wipes the paint (props always
## spawn white, SPEC.md 9.1) and releases the event history; regressions are
## stale packets and ignored.
func _set_paint_epoch(value: int) -> void:
	if value <= paint_epoch:
		return
	paint_epoch = value
	painter.clear_paint()
	if _paint_sync != null:  # spawn state can arrive before @onready resolves
		_paint_sync.reset_history()

## Make the tree match form_id: exactly one visible form — the slime meshes OR
## one prop scene under $Visual/PropAnchor — plus the registry's collision
## volume. Stale prop visuals are detached immediately so no frame ever shows
## two forms at once. The painter REBINDS without wiping: the paint lifetime
## belongs to paint_epoch (wiped there — on the owner the bump precedes this,
## on replicas epoch and form may arrive in either order).
func _apply_form() -> void:
	for stale in _prop_anchor.get_children():
		_prop_anchor.remove_child(stale)
		stale.free()
	var is_slime := form_id == PlayerForms.SLIME
	_slime_visual.visible = is_slime
	if is_slime:
		painter.rebind_prop(null)
	else:
		var prop: Node = load(PlayerForms.scene_path(form_id)).instantiate()
		_prop_anchor.add_child(prop)
		painter.rebind_prop(_find_prop_mesh(prop))
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

## Feeding (SPEC.md 7): hold E for 1 s next to a sleeping NPC — hiders only,
## PREP only. This runs on the OWNING peer: it tracks the hold and the slurp
## cosmetic, then sends ONE eat request that the host validates (phase, role,
## real distance). Interaction prompts appear only near NPCs; other players
## are never edible.
func _update_feeding(delta: float) -> void:
	if _game_state == null or _npc_manager == null:
		return
	var me := get_multiplayer_authority()
	var eligible: bool = _game_state.current_phase == _game_state.Phase.PREP \
			and _game_state.role_of(me) == _game_state.Role.HIDER \
			and _game_state.is_alive(me)
	var npc: Node3D = null
	if eligible:
		npc = _npc_manager.nearest_living_npc(global_position, EAT_REACH)
	if npc == null:
		_reset_feeding()
		return
	if npc != _slurp_npc:
		_reset_feeding()
		_slurp_npc = npc
	if Input.is_action_pressed("fressen"):
		_eat_hold += delta
		npc.set_slurp(_eat_hold / EAT_HOLD_SECONDS)
		if _eat_hold >= EAT_HOLD_SECONDS:
			var npc_id: int = npc.npc_id
			_reset_feeding()
			_npc_manager.request_eat_from(me, npc_id)
	else:
		_eat_hold = 0.0
		npc.reset_slurp()
	get_tree().call_group("round_hud", "set_eat_prompt",
			"[E] Fressen — halten", _eat_hold / EAT_HOLD_SECONDS)

func _reset_feeding() -> void:
	_eat_hold = 0.0
	if _slurp_npc != null and is_instance_valid(_slurp_npc):
		_slurp_npc.reset_slurp()
	_slurp_npc = null
	get_tree().call_group("round_hud", "set_eat_prompt", "", 0.0)

const SPLATTER_SPRAY_STAMPS := 5
const SPLATTER_SPRAY_COLOR := Color(0.95, 0.2, 0.75)  # the paintball magenta

## A near-miss splatter caught this prop (SPEC.md 11 — "Angesprühte
## Verstecker müssen übermalen oder fliegen auf"). Only the OWNER converts
## the spray into its own normal paint-stroke events: exactly-once across
## the session, and late joiners replay it with the regular paint history.
func apply_splatter_spray(global_hit: Vector3, seed_value: int) -> void:
	if not is_multiplayer_authority() or form_id == PlayerForms.SLIME:
		return
	if _game_state != null and not _game_state.is_alive(get_multiplayer_authority()):
		return
	var center_uv: Vector2 = painter.world_point_to_uv(global_hit)
	if center_uv.x < 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_paint_sync.local_stroke(center_uv, SPLATTER_SPRAY_COLOR)
	for _i in SPLATTER_SPRAY_STAMPS - 1:
		var jitter := Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
		var uv := (center_uv + jitter).clamp(Vector2.ZERO, Vector2.ONE)
		_paint_sync.local_stroke(uv, SPLATTER_SPRAY_COLOR)

## The paintball gun (SPEC.md 11): seekers only, HUNT only, alive only.
func _is_armed_seeker() -> bool:
	if _game_state == null or _seeker_combat == null:
		return false
	var me := get_multiplayer_authority()
	return _game_state.current_phase == _game_state.Phase.HUNT \
			and _game_state.is_seeker(me) and _game_state.is_alive(me)

## Fire straight down the camera center (the crosshair). Coordinates travel
## parent-relative so the host validates them against its own copy.
func _fire_paintball() -> void:
	var dir: Vector3 = -_camera.global_transform.basis.z
	var muzzle_global: Vector3 = _camera.global_position + dir * 1.0
	var origin_rel: Vector3 = (get_parent() as Node3D).to_local(muzzle_global)
	_seeker_combat.request_fire_from(get_multiplayer_authority(), origin_rel, dir)

## Ghosting is DERIVED state: replicated registry + phase decide it, so every
## peer's copy of a dead capsule hides itself without extra sync traffic.
## Mid-round joiners (role NONE, not alive) ghost too — they spectate until
## the next round instead of roaming the hunt as visible slimes.
func _refresh_ghost() -> void:
	if _game_state == null:
		return
	var me := get_multiplayer_authority()
	var should: bool = _game_state.current_phase != _game_state.Phase.LOBBY \
			and _game_state.players.has(me) and not _game_state.is_alive(me)
	if should == _ghosted:
		return
	_ghosted = should
	visible = not should
	collision_layer = 0 if should else 1
	# Disable the SHAPE too, not just the layer: a ghosted authority stops
	# simulating, and remote copies' kinematic bodies then linger SOLID at the
	# death spot even after the reset teleports the node away (verified: a
	# player parked on a corpse spot got depenetration-launched). Re-enabling
	# re-registers the collider at the current synced transform. Deferred —
	# shape toggles must not land while the physics space is flushing.
	_collision.set_deferred("disabled", should)
	if is_multiplayer_authority():
		if should and _paint_mode:
			_exit_paint_mode()
		if should:
			_enter_spectator()
		else:
			_exit_spectator()

## The dead watch through a free-fly rig next to the corpse (SPEC.md 5.3);
## LOCAL-ONLY, parented to the world so the invisible body doesn't drag it.
func _enter_spectator() -> void:
	if _spectator_rig != null or _game_state == null:
		return
	var world := _game_state.get_parent()
	if world == null:
		return
	_spectator_rig = SpectatorCameraScene.instantiate()
	world.add_child(_spectator_rig)
	_spectator_rig.global_position = global_position + Vector3(0.0, 2.0, 0.0)

func _exit_spectator() -> void:
	if _spectator_rig == null:
		return
	if is_instance_valid(_spectator_rig):
		_spectator_rig.queue_free()
	_spectator_rig = null
	if _camera != null and is_instance_valid(_camera):
		_camera.current = true

func _exit_tree() -> void:
	_exit_spectator()  # a despawning capsule never strands its rig

## Full per-round reset (SPEC.md 5.3): back to slime (wipes paint via the
## epoch), back to the spawn, dry floor. The registry cleared by the host
## un-ghosts everyone through _refresh_ghost.
func _on_round_reset() -> void:
	if not is_multiplayer_authority():
		return
	transform_to_slime()
	rotation_drip = 0.0
	_teleport_to_group_marker("player_spawn")

## Round start (SPEC.md 5.1): the owner repositions itself for its role —
## seekers wait blind in the sealed spawn box, hiders start at the map spawn.
## Only the authority moves itself; everyone else sees it via the synchronizer.
func _on_round_roles_assigned() -> void:
	if not is_multiplayer_authority():
		return
	var role: int = _game_state.role_of(get_multiplayer_authority())
	if role == _game_state.Role.SEEKER:
		_teleport_to_group_marker("seeker_spawn")
	elif role == _game_state.Role.HIDER:
		_teleport_to_group_marker("player_spawn")

## Hunt start (SPEC.md 5.2): seekers are released into the map. Every copy
## also re-derives its ghost state — the phase is half of that condition.
func _on_round_phase_changed(phase: int) -> void:
	_refresh_ghost()
	if not is_multiplayer_authority():
		return
	if phase == _game_state.Phase.HUNT and _game_state.is_seeker(get_multiplayer_authority()):
		_teleport_to_group_marker("player_spawn")

## Teleport to the first marker in `group` under this capsule's world (the
## GameState's parent — /root in the real game, the branch root in tests),
## fanned by registry slot so simultaneous teleports never stack players.
func _teleport_to_group_marker(group: String) -> void:
	var world: Node = _game_state.get_parent()
	if world == null:
		return
	var target: Node3D = null
	for marker in world.find_children("*", "Marker3D", true, false):
		if marker.is_in_group(group):
			target = marker
			break
	if target == null:
		return
	var ids: Array = _game_state.players.keys()
	ids.sort()
	var slot := maxi(ids.find(get_multiplayer_authority()), 0)
	var angle := float(slot) * TAU / 8.0
	global_position = target.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.2
	velocity = Vector3.ZERO

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
		# Paint mode toggle (Phase 4). P as in Pinsel; E is Fressen (below).
		"paint_mode": [KEY_P],
		# Hold E next to a sleeping NPC to eat it (SPEC.md 7, Phase 5).
		"fressen": [KEY_E],
		# 3D eyedropper in paint mode. Q, not E — E is the future Fressen key.
		"eyedropper": [KEY_Q],
		# One-click base coat in paint mode (SPEC.md 9.3 Grundieren).
		"grundieren": [KEY_G],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
