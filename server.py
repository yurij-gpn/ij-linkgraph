#!/usr/bin/env python3
"""
Static file server + Ahrefs API proxy.

Usage:
    python3 server.py [port]

Serves files from the current directory on http://localhost:8080 (default).
Requests to /api/ahrefs/* are proxied to https://api.ahrefs.com/v3/*
with the Bearer token injected automatically.
"""
import http.server
import urllib.request
import urllib.error
import urllib.parse
import json
import sys
import os

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
AHREFS_TOKEN = "REDACTED"
AHREFS_BASE = "https://api.ahrefs.com/v3"
PROXY_PREFIX = "/api/ahrefs/"


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy("GET")
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy("POST")
        else:
            self.send_error(405)

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors_headers()
        self.end_headers()

    def _cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def _proxy(self, method):
        # Strip /api/ahrefs prefix and rebuild the Ahrefs URL
        rest = self.path[len(PROXY_PREFIX):]  # e.g. "site-explorer/metrics?target=..."
        target_url = f"{AHREFS_BASE}/{rest}"

        body = None
        if method == "POST":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else None

        req = urllib.request.Request(
            target_url,
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {AHREFS_TOKEN}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self._cors_headers()
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self._cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_response(502)
            self._cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, fmt, *args):
        # Suppress noisy static-file logs, keep proxy logs
        if self.path.startswith(PROXY_PREFIX):
            print(f"[proxy] {fmt % args}")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    with http.server.ThreadingHTTPServer(("", PORT), Handler) as httpd:
        print(f"Serving on http://localhost:{PORT}")
        print(f"Ahrefs proxy: http://localhost:{PORT}/api/ahrefs/...")
        httpd.serve_forever()
