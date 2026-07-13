extends SceneTree
## Headless test — prop movement speed tiers (Phase 3, feature/prop-speed-tiers).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/speed_tiers_test.gd
##
## SPEC.md 9.2's speed table is hardcoded here on purpose — the test is the
## spec: slime 100 %, small 80 %, medium 60 %, large 40 % of the slime base
## speed. Checks the registry table, the player's effective max_speed(), and —
## the part that counts — the real displacement measured over exactly one
## second of fixed-60-Hz physics per form, driven through the real input
## actions in the real gray room. Prints one line per check and exits 0/1.

const FORMS_SCRIPT_PATH := "res://scripts/player_forms.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const TIMEOUT_SEC := 90.0

## SPEC.md 9.2 — do not derive these from the implementation.
const EXPECTED_MULTIPLIER := {"SLIME": 1.0, "SMALL": 0.8, "MEDIUM": 0.6, "LARGE": 0.4}
## Measured displacement may differ from v*t by frame boundary effects only.
const TOLERANCE := 0.05

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		printerr("[speed_tiers_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
		_done = true
		quit(1)
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
		print("[speed_tiers_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[speed_tiers_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _run_tests() -> void:
	await process_frame

	var forms: GDScript = load(FORMS_SCRIPT_PATH)

	# --- Registry table (SPEC.md 9.2, exact values) --------------------------
	print("[speed_tiers_test] registry table")
	if forms.get("SPEED_MULTIPLIERS") != null:
		_check(forms.speed_multiplier(forms.SLIME) == 1.0, "slime multiplier is exactly 1.0")
		for pair in [["SMALL", 0.8], ["MEDIUM", 0.6], ["LARGE", 0.4]]:
			var prop_id: String = forms.first_prop_of_size(forms.Size[pair[0]])
			_check(forms.speed_multiplier(prop_id) == pair[1],
					"%s (%s) multiplier is exactly %.1f" % [pair[0], prop_id, pair[1]])
	else:
		_check(false, "registry exposes SPEED_MULTIPLIERS/speed_multiplier() (skipping table checks)")

	# --- Player in the gray room ---------------------------------------------
	print("[speed_tiers_test] measured physics speed per form")
	var room: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room)
	var player: CharacterBody3D = load(PLAYER_SCENE_PATH).instantiate()
	player.name = "1"  # offline unique id -> local authority, camera yaw 0
	player.position = Vector3(0.0, 0.5, 4.5)
	root.add_child(player)
	for i in 90:
		if player.is_on_floor():
			break
		await physics_frame
	_check(player.is_on_floor(), "player settled on the floor")

	var base: float = player.WALK_SPEED
	var has_max_speed: bool = player.has_method("max_speed")
	_check(has_max_speed, "player exposes max_speed()")

	# W held down for the whole measurement run — camera yaw starts at 0, so
	# the player runs straight toward -Z; the room is 12 m, the runway is safe.
	Input.action_press("move_forward")
	var runs: Array = ["SLIME", "LARGE", "MEDIUM", "SMALL", "SLIME"]
	for run_index in runs.size():
		var wanted: String = runs[run_index]
		var label: String = wanted
		if wanted == "SLIME":
			label = "SLIME (baseline)" if run_index == 0 else "SLIME (restored)"
		if wanted == "SLIME":
			player.transform_to_slime()
		else:
			player.transform_to_prop(forms.first_prop_of_size(forms.Size[wanted]))
		var expected: float = base * EXPECTED_MULTIPLIER[wanted]
		if has_max_speed:
			_check(absf(player.max_speed() - expected) < 0.001,
					"%s: max_speed() is %.2f" % [label, expected])
		var measured: float = await _measure_speed(player)
		_check(absf(measured - expected) <= expected * TOLERANCE,
				"%s: measured %.2f m/s over 1 s of physics (expected %.2f ±%.0f%%)"
				% [label, measured, expected, TOLERANCE * 100.0])
		_check(player.is_on_floor(), "%s: still grounded after the run" % label)
	Input.action_release("move_forward")

	_finish()

## Teleport to the runway start, let the form settle + accelerate to steady
## state (45 ticks), then measure displacement across exactly 60 fixed physics
## ticks — one second at the project's 60 Hz physics rate.
func _measure_speed(player: CharacterBody3D) -> float:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.2, 4.5)
	for i in 45:
		await physics_frame
	var start: Vector3 = player.global_position
	for i in 60:
		await physics_frame
	var moved: Vector3 = player.global_position - start
	moved.y = 0.0
	return moved.length()
