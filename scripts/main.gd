extends Node3D
## Placeholder boot scene. The real main menu / lobby UI arrives in build step 1
## (SPEC.md 15): room-code create/join. For now this proves the project boots and
## the autoloads are wired.

func _ready() -> void:
	print("[Slime-Verstecken] Boot OK — Godot ", Engine.get_version_info()["string"])
	print("[Net] autoload ready, max players = ", Net.MAX_PLAYERS)
	print("[GameState] starting phase = ", GameState.phase_name())
