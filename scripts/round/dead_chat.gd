extends Node
## Dead-only text chat (Phase 6, feature/spectator-mode).
##
## No class_name on purpose (repo convention — preload by path).
##
## SPEC.md 5.3: "Eliminierte: … Textchat nur mit anderen Toten. Kein
## Voice-Chat in V1." The HOST relays every line: it verifies the sender is
## actually dead (registry: present + not alive — mid-round joiners count as
## spectators too) while a round or its END screen is showing, then delivers
## ONLY to dead peers. Alive players can neither send nor ever receive a
## packet — the filter runs server-side, not in the UI.

const RoundLocator := preload("res://scripts/round/round_locator.gd")

const MAX_LINE_LENGTH := 200

signal message_received(from_id: int, text: String)

var _game_state: Node = null

func _ready() -> void:
	_game_state = RoundLocator.locate(self)

## Local entry point for the dead player's own machine.
func send(text: String) -> void:
	var line := text.strip_edges().left(MAX_LINE_LENGTH)
	if line.is_empty():
		return
	if RoundLocator.has_real_peer(self) and not multiplayer.is_server():
		_relay.rpc_id(1, line)
	else:
		_relay(line)

## Runs on the HOST: dead-sender gate + dead-only fan-out.
@rpc("any_peer", "reliable")
func _relay(text: String) -> void:
	if _game_state == null or not _game_state.is_round_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id() if RoundLocator.has_real_peer(self) else 1
	if _game_state.current_phase == _game_state.Phase.LOBBY:
		return  # no round, no dead channel
	if not _game_state.players.has(sender) or _game_state.is_alive(sender):
		return  # the living have Discord (SPEC.md 5.3)
	var line := text.strip_edges().left(MAX_LINE_LENGTH)
	if line.is_empty():
		return
	var my_id := multiplayer.get_unique_id() if RoundLocator.has_real_peer(self) else 1
	for id in _game_state.players:
		if _game_state.is_alive(id):
			continue
		if id == my_id:
			_deliver(sender, line)
		elif RoundLocator.has_real_peer(self):
			_deliver.rpc_id(id, sender, line)

## Runs on each DEAD peer's machine.
@rpc("authority", "reliable")
func _deliver(from_id: int, text: String) -> void:
	message_received.emit(from_id, text)
	get_tree().call_group("round_hud", "add_dead_chat_line", from_id, text)
