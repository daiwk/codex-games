#!/usr/bin/env python3
"""Run the included Web game locally using only the Python standard library."""
import argparse
import errno
import functools
import gzip
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading
import webbrowser

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "sites" / "wenfeng-web" / "dist"


class GameHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".json": "application/json",
        ".wasm": "application/wasm",
        ".gz": "application/gzip",
        ".otf": "font/otf",
    }

    def end_headers(self):
        # Revalidate local edits; .gz files are decoded by the game's loader.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None

    def copyfile(self, source, outputfile):
        try:
            super().copyfile(source, outputfile)
        except (BrokenPipeError, ConnectionResetError):
            # A browser may cancel a large asset download when its tab closes.
            pass


def verify_assets(full=False):
    for name in ("index.html", "index.js", "web-app.js", "web.css", "assets-manifest.json"):
        if not (DIST / name).is_file():
            raise ValueError("Missing game file: " + name + ". Download the complete repository first.")
    manifest = json.loads((DIST / "assets-manifest.json").read_text(encoding="utf-8"))
    for name in ("index.wasm", "index.pck"):
        asset = manifest["assets"][name]
        file = (DIST / asset["file"]).resolve()
        if file.parent != DIST.resolve() or not file.is_file():
            raise ValueError("Missing game asset: " + name)
        if file.stat().st_size != asset["download_bytes"]:
            raise ValueError("Incomplete game asset: " + name + ". Download it again.")
        if full:
            data = gzip.decompress(file.read_bytes())
            if len(data) != asset["decoded_bytes"] or hashlib.sha256(data).hexdigest() != asset["sha256"]:
                raise ValueError("Game asset checksum mismatch: " + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, help="Local port (default: 8000, or a free port if busy; 0 picks a free port)")
    parser.add_argument("--no-browser", action="store_true", help="Print the URL without opening a browser")
    parser.add_argument("--check", action="store_true", help="Verify the included WASM/PCK assets and exit")
    args = parser.parse_args()
    if args.port is not None and not 0 <= args.port <= 65535:
        parser.error("--port must be between 0 and 65535")
    try:
        verify_assets(full=args.check)
        if args.check:
            print("Game assets verified (gzip, decoded sizes and SHA256).")
            return 0
        handler = functools.partial(GameHandler, directory=str(DIST))
        try:
            server = ThreadingHTTPServer(("127.0.0.1", 8000 if args.port is None else args.port), handler)
        except OSError as error:
            busy_codes = (errno.EADDRINUSE, getattr(errno, "WSAEADDRINUSE", errno.EADDRINUSE))
            if args.port is not None or error.errno not in busy_codes:
                raise
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    except (OSError, ValueError, KeyError, EOFError) as error:
        print("Unable to start game: " + str(error), file=sys.stderr)
        return 1

    with server:
        url = "http://127.0.0.1:" + str(server.server_port) + "/"
        print("Wenfeng - Duel of Blades", flush=True)
        print("Open: " + url, flush=True)
        print("Press Ctrl+C to stop the local server.", flush=True)
        if not args.no_browser:
            timer = threading.Timer(0.3, lambda: webbrowser.open(url))
            timer.daemon = True
            timer.start()
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nLocal game server stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
