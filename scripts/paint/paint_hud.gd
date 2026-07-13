extends CanvasLayer
## Paint-mode HUD: color wheel + HSV controls driving the brush color
## (Phase 4, feature/eyedropper-and-colorpicker — SPEC.md 9.3 "Farbrad +
## HSV-Regler"). player_capsule.gd instances this for the LOCAL player only
## and shows it while paint mode is active.
##
## The picker's built-in screen-pixel sampler stays hidden: it reads LIT
## screen colors — neither deterministic nor reproducible by painting. The 3D
## eyedropper (Q, handled by player_capsule.gd) is the one sampling tool; its
## results arrive here through set_color().

## Emitted when the player picks a color in the UI (never for set_color pushes).
signal color_changed(color: Color)
## One-click base coat with the current color (SPEC.md 9.3: Pflicht-Feature).
signal grundieren_pressed
## Reset the prop to neutral white (SPEC.md 9.3: Alles-Löschen).
signal clear_pressed

@onready var _picker: ColorPicker = $Panel/Margin/Rows/Picker
@onready var _grundieren_button: Button = $Panel/Margin/Rows/Actions/GrundierenButton
@onready var _clear_button: Button = $Panel/Margin/Rows/Actions/ClearButton

func _ready() -> void:
	_picker.edit_alpha = false  # strokes are opaque paint
	_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_picker.sampler_visible = false
	_picker.color_changed.connect(_on_picker_color_changed)
	_grundieren_button.pressed.connect(_on_grundieren_button)
	_clear_button.pressed.connect(_on_clear_button)

## Push an externally sampled color (3D eyedropper) into the UI. Godot only
## emits picker.color_changed for user interaction, so this cannot loop.
func set_color(color: Color) -> void:
	_picker.color = color

func color() -> Color:
	return _picker.color

func _on_picker_color_changed(color: Color) -> void:
	color_changed.emit(color)

func _on_grundieren_button() -> void:
	grundieren_pressed.emit()

func _on_clear_button() -> void:
	clear_pressed.emit()
