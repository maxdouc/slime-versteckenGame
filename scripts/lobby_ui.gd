extends Control
## Minimal ENet test lobby UI (build step 1A / SPEC.md 15).
##
## Wires Host/Join buttons straight to the Net autoload's high-level API.
## The room code shown here is a LOCAL TEST PLACEHOLDER: Net does not yet
## resolve a code to an address (that arrives with the WebRTC signaling
## layer), so joining still requires typing the host's IP.

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready() -> void:
	ip_input.text = "127.0.0.1"
	room_code_label.text = ""
	status_label.text = ""

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	Net.lobby_created.connect(_on_lobby_created)
	Net.lobby_joined.connect(_on_lobby_joined)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connection_failed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	status_label.text = "Hosting..."
	var code := Net.host_game()
	if code == "":
		status_label.text = "Failed to host."

func _on_join_pressed() -> void:
	status_label.text = "Connecting to %s..." % ip_input.text
	Net.join_game(ip_input.text)

func _on_lobby_created(code: String) -> void:
	room_code_label.text = "Room code (local test placeholder): %s" % code
	status_label.text = "Hosting on port %d." % Net.DEFAULT_PORT

func _on_lobby_joined(_code: String) -> void:
	status_label.text = "Connected to host."

func _on_peer_connected(id: int) -> void:
	status_label.text = "Peer connected: %d" % id

func _on_peer_disconnected(id: int) -> void:
	status_label.text = "Peer disconnected: %d" % id

func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: %s" % reason
