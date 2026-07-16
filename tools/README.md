# Tools — Web build pipeline (Phase 8)

## Export the Web build (CLI, repeatable)

From the repo root, with the Godot 4.7 export templates installed:

```
<godot-console-exe> --headless --path . --export-release "Web" export/web/index.html
```

Uses the committed "Web" preset in `export_presets.cfg`: GL Compatibility,
extensions OFF, **threads ON**, output `export/web/` (gitignored — builds are
never committed).

## Serve it locally

Threads need `SharedArrayBuffer`, which browsers only enable behind
COOP/COEP headers. Plain static servers don't send them; this one does:

```
powershell -ExecutionPolicy Bypass -File tools/serve_web.ps1
```

Then open http://localhost:8060. The Output-panel boot line
(`[Slime-Verstecken] Boot OK`) appears in the browser console when the boot
scene runs.

Note: hosting rules live in README.md ("Web specifics") — itch.io sets the
headers in production, GitHub Pages does not.

## Multiplayer in the browser

Browsers can only use the WebRTC transport (ENet needs UDP). For a local
two-tab test, run the signaling server first (see `server/README.md`), host
in one tab with signaling address `127.0.0.1`, and join with the room code
in the second tab.
