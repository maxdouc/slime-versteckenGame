# /server — WebRTC signaling server (build step 1D)

A tiny headless WebSocket server. It creates rooms, issues the **real 6-char
room codes**, and relays the WebRTC handshake (SDP offers/answers + ICE
candidates) between peers of a room until their direct P2P links are up.
**It never carries game traffic** — after the handshake, gameplay packets flow
peer-to-peer.

No Node.js, no extra installs: it runs on the same Godot 4.7 binary as the
editor.

## Starting the server

From the **repo root** (the folder with `project.godot`):

```
<path-to-godot> --headless --script server/signaling_server.gd
```

Windows example (PowerShell, adjust the path to your Godot download):

```powershell
& "C:\...\Godot_v4.7-stable_win64_console.exe" --headless --script server/signaling_server.gd
```

Default port: **9080**, bound on all interfaces. Custom port:

```
<godot> --headless --script server/signaling_server.gd -- --port=9090
```

Stop it with `Ctrl+C`. Every room/join/relay event is logged with a timestamp.

## Automated smoke test

```
<godot> --headless --script server/smoke_test.gd
```

Spawns a private server on port 9081, hosts a room, joins it by code, and
sends one packet across the resulting P2P links in both directions. Prints
`PASS`/`FAIL`, exit code 0/1. Run it after touching anything in `/net`,
`/server`, or the webrtc addon.

## Protocol (JSON text frames over one WebSocket per client)

Client → server:

| Message | Meaning |
|---|---|
| `{"type":"host"}` | create a room; sender becomes peer 1 |
| `{"type":"join","code":"ABC123"}` | join a room by code |
| `{"type":"offer"/"answer","to":id,"sdp":...}` | relay session description to a room peer |
| `{"type":"candidate","to":id,"media":...,"index":...,"name":...}` | relay ICE candidate |

Server → client:

| Message | Meaning |
|---|---|
| `{"type":"room_created","code":...,"id":1}` | room exists, you are the host |
| `{"type":"room_joined","code":...,"id":...,"peers":[...]}` | you are in; connect to `peers` |
| `{"type":"peer_joined","id":...}` / `{"type":"peer_left","id":...}` | membership changes |
| `{"type":"room_closed"}` | host's signaling connection is gone; no new joins |
| relayed `offer`/`answer`/`candidate` with `"from":id` | counterpart of the relays above |
| `{"type":"error","message":...}` | e.g. unknown room code, room full |

Peer IDs: host is always `1`; joiners get a random positive int32. The peer
with the **higher** ID creates the WebRTC offer of each pair, so the host never
creates offers (same rule as Godot's official `webrtc_signaling` demo).

## Test recipes

### Two instances on one PC

1. Start the server (see above) and leave it running.
2. Start the game twice (editor F5 + exported build, or two editor instances).
3. Instance A: transport **WebRTC**, server address `127.0.0.1`, **Host** →
   a room code appears.
4. Instance B: transport **WebRTC**, server address `127.0.0.1`, type the code,
   **Join**. Both windows should show the synced capsules (arrow keys move).

### Two PCs over Tailscale (Travis ↔ Maxim) — no port forwarding

1. Both install [Tailscale](https://tailscale.com) and join the same tailnet
   (one of you creates it and invites the other).
2. **Host machine:** start the signaling server, then the game → WebRTC →
   server address `127.0.0.1` → **Host**. Read your Tailscale IP with
   `tailscale ip -4` (looks like `100.x.y.z`). Share IP + room code.
3. **Joining machine:** game → WebRTC → server address = the host's
   `100.x.y.z` → enter the code → **Join**.
4. Because both machines sit in the same tailnet, ICE finds a direct route over
   the Tailscale interface — no router configuration needed.

Deliberately **not** in this branch (deferred to the web-export/deployment
phase): public hosting of this server, `wss://` (TLS), and a TURN relay for
NAT pairs that STUN cannot crack.
