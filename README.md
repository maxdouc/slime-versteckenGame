# Slime-Verstecken (Arbeitstitel)

Multiplayer prop-hunt + painting. **Web-first (HTML5). Steam = V2.**
Team: Maxim + Partner (2 devs, no artist). Engine: Godot 4.7.

`SPEC.md` is the single source of truth for gameplay. If code and spec disagree,
the spec wins. This README covers setup and process only.

---

## Setup (each dev, once)

1. Install **Godot 4.7** (standard, not .NET) — https://godotengine.org
2. Clone this repo.
3. Open `project.godot` in Godot. First open triggers an asset import — normal.
4. Editor > Manage Export Templates > Download (needed for the Web export).
5. Press F5. The boot scene prints confirmation to the Output panel.

The Godot binary itself is **not** committed (see `.gitignore`). The
`webrtc_native` GDExtension (Windows x86_64) **is** committed and pinned —
see `addons/webrtc_native/VERSION.md`; nothing extra to install.

---

## Architecture: the one rule that must not break

All gameplay talks to Godot's **high-level multiplayer API** (`@rpc`,
`MultiplayerSynchronizer`). It never touches the transport directly. The
transport lives behind the `Net` autoload: the seam block in `net/net.gd` plus
its helper `net/webrtc_signaling.gd`:

| Stage | Peer | Notes |
|---|---|---|
| **Primary (since 1D)** | `WebRTCMultiplayerPeer` | mesh + WebSocket signaling server in `/server`; real room codes. Desktop/editor needs the pinned `addons/webrtc_native` GDExtension (committed); browsers use built-in WebRTC |
| Developer fallback | `ENetMultiplayerPeer` | explicit dropdown choice in the lobby, direct IP. **No automatic fallback** — WebRTC failures show an error instead |
| Steam (V2) | `SteamMultiplayerPeer` | via GodotSteam addon |

Swapping transports = editing the seam in `/net`. Nothing else changes. Keep it
that way. Running/testing the signaling server: see `server/README.md`.

---

## Web specifics (read before build step 1)

- **Hosting:** the Web build uses threads, which need `Cross-Origin-Opener-Policy`
  and `Cross-Origin-Embedder-Policy` headers. **itch.io sets these; GitHub Pages
  does not.** Playtest builds go on itch.io.
- **Paint netcode:** brush strokes sync as **events** (`{object_id, uv, color,
  action}`), never whole textures (SPEC.md 9.3). In the browser this is not
  optional — memory and bandwidth are tighter than native.
- **Paint textures:** keep per-prop paint textures small (256² or 512²). Measure
  browser framerate from build step 2 onward, not at the end.
- **No Steam:** no GodotSteam, no Steam matchmaking, no cosmetics shop in V1.
  Lobbies use a 6-char room code (`Net._generate_code()`).

---

## Process rules

- Feature branches only. Merges via Pull Request. **No direct commits to `main`
  — including by AI agents.**
- Every networked feature is tested on **two real machines / two real browsers**,
  never only in the editor. Desyncs live in the network, not the editor.
- "Maybe add later" does not exist. It is either in `SPEC.md` with a build-order
  position, or it is cut.

---

## Build order (SPEC.md 15, web-adapted)

1. **Web MP scaffold** — signaling server (`/server`), WebRTC peer, room-code
   lobby, gray room, synced capsules. *(This scaffold ships ENet as a stand-in so
   step 0 is verifiable; step 1 swaps in WebRTC.)*
2. Slime movement + transform into white props, speed tiers.
3. Paint system — eyedropper, brush, **Grundieren** button, strokes as events.
4. Round loop — prep/hunt timers, feeding, eat table, rotation timer + drip.
5. Seeker kit — paintball gun, splatter, cooldown, spectator.
6. Map 1 graybox, then Kenney dressing.
7. Community playtest (~100). Kenney-vs-Synty decision gate.
8. Clones + swap-teleport. Built last, cut first.

---

## Repo layout

```
/scenes   Godot scenes (.tscn)
/scripts  gameplay GDScript + autoloads (game_state.gd)
/net      transport seam (net.gd autoload)
/server   headless signaling server for WebRTC (build step 1)
/shaders  wobble, splatter, etc.
/maps     level scenes
/assets   props, slime meshes, imported packs
```
