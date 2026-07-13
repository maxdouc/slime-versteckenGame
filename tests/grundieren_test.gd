extends SceneTree
## Headless test — Grundieren + Alles-Löschen (Phase 4,
## feature/grundieren-button).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/grundieren_test.gd
##
## SPEC.md 9.3: the Grundieren button is a MANDATORY feature — one click and
## the current color covers the whole object (without it the 60-s rotation
## loop is unplayable). Alles-Löschen resets to neutral white. SPEC.md 9.1/9.2
## boundaries: paint survives movement while the form is held, returning to
## slime wipes it.
##
## Covers: painter.fill()/clear_paint() semantics, stamp-over-fill layering,
## HUD buttons + signal wiring into the capsule, the G hotkey action, and the
## keep-while-moving / wipe-on-slime rules end to end on the real capsule.
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const PAINTER_PATH := "res://scripts/paint/prop_painter.gd"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const HUD_SCENE_PATH := "res://scenes/paint_hud.tscn"
const TIMEOUT_SEC := 60.0
const WHITE := Color(1, 1, 1, 1)

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false
var _probe_hits := 0

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		printerr("[grundieren_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[grundieren_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[grundieren_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

## RGBA8 storage quantizes colors, so compare with ~1.5/255 tolerance.
func _color_close(a: Color, b: Color, tol := 0.007) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
			and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol

## True when every probed pixel (corners, edges, center) has `color`.
func _image_solid(img: Image, color: Color) -> bool:
	var size := img.get_width()
	for p in [Vector2i(0, 0), Vector2i(size - 1, 0), Vector2i(0, size - 1),
			Vector2i(size - 1, size - 1), Vector2i(size / 2, size / 2),
			Vector2i(size / 2, 0), Vector2i(0, size / 2)]:
		if not _color_close(img.get_pixelv(p), color):
			return false
	return true

func _on_probe() -> void:
	_probe_hits += 1

func _run_tests() -> void:
	await process_frame
	var painter_script: GDScript = load(PAINTER_PATH)

	# --- Painter: fill (Grundieren core) ------------------------------------
	print("[grundieren_test] painter.fill")
	var painter: RefCounted = painter_script.new()
	if not painter.has_method("fill") or not painter.has_method("clear_paint"):
		_check(false, "painter exposes fill() and clear_paint() — skipping all")
		_finish()
		return
	_check(true, "painter exposes fill() and clear_paint()")

	var moss := Color(0.25, 0.55, 0.2)
	painter.fill(moss)
	_check(painter.is_painted(), "fill marks the painter painted")
	_check(painter.image() != null and _image_solid(painter.image(), moss),
			"fill covers every pixel with the color")

	var red := Color(0.82, 0.13, 0.10)
	painter.stamp_uv(Vector2(0.5, 0.5), red)
	_check(_color_close(painter.color_at_uv(Vector2(0.5, 0.5)), red),
			"a stamp lands on top of the base coat")
	_check(_color_close(painter.color_at_uv(Vector2(0.05, 0.05)), moss),
			"the base coat survives around the stamp")

	painter.fill(WHITE)
	_check(_image_solid(painter.image(), WHITE), "re-filling paints over everything")

	# --- Painter: clear_paint (Alles-Löschen core) ---------------------------
	print("[grundieren_test] painter.clear_paint")
	var carton: Node = (load("res://scenes/props/prop_carton.tscn") as PackedScene).instantiate()
	root.add_child(carton)
	var mesh: MeshInstance3D = carton.find_children("*", "MeshInstance3D", true, false)[0]
	var pristine: Material = mesh.get_surface_override_material(0)
	var bound: RefCounted = painter_script.new()
	bound.bind_prop(mesh)
	bound.fill(moss)
	_check(mesh.get_surface_override_material(0) != pristine,
			"fill on a bound prop applies the paint material")
	bound.clear_paint()
	_check(not bound.is_painted() and bound.image() == null,
			"clear_paint drops the paint state entirely (back to lazy)")
	_check(mesh.get_surface_override_material(0) == pristine,
			"clear_paint restores the pristine shared white material")
	_check(bound.bound_mesh_instance() == mesh,
			"clear_paint keeps the prop bound (painting can continue)")
	bound.stamp_uv(Vector2(0.5, 0.5), red)
	_check(bound.is_painted() and mesh.get_surface_override_material(0) != pristine,
			"painting after clear_paint rebinds the paint material")
	bound.unbind()
	carton.queue_free()

	# --- HUD: buttons exist and re-emit as signals ----------------------------
	print("[grundieren_test] HUD buttons")
	var hud: CanvasLayer = (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var grundieren_button: Button = hud.get_node_or_null("Panel/Margin/Rows/Actions/GrundierenButton")
	var clear_button: Button = hud.get_node_or_null("Panel/Margin/Rows/Actions/ClearButton")
	_check(grundieren_button != null, "HUD has the Grundieren button (SPEC.md 9.3: Pflicht)")
	_check(clear_button != null, "HUD has the Alles-Löschen button")
	var has_signals: bool = hud.has_signal("grundieren_pressed") and hud.has_signal("clear_pressed")
	_check(has_signals, "HUD exposes grundieren_pressed/clear_pressed signals")
	if grundieren_button != null and has_signals:
		hud.grundieren_pressed.connect(_on_probe)
		_probe_hits = 0
		grundieren_button.pressed.emit()
		_check(_probe_hits == 1, "Grundieren button press emits grundieren_pressed")
	if clear_button != null and has_signals:
		hud.clear_pressed.connect(_on_probe)
		_probe_hits = 0
		clear_button.pressed.emit()
		_check(_probe_hits == 1, "Alles-Löschen button press emits clear_pressed")
	hud.queue_free()

	# --- Capsule: one-click base coat with the current color ------------------
	print("[grundieren_test] capsule wiring")
	var room: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room)
	var player: CharacterBody3D = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	player.name = "1"  # offline unique id -> local authority
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)
	await process_frame
	_check(InputMap.has_action("grundieren"), "grundieren hotkey action is registered")

	var capsule_hud: CanvasLayer = player.get_node_or_null("PaintHud")
	if capsule_hud == null:
		_check(false, "capsule HUD missing — skipping capsule checks")
		_finish()
		return
	player.transform_to_prop("carton")
	player.painter.brush_color = moss
	capsule_hud.grundieren_pressed.emit()
	_check(player.painter.is_painted()
			and _image_solid(player.painter.image(), moss),
			"Grundieren covers the whole prop with the CURRENT color")

	# --- Capsule: paint survives movement in the same form (SPEC.md 9.2) ------
	var before: PackedByteArray = player.painter.image().get_data()
	for i in 90:
		if player.is_on_floor():
			break
		await physics_frame
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	_check(player.painter.is_painted()
			and player.painter.image().get_data() == before,
			"paint survives walking in the same form, byte-identical")
	var walked_mesh: MeshInstance3D = player.painter.bound_mesh_instance()
	_check(walked_mesh != null and is_instance_valid(walked_mesh)
			and walked_mesh.get_surface_override_material(0) != null
			and walked_mesh.get_surface_override_material(0).albedo_texture == player.painter.texture(),
			"the paint material stays bound while moving")

	# --- Capsule: Alles-Löschen ------------------------------------------------
	capsule_hud.clear_pressed.emit()
	_check(not player.painter.is_painted(),
			"Alles-Löschen resets the prop to neutral white")
	_check(player.painter.bound_mesh_instance() != null,
			"Alles-Löschen keeps the form and the binding")

	# --- Capsule: returning to slime wipes a base coat (SPEC.md 9.1) ----------
	capsule_hud.grundieren_pressed.emit()
	_check(player.painter.is_painted(), "re-primed for the slime-wipe check")
	player.transform_to_slime()
	_check(not player.painter.is_painted(), "returning to slime wipes the base coat")
	player.transform_to_prop("carton")
	_check(not player.painter.is_painted(),
			"transforming again starts from neutral white, not the old coat")

	player.queue_free()
	room.queue_free()
	await process_frame
	_finish()
