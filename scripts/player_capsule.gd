extends CharacterBody3D
## Minimal player capsule placeholder — visuals and collision only.
##
## Movement/camera arrive in feature/player-movement-camera; networked
## spawning and sync arrive in feature/basic-player-sync. This scene is kept
## instance-ready (single root, no external state) so a MultiplayerSpawner
## can spawn it later without changes here.
