extends SceneTree
## Headless test — 3D eyedropper + color picker (Phase 4,
## feature/eyedropper-and-colorpicker).
##
## Run from the repo root:
##
##     <godot> --headless --script tests/eyedropper_colorpicker_test.gd
##
## Covers:
##   1. prop_painter.color_at_uv() — reading back painted/unpainted colors.
##   2. eyedropper.gd — sampling the EXACT surface color (SPEC.md 9.3: "Nimmt
##      die exakte Farbe jeder angepeilten Oberfläche auf"): plain materials,
##      override materials (how the gray room is built), textured materials
##      (albedo modulate), painted props on player capsules, hidden-mesh
##      selection (a transformed capsule samples its prop, not the hidden
##      slime body), and surfaces nothing can be sampled from.
##   3. paint_hud.tscn — HSV color picker wiring on the local capsule: the
##      picker drives painter.brush_color, the screen-pixel sampler is off
##      (it would sample LIT colors — the 3D eyedropper is the real tool),
##      remote copies get no HUD.
## Prints one line per check and exits 0 (all ok) / 1 (any FAIL).

const EYEDROPPER_PATH := "res://scripts/paint/eyedropper.gd"
const PAINTER_PATH := "res://scripts/paint/prop_painter.gd"
const HUD_SCENE_PATH := "res://scenes/paint_hud.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player_capsule.tscn"
const ROOM_SCENE_PATH := "res://scenes/gray_room.tscn"
const TIMEOUT_SEC := 60.0
const WHITE := Color(1, 1, 1, 1)
const ROOM_GRAY := Color(0.6, 0.6, 0.6, 1)

var _checks := 0
var _failures := 0
var _elapsed := 0.0
var _done := false

func _initialize() -> void:
	_run_tests()

func _process(delta: float) -> bool:
	_elapsed += delta
	if not _done and _elapsed > TIMEOUT_SEC:
		printerr("[eyedropper_test] FAIL — timed out after %.0f s" % TIMEOUT_SEC)
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
		print("[eyedropper_test] PASS — all %d checks ok" % _checks)
	else:
		printerr("[eyedropper_test] FAIL — %d of %d checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

## RGBA8 storage quantizes colors, so compare with ~1.5/255 tolerance.
func _color_close(a, b: Color, tol := 0.007) -> bool:
	if not (a is Color):
		return false
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
			and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol

func _run_tests() -> void:
	await process_frame

	print("[eyedropper_test] scripts and scenes load")
	var dropper: GDScript = load(EYEDROPPER_PATH) if ResourceLoader.exists(EYEDROPPER_PATH) else null
	var painter_script: GDScript = load(PAINTER_PATH)
	_check(dropper != null, "scripts/paint/eyedropper.gd exists and loads")
	_check(ResourceLoader.exists(HUD_SCENE_PATH), "scenes/paint_hud.tscn exists")
	if dropper == null or not ResourceLoader.exists(HUD_SCENE_PATH):
		_finish()
		return

	# --- painter.color_at_uv -----------------------------------------------
	print("[eyedropper_test] painter color readback")
	var readback: RefCounted = painter_script.new()
	if readback.has_method("color_at_uv"):
		_check(_color_close(readback.color_at_uv(Vector2(0.3, 0.3)), WHITE),
				"unpainted painter reads back neutral white")
		var teal := Color(0.1, 0.55, 0.6)
		readback.stamp_uv(Vector2(0.5, 0.5), teal)
		_check(_color_close(readback.color_at_uv(Vector2(0.5, 0.5)), teal),
				"painted painter reads back the stamped color")
		_check(_color_close(readback.color_at_uv(Vector2(0.05, 0.05)), WHITE),
				"pixels outside the stamp still read white")
	else:
		_check(false, "painter exposes color_at_uv()")

	# --- Eyedropper: plain and override materials ---------------------------
	print("[eyedropper_test] eyedropper on static surfaces")
	var room: Node = load(ROOM_SCENE_PATH).instantiate()
	root.add_child(room)
	var wall: StaticBody3D = room.get_node("WallNorth")
	var wall_sample = dropper.sample_color(wall, Vector3(1.0, 1.5, -5.9))
	_check(_color_close(wall_sample, ROOM_GRAY),
			"gray-room wall samples its exact material color (got %s)" % str(wall_sample))
	var floor_body: StaticBody3D = room.get_node("Floor")
	var floor_sample = dropper.sample_color(floor_body, Vector3(2.0, 0.1, 3.0))
	_check(_color_close(floor_sample, ROOM_GRAY), "floor samples the same gray")

	# --- Eyedropper: textured material modulates albedo ----------------------
	# 8x8 texture, one blue pixel at (4,6) — exactly where the +Y face CENTER
	# lands (cell center uv (0.5, 0.75)), which is orientation-independent.
	# The white probe point is chosen symmetric in x/z so it can never hit
	# (4,6) no matter how the face's UV axes are oriented or mirrored.
	var tex_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tex_image.fill(Color(1, 1, 1, 1))
	tex_image.set_pixel(4, 6, Color(0.0, 0.0, 1.0, 1.0))
	var tex_body := StaticBody3D.new()
	var tex_mesh := MeshInstance3D.new()
	var tex_box := BoxMesh.new()
	tex_box.size = Vector3(1, 1, 1)
	tex_mesh.mesh = tex_box
	var tex_mat := StandardMaterial3D.new()
	tex_mat.albedo_color = Color(0.5, 1.0, 0.5, 1.0)
	tex_mat.albedo_texture = ImageTexture.create_from_image(tex_image)
	tex_mesh.set_surface_override_material(0, tex_mat)
	tex_body.add_child(tex_mesh)
	root.add_child(tex_body)
	tex_body.position = Vector3(30.0, 0.0, 0.0)
	var tex_sample = dropper.sample_color(tex_body, Vector3(30.0, 0.5, 0.0))
	_check(_color_close(tex_sample, Color(0.0, 0.0, 0.5, 1.0)),
			"textured surface samples texel x albedo tint (got %s)" % str(tex_sample))
	var tex_sample_white = dropper.sample_color(tex_body, Vector3(29.65, 0.5, -0.35))
	_check(_color_close(tex_sample_white, Color(0.5, 1.0, 0.5, 1.0)),
			"white texel leaves only the albedo tint")

	# --- Eyedropper: nothing to sample ---------------------------------------
	var bare := StaticBody3D.new()
	root.add_child(bare)
	_check(dropper.sample_color(bare, Vector3.ZERO) == null,
			"a body without any mesh samples null (keep current color)")
	_check(dropper.sample_color(null, Vector3.ZERO) == null, "null collider samples null")

	# --- Eyedropper: player capsules ------------------------------------------
	print("[eyedropper_test] eyedropper on player capsules")
	var player: CharacterBody3D = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	player.name = "1"  # offline unique id -> local authority
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)
	await process_frame

	var slime_sample = dropper.sample_color(player, player.position + Vector3(0.0, 0.5, -0.5))
	_check(_color_close(slime_sample, WHITE), "slime capsule samples its white body")

	player.transform_to_prop("carton")
	var prop_mesh: MeshInstance3D = player.painter.bound_mesh_instance()
	var top_center: Vector3 = prop_mesh.global_transform * Vector3(0.0, 0.55, 0.0)
	var unpainted_sample = dropper.sample_color(player, top_center)
	_check(_color_close(unpainted_sample, WHITE),
			"unpainted prop samples neutral white via the VISIBLE prop mesh")

	var moss := Color(0.25, 0.55, 0.2)
	player.painter.stamp_uv(Vector2(0.5, 0.75), moss)  # the box-top atlas cell center
	var painted_sample = dropper.sample_color(player, top_center)
	_check(_color_close(painted_sample, moss),
			"painted prop samples the EXACT painted color (got %s)" % str(painted_sample))
	var side_center: Vector3 = prop_mesh.global_transform * Vector3(0.0, 0.0, 0.55)
	var side_sample = dropper.sample_color(player, side_center)
	_check(_color_close(side_sample, WHITE), "unpainted side of the same prop still samples white")

	# --- HUD: local capsule wiring --------------------------------------------
	print("[eyedropper_test] color picker HUD")
	_check(InputMap.has_action("eyedropper"), "eyedropper input action is registered")
	var hud: CanvasLayer = player.get_node_or_null("PaintHud")
	_check(hud != null, "local capsule instances the paint HUD")
	if hud != null:
		_check(not hud.visible, "HUD starts hidden (only paint mode shows it)")
		var pickers: Array[Node] = hud.find_children("*", "ColorPicker", true, false)
		_check(pickers.size() == 1, "HUD contains exactly one ColorPicker")
		if pickers.size() == 1:
			var picker: ColorPicker = pickers[0]
			_check(not picker.edit_alpha, "picker has no alpha channel (strokes are opaque)")
			_check(picker.picker_shape == ColorPicker.SHAPE_HSV_WHEEL,
					"picker uses the HSV color wheel (SPEC.md 9.3: Farbrad + HSV)")
			_check(not picker.sampler_visible,
					"screen-pixel sampler is hidden — the 3D eyedropper is the only sampler")
			var plum := Color(0.55, 0.2, 0.5)
			picker.color = plum
			picker.color_changed.emit(plum)
			_check(player.painter.brush_color == plum, "picking a color drives the brush color")
			player.painter.stamp_uv(Vector2(0.1, 0.1), player.painter.brush_color)
			_check(_color_close(player.painter.color_at_uv(Vector2(0.1, 0.1)), plum),
					"the brush paints with the picked color")
			if hud.has_method("set_color"):
				hud.set_color(Color(0.9, 0.9, 0.1))
				_check(picker.color == Color(0.9, 0.9, 0.1),
						"set_color pushes eyedropper results into the picker")
			else:
				_check(false, "HUD exposes set_color()")

	# --- HUD: remote copies get none -------------------------------------------
	var remote: CharacterBody3D = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate()
	remote.name = "2"  # not the offline unique id -> remote copy
	remote.position = Vector3(3.0, 1.0, 0.0)
	root.add_child(remote)
	await process_frame
	_check(remote.get_node_or_null("PaintHud") == null, "remote copies get no paint HUD")

	player.queue_free()
	remote.queue_free()
	tex_body.queue_free()
	bare.queue_free()
	room.queue_free()
	await process_frame
	_finish()
