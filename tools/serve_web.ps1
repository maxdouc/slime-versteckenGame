# Local COOP/COEP static server for the Web build (Phase 8).
#
# The Web export uses THREADS, so the browser only grants SharedArrayBuffer
# when the page ships with Cross-Origin-Opener-Policy / -Embedder-Policy
# headers (README "Web specifics"). itch.io sets them in production; plain
# static servers (and GitHub Pages) do not — this script does, for local
# smoke tests.
#
# Usage (from the repo root, after exporting to export/web):
#
#     powershell -ExecutionPolicy Bypass -File tools/serve_web.ps1
#
# then open http://localhost:8060 in a browser. Ctrl+C stops the server.

param(
    [int]$Port = 8060,
    [string]$Root = "export/web"
)

$rootPath = (Resolve-Path $Root).Path
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $rootPath at http://localhost:$Port (COOP/COEP on) - Ctrl+C stops"

$contentTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "application/javascript"
    ".wasm" = "application/wasm"
    ".pck"  = "application/octet-stream"
    ".png"  = "image/png"
    ".ico"  = "image/x-icon"
    ".json" = "application/json"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $request = $context.Request
            $response = $context.Response
            $relative = $request.Url.AbsolutePath.TrimStart("/")
            if ($relative -eq "") { $relative = "index.html" }
            $file = Join-Path $rootPath $relative
            # The headers that make SharedArrayBuffer (threads) work:
            $response.Headers.Add("Cross-Origin-Opener-Policy", "same-origin")
            $response.Headers.Add("Cross-Origin-Embedder-Policy", "require-corp")
            $response.Headers.Add("Cache-Control", "no-store")
            if ((Test-Path $file -PathType Leaf) -and $file.StartsWith($rootPath)) {
                $ext = [System.IO.Path]::GetExtension($file).ToLower()
                if ($contentTypes.ContainsKey($ext)) {
                    $response.ContentType = $contentTypes[$ext]
                }
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $response.ContentLength64 = $bytes.Length
                if ($request.HttpMethod -ne "HEAD") {
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            } else {
                $response.StatusCode = 404
            }
            $response.OutputStream.Close()
        } catch {
            # One broken request (aborted download, odd method) must never
            # take the server down mid-playtest.
            try { $context.Response.Abort() } catch {}
        }
    }
} finally {
    $listener.Stop()
}
