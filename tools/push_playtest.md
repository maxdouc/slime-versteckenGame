# Playtest upload — itch.io via butler (Phase 8)

Target (from LOCAL_OPERATOR.md): `ttravis17/slime-verstecken-playtest:web-playtest`
Policy: **hidden/private test uploads only.** Never make the page or build
public without Travis. Never expose or commit credentials.

## Binding order

1. **Fresh export** (see `tools/README.md`):

   ```
   <godot-console-exe> --headless --path . --export-release "Web" export/web/index.html
   ```

2. **Visibility pre-check** — the page must NOT be publicly reachable.
   An anonymous (logged-out) request to
   https://ttravis17.itch.io/slime-verstecken-playtest must return 404
   (draft pages 404 for strangers). If it renders publicly: **abort** and
   talk to Travis — pushing would publish content.

   Note: `butler push` has no visibility flag (verified against
   `push --help`); hiddenness is carried entirely by the page's draft
   state, which only the itch.io web dashboard changes.

3. **Push**, versioned `<yyyymmdd>-<short-sha>`:

   ```
   C:\Tools\butler\butler.exe push export/web ttravis17/slime-verstecken-playtest:web-playtest --userversion <yyyymmdd>-<sha>
   ```

4. **Verify**: `butler status ttravis17/slime-verstecken-playtest:web-playtest`
   shows the new build processing/processed.

5. **Browser check** on the (draft) page while logged in as ttravis17:
   the build boots inside the itch iframe, console clean. The page-level
   embed options (viewport ~1280×720, "SharedArrayBuffer support",
   fullscreen button) live in the itch dashboard — butler cannot set them.

## Attempt log

- 2026-07-15, build `20260715-cf76dba`: steps 1–2 passed (export exit 0;
  anonymous check = 404, page hidden). Step 3 REFUSED by itch.io:
  `API error (400): Please verify your account's email address before
  uploading a build`. → Travis: click the verification link in the
  itch.io account email, then rerun steps 1–4. Everything up to the API
  gate is proven working (butler auth OK — the same credentials list the
  project fine).
