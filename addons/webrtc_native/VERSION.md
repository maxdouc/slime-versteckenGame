# webrtc-native GDExtension — pinned version

- **Plugin:** official `godotengine/webrtc-native`
- **Release:** `1.2.1-stable` (published 2026-07-07)
- **Source:** https://github.com/godotengine/webrtc-native/releases/tag/1.2.1-stable
- **Asset:** `godot-extension-webrtc_native.zip`
- **Compatibility:** built for Godot 4.3+ (`compatibility_minimum = 4.3` in
  `webrtc_native.gdextension`) — verified against our Godot 4.7-stable.
- **Dependencies (from release notes):** libdatachannel 0.24.5, mbedTLS 3.6.7.
- **License:** MIT (`LICENSE.webrtc-native`); bundled third-party licenses in the
  other `LICENSE.*` files in this directory.

## What is committed (and why)

Only the **Windows x86_64** binaries are committed (`lib/…windows.template_debug/
release.x86_64.dll`) — that is what both dev machines need for native/editor
testing. The **Web export does not use this extension at all**: browsers ship
WebRTC natively and Godot uses it directly (note that `webrtc_native.gdextension`
lists no `web.*` entry).

## Known quirk (verified on Godot 4.7-stable, Windows)

The **first** editor/import run after this extension gets registered (fresh
clone, wiped `.godot/` cache) finishes all its work correctly but crashes with
an access violation **during process teardown**. Every following editor
session exits cleanly, and the running game is never affected (verified for
1.2.0 and 1.2.1 — behavior is identical). If Godot reports a crash right after
your first project open on this branch: one-time, harmless, ignore it.

## Updating or adding a platform

Download the same (or a newer, team-approved) release asset, extract, and copy
the needed `lib/` binaries next to the existing ones. The `.gdextension` file
already lists the paths for every platform. Update this file when the pinned
release changes.
