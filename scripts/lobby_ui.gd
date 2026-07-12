extends Control
## Lobby UI (build steps 1A + 1D).
##
## WebRTC with real room codes is the primary transport; ENet stays selectable
## as an EXPLICIT developer fallback in the dropdown. The two never swap
## silently — every failure lands in the status label instead (branch 1D
## decision). All buttons talk to the Net autoload only.

@onready var transport_option: OptionButton = $VBoxContainer/TransportOption
@onready var address_label: Label = $VBoxContainer/AddressLabel
@onready var address_input: LineEdit = $VBoxContainer/AddressInput
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel
@onready var code_input: LineEdit = $VBoxContainer/CodeInput
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready() -> void:
	transport_option.add_item("WebRTC — room code (default)", Net.Transport.WEBRTC)
	transport_option.add_item("ENet — developer fallback (IP)", Net.Transport.ENET)
	transport_option.item_selected.connect(_on_transport_selected)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	Net.lobby_created.connect(_on_lobby_created)
	Net.lobby_joined.connect(_on_lobby_joined)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connection_failed.connect(_on_connection_failed)

	transport_option.select(transport_option.get_item_index(Net.transport))
	_apply_transport()

func _on_transport_selected(index: int) -> void:
	Net.transport = transport_option.get_item_id(index) as Net.Transport
	_apply_transport()

func _apply_transport() -> void:
	var webrtc := Net.transport == Net.Transport.WEBRTC
	code_input.visible = webrtc
	if webrtc:
		address_label.text = "Signaling server (host: 127.0.0.1, see server/README.md)"
		address_input.placeholder_text = "e.g. 127.0.0.1 or the host's Tailscale IP"
	else:
		address_label.text = "Host IP (ENet developer fallback)"
		address_input.placeholder_text = "e.g. 192.168.1.20"
	room_code_label.text = ""
	status_label.text = ""

func _on_host_pressed() -> void:
	room_code_label.text = ""
	Net.signaling_address = address_input.text
	if Net.transport == Net.Transport.WEBRTC:
		status_label.text = "Creating room via %s..." % address_input.text
	else:
		status_label.text = "Hosting..."
	Net.host_game()

func _on_join_pressed() -> void:
	room_code_label.text = ""
	Net.signaling_address = address_input.text
	if Net.transport == Net.Transport.WEBRTC:
		var code := code_input.text.strip_edges().to_upper()
		status_label.text = "Joining room %s via %s..." % [code, address_input.text]
		Net.join_game(code)
	else:
		status_label.text = "Connecting to %s..." % address_input.text
		Net.join_game(address_input.text)

func _on_lobby_created(code: String) -> void:
	if Net.transport == Net.Transport.WEBRTC:
		room_code_label.text = "Room code: %s — share it with the other players." % code
		status_label.text = "Hosting. Waiting for players..."
	else:
		room_code_label.text = "Room code (ENet placeholder, not joinable): %s" % code
		status_label.text = "Hosting on port %d." % Net.DEFAULT_PORT

func _on_lobby_joined(code: String) -> void:
	if code == "":
		status_label.text = "Connected to host."
	else:
		status_label.text = "Joined room %s — connected to host." % code

func _on_peer_connected(id: int) -> void:
	status_label.text = "Peer connected: %d" % id

func _on_peer_disconnected(id: int) -> void:
	status_label.text = "Peer disconnected: %d" % id

func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: %s" % reason
