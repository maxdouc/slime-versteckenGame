extends CharacterBody3D
## Networked player capsule (build step 1C: synced capsules in the gray room).
##
## AUTHORITY — PHASE 1 TEST SETUP, NOT THE FINAL GAMEPLAY DECISION:
## each peer owns its capsule (authority = peer ID, taken from the node name
## the host assigns at spawn), simulates it locally, and the
## MultiplayerSynchronizer child broadcasts position/rotation to everyone
## else. This client-authoritative model exists only to prove capsule sync
## over a real network. Revisit authority when real movement lands in
## feature/player-movement-camera (Phase 2).
##
## The movement below is a THROWAWAY TEST HARNESS for the same reason: it
## uses only the built-in ui_* actions (arrow keys) so the input map and
## project.godot stay untouched. Phase 2 replaces it wholesale.

const TEST_MOVE_SPEED: float = 4.0

func _enter_tree() -> void:
	# The host names each capsule after the owning peer's ID (main.gd).
	var peer_id := str(name).to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)

func _ready() -> void:
	# Remote copies are driven by the synchronizer, never by local physics.
	set_physics_process(is_multiplayer_authority())

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# TEMP Phase 1 test movement — arrow keys, fixed speed, no camera.
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity.x = input.x * TEST_MOVE_SPEED
	velocity.z = input.y * TEST_MOVE_SPEED
	move_and_slide()
