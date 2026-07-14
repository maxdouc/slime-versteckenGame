extends Control
## Round HUD (Phase 5, feature/round-phases): phase title, countdown, own
## role, and the host's Start-Round button. Grows with later Phase 5/6
## branches (eaten count, rotation timer, cooldown, end screen).
##
## Resolves the round state via the ancestor-walk locator (never the autoload
## identifier) and POLLS in _process — the HUD is pure presentation, all truth
## lives in GameState. Hidden entirely when no round state exists.

const RoundLocator := preload("res://scripts/round/round_locator.gd")

@onready var _phase_label: Label = $Panel/VBox/PhaseLabel
@onready var _timer_label: Label = $Panel/VBox/TimerLabel
@onready var _role_label: Label = $Panel/VBox/RoleLabel
@onready var _eaten_label: Label = $Panel/VBox/EatenLabel
@onready var _start_button: Button = $Panel/VBox/StartButton
@onready var _prompt_label: Label = $Prompt/PromptLabel
@onready var _prompt_progress: ProgressBar = $Prompt/PromptProgress

var _game_state: Node = null

func _ready() -> void:
	add_to_group("round_hud")  # capsules push interaction prompts here
	_game_state = RoundLocator.locate(self)
	_start_button.pressed.connect(_on_start_pressed)
	set_eat_prompt("", 0.0)
	if _game_state == null:
		visible = false
		set_process(false)

## Pushed by the locally-controlled capsule (group call): interaction prompt +
## hold progress at the bottom center. Empty text hides the block.
func set_eat_prompt(text: String, progress: float) -> void:
	_prompt_label.text = text
	_prompt_label.get_parent().visible = text != ""
	_prompt_progress.value = clampf(progress, 0.0, 1.0) * 100.0

func _process(_delta: float) -> void:
	_phase_label.text = _game_state.phase_title()
	if _game_state.current_phase == _game_state.Phase.LOBBY:
		_timer_label.text = "—"
	else:
		var t := ceili(_game_state.time_left())
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	_role_label.text = _role_text()
	_eaten_label.text = _eaten_text()
	_start_button.visible = _game_state.can_start_round()

func _on_start_pressed() -> void:
	_game_state.start_round()

func _role_text() -> String:
	var role: int = _game_state.role_of(multiplayer.get_unique_id() \
			if multiplayer.multiplayer_peer != null else 1)
	if role == _game_state.Role.SEEKER:
		return "Sucher"
	if role == _game_state.Role.HIDER:
		return "Verstecker"
	if _game_state.is_round_active():
		return "Zuschauer — nächste Runde spielst du mit"
	return ""

func _eaten_text() -> String:
	var me := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if _game_state.role_of(me) != _game_state.Role.HIDER:
		return ""
	return "Gefressen: %d" % _game_state.eaten_of(me)
