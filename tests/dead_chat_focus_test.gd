extends SceneTree
## Headless test — dead-chat keyboard focus vs spectator control
## (fix/phase-5-9-manual-validation round 2, confirmed defect).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/dead_chat_focus_test.gd
##
## Manual validation found: typing W/A/S/D into the dead-chat LineEdit ALSO
## flew the spectator camera — the camera polls Input action state directly,
## which knows nothing about GUI focus. The fixed contract:
##
##   * while a text field owns the keyboard, spectator movement (WASD and
##     fly up/down) is fully suppressed;
##   * Enter submits the line, clears the field, RELEASES focus, and the
##     message reaches the dead chat;
##   * a mouse click outside the field releases focus too (and recaptures
##     the mouse, unchanged);
##   * with focus gone, movement works again.
##
## Runs offline (no peers): DeadChat's host path validates and delivers
## locally, which exercises the same submit pipeline. Exits 0 / 1.

const GAME_STATE_PATH := "res://scripts/game_state.gd"
const DEAD_CHAT_PATH := "res://scripts/round/dead_chat.gd"
const HUD_SCENE_PATH := "res://scenes/round_hud.tscn"
const SPECTATOR_SCENE_PATH := "res://scenes/spectator_camera.tscn"
const CAPSULE_SCRIPT_PATH := "res://scripts/player_capsule.gd"
const TIMEOUT_SEC := 60.0

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
		printerr("[dead_chat_focus_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
	Input.action_release("move_forward")
	Input.action_release("fly_up")
	if _failures == 0:
		print("[dead_chat_focus_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[dead_chat_focus_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _wait_frames(n: int) -> void:
	for _i in n:
		if _done:
			return
		await process_frame

func _run_tests() -> void:
	await process_frame
	# The production scripts register these actions themselves.
	(load(CAPSULE_SCRIPT_PATH) as GDScript)._ensure_input_actions()
	(load(SPECTATOR_SCENE_PATH) as PackedScene)  # spectator registers fly_* in _ready

	# --- World: offline round state with OUR player dead in HUNT ---------------
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var gs: Node = (load(GAME_STATE_PATH) as GDScript).new()
	gs.name = "GameState"
	world.add_child(gs)
	gs.set_process(false)  # freeze phase ticking — this test is about input
	gs.current_phase = gs.Phase.HUNT
	gs.players = {1: {"role": gs.Role.HIDER, "alive": false, "eaten": 0}}
	var chat: Node = (load(DEAD_CHAT_PATH) as GDScript).new()
	chat.name = "DeadChat"
	world.add_child(chat)
	var hud: Control = (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	world.add_child(hud)
	var rig: Node3D = (load(SPECTATOR_SCENE_PATH) as PackedScene).instantiate()
	world.add_child(rig)
	await process_frame
	await process_frame

	var chat_input: LineEdit = hud.get_node("DeadChatBox/ChatInput")
	var chat_log: Label = hud.get_node("DeadChatBox/ChatLog")
	_check(hud.get_node("DeadChatBox").visible, "dead chat visible for the dead player")

	# --- Baseline: unfocused movement works ------------------------------------
	var p0: Vector3 = rig.global_position
	Input.action_press("move_forward")
	await _wait_frames(6)
	Input.action_release("move_forward")
	_check(rig.global_position.distance_to(p0) > 0.1,
			"baseline: spectator flies while chat is NOT focused")

	# --- Focused: every movement axis is suppressed ----------------------------
	chat_input.grab_focus()
	await process_frame
	_check(hud.get_viewport().gui_get_focus_owner() == chat_input,
			"chat field took keyboard focus")
	var p1: Vector3 = rig.global_position
	Input.action_press("move_forward")
	Input.action_press("fly_up")
	await _wait_frames(8)
	Input.action_release("move_forward")
	Input.action_release("fly_up")
	_check(rig.global_position.distance_to(p1) < 0.001,
			"typing focus suppresses WASD and fly movement (was the bug)")

	# --- Enter: submit + deliver + clear + RELEASE focus -----------------------
	chat_input.text = "hallo zusammen"
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await _wait_frames(3)
	_check("hallo zusammen" in chat_log.text,
			"Enter submitted the line into the dead chat")
	_check(chat_input.text == "", "field cleared after submit")
	_check(hud.get_viewport().gui_get_focus_owner() == null,
			"Enter RELEASED the keyboard focus")

	# --- Movement restored after release ---------------------------------------
	var p2: Vector3 = rig.global_position
	Input.action_press("move_forward")
	await _wait_frames(6)
	Input.action_release("move_forward")
	_check(rig.global_position.distance_to(p2) > 0.1,
			"spectator control restored after Enter")

	# --- Click OUTSIDE the field releases focus too ----------------------------
	chat_input.grab_focus()
	await process_frame
	_check(hud.get_viewport().gui_get_focus_owner() == chat_input,
			"chat field focused again")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 20)  # far from the chat box (bottom-left area)
	Input.parse_input_event(click)
	await _wait_frames(3)
	_check(hud.get_viewport().gui_get_focus_owner() == null,
			"clicking outside the chat released its focus")
	var p3: Vector3 = rig.global_position
	Input.action_press("move_forward")
	await _wait_frames(6)
	Input.action_release("move_forward")
	_check(rig.global_position.distance_to(p3) > 0.1,
			"spectator control restored after the outside click")

	_finish()
