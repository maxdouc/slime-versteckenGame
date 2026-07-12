extends CharacterBody3D
## Networked player capsule with third-person movement and camera (Phase 2,
## feature/player-movement-camera).
##
## AUTHORITY — unchanged from Phase 1: each peer owns its capsule (authority =
## peer ID, taken from the node name the host assigns at spawn), simulates it
## locally, and the MultiplayerSynchronizer child broadcasts position + facing
## to everyone else. Client-authoritative on purpose for now; revisit if
## cheating ever becomes a concern.
##
## Node contract: the CharacterBody3D root never rotates. $Visual yaw-turns
## toward the movement direction (that rotation is what remote peers see via
## the synchronizer), $CameraPivot carries the mouse-orbited camera rig and
## only exists on the locally controlled capsule.

const WALK_SPEED: float = 5.0
const ACCELERATION: float = 25.0  # m/s² while there is movement input
const DECELERATION: float = 30.0  # m/s² braking toward standstill
const AIR_CONTROL: float = 0.3  # fraction of accel/decel while airborne
const TURN_WEIGHT: float = 12.0  # visual yaw smoothing, higher = snappier

const MOUSE_SENSITIVITY: float = 0.003
const CAMERA_PITCH_START: float = -0.35  # rad; negative looks down at the player
const CAMERA_PITCH_MIN: float = -1.2
const CAMERA_PITCH_MAX: float = 0.35

@onready var _visual: Node3D = $Visual
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

func _enter_tree() -> void:
	# The host