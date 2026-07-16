extends Control
## Round HUD (Phase 5, feature/round-phases): phase title, countdown, own
## role, and the host's Start-Round button. Grows with later Phase 5/6
## branches (eaten count, rotation timer, cooldown, end screen).
##
## Resolves the round state via the ancestor-walk locator (never the autoload
## identifier) and POLLS in _process — the HUD is pure presentation, all truth
## lives in GameState. Hidden entirely when no round state exists.

const RoundLocator := preload("res://scripts/round/round_locator.gd")
const PlayerForms := preload("res://scripts/player_forms.gd")
const Progression := preload("res://scripts/round/progression.gd")

const NOTICE_SECONDS := 2.5

@onready var _phase_label: Label = $Panel/VBox/PhaseLabel
@onready var _timer_label: Label = $Panel/VBox/TimerLabel
@onready var _role_label: Label = $Panel/VBox/RoleLabel
@onready var _eaten_label: Label = $Panel/VBox/EatenLabel
@onready var _forms_label: Label = $Panel/VBox/FormsLabel
@onready var _clones_label: Label = $Panel/VBox/ClonesLabel
@onready var _rotation_label: Label = $Panel/VBox/RotationLabel
@onready var _start_button: Button = $Panel/VBox/StartButton
@onready var _prompt_label: Label = $Prompt/PromptLabel
@onready var _prompt_progress: ProgressBar = $Prompt/PromptProgress
@onready var _notice_label: Label = $NoticeLabel
@onready var _ghost_banner: Label = $GhostBanner
@onready var _crosshair: Label = $Crosshair
@onready var _cooldown_label: Label = $CooldownLabel
@onready var _chat_box: VBoxContainer = $DeadChatBox
@onready var _chat_log: Label = $DeadChatBox/ChatLog
@onready var _chat_input: LineEdit = $DeadChatBox/ChatInput

var _dead_chat: Node = null
var _chat_lines: Array = []
@onready var _end_panel: PanelContainer = $EndPanel
@onready var _result_label: Label = $EndPanel/VBox/ResultLabel
@onready var _outcome_label: Label = $EndPanel/VBox/OutcomeLabel

var _game_state: Node = null
var _clone_manager: Node = null
var _notice_left := 0.0
var _cooldown_left := 0.0

func _ready() -> void:
	add_to_group("round_hud")  # capsules push interaction prompts here
	_game_state = RoundLocator.locate(self)
	_dead_chat = RoundLocator.locate_named(self, ^"DeadChat")
	_clone_manager = RoundLocator.locate_named(self, ^"CloneManager")
	_start_button.pressed.connect(_on_start_pressed)
	_chat_input.text_submitted.connect(_on_chat_submitted)
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

## Short self-clearing center notice ("form locked", later: eliminations…).
func flash_notice(text: String) -> void:
	_notice_label.text = text
	_notice_label.visible = true
	_notice_left = NOTICE_SECONDS

## Pushed by the local RotationTracker every tick while the timer runs.
func set_rotation_status(text: String, warn: bool) -> void:
	_rotation_label.text = text
	_rotation_label.visible = text != ""
	_rotation_label.modulate = Color(1.0, 0.35, 0.3) if warn else Color.WHITE

## Pushed by SeekerCombat after a miss: reload feedback for the shooter.
func set_cooldown(seconds: float) -> void:
	_cooldown_left = seconds

## Pushed by DeadChat on delivery (dead peers only ever receive these).
func add_dead_chat_line(from_id: int, text: String) -> void:
	_chat_lines.append("[%d] %s" % [from_id, text])
	while _chat_lines.size() > 6:
		_chat_lines.pop_front()
	_chat_log.text = "\n".join(_chat_lines)

func _on_chat_submitted(text: String) -> void:
	_chat_input.clear()
	if _dead_chat != null:
		_dead_chat.send(text)

func _process(_delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left -= _delta
		if _notice_left <= 0.0:
			_notice_label.visible = false
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - _delta, 0.0)
		_cooldown_label.text = "Nachladen… %.1f s" % _cooldown_left
	_cooldown_label.visible = _cooldown_left > 0.0
	_phase_label.text = _game_state.phase_title()
	if _game_state.current_phase == _game_state.Phase.LOBBY:
		_timer_label.text = "—"
	else:
		var t := ceili(_game_state.time_left())
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]
	_role_label.text = _role_text()
	_eaten_label.text = _eaten_text()
	_forms_label.text = _forms_text()
	_clones_label.text = _clones_text()
	_start_button.visible = _game_state.can_start_round()
	_update_ghost_banner()
	_update_end_panel()
	_update_crosshair()

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

func _me() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1

## "Du bist raus" while dead mid-round; the dead chat shows whenever this
## machine's player is dead in a running round or on the END screen.
func _update_ghost_banner() -> void:
	var me := _me()
	var dead: bool = _game_state.players.has(me) and not _game_state.is_alive(me)
	_ghost_banner.visible = _game_state.current_phase != _game_state.Phase.LOBBY \
			and _game_state.current_phase != _game_state.Phase.END and dead
	_chat_box.visible = _game_state.current_phase != _game_state.Phase.LOBBY and dead
	if not _chat_box.visible and not _chat_lines.is_empty():
		_chat_lines.clear()
		_chat_log.text = ""

## Crosshair for the armed seeker (SPEC.md 11 — aim down the camera center).
func _update_crosshair() -> void:
	var me := _me()
	_crosshair.visible = _game_state.current_phase == _game_state.Phase.HUNT \
			and _game_state.is_seeker(me) and _game_state.is_alive(me)

## END screen (SPEC.md 5.3): winner side + the personal outcome. No score.
func _update_end_panel() -> void:
	var show: bool = _game_state.current_phase == _game_state.Phase.END \
			and not _game_state.end_result.is_empty()
	_end_panel.visible = show
	if not show:
		return
	var winner: String = _game_state.end_result.get("winner", "")
	var survivors: Array = _game_state.end_result.get("survivors", [])
	if winner == "seekers":
		_result_label.text = "Die Sucher gewinnen!"
	else:
		_result_label.text = "%d Verstecker überleben!" % survivors.size()
	var me := _me()
	if survivors.has(me):
		_outcome_label.text = "Du überlebst — gewonnen!"
	elif _game_state.role_of(me) == _game_state.Role.SEEKER:
		_outcome_label.text = "Gute Jagd!" if winner == "seekers" else "Alle entwischt…"
	elif _game_state.players.has(me) and not _game_state.is_alive(me):
		_outcome_label.text = "Du wurdest erwischt."
	else:
		_outcome_label.text = ""

## "Klone: n/m [C]" for hiders with a budget (SPEC.md 10 via the eat table).
func _clones_text() -> String:
	if _clone_manager == null:
		return ""
	var me := _me()
	if not _game_state.is_round_active() \
			or _game_state.role_of(me) != _game_state.Role.HIDER:
		return ""
	var budget: int = Progression.clones_allowed(_game_state.eaten_of(me))
	if budget == 0:
		return ""
	return "Klone: %d/%d [C]" % [_clone_manager.clones_of(me).size(), budget]

## Unlock overview from the SPEC.md 8 table, e.g. "Groß ✓ · Mittel ✗(1) · Klein ✗(2)".
func _forms_text() -> String:
	var me := multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if not _game_state.is_round_active() \
			or _game_state.role_of(me) != _game_state.Role.HIDER:
		return ""
	var eaten: int = _game_state.eaten_of(me)
	var parts: Array = []
	var table := [["Groß", PlayerForms.Size.LARGE, 0], ["Mittel", PlayerForms.Size.MEDIUM, 1],
			["Klein", PlayerForms.Size.SMALL, 2]]
	for entry in table:
		if Progression.is_size_unlocked(eaten, entry[1]):
			parts.append("%s ✓" % entry[0])
		else:
			parts.append("%s ✗(%d)" % [entry[0], entry[2]])
	return " · ".join(parts)
