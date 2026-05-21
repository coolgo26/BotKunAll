"""
Pixel Worlds Traffic Interceptor
Capture semua request ke SocialFirst & PlayFab dari game client asli.

Cara pakai:
1. pip install mitmproxy
2. python intercept_pw.py
3. Set system proxy ke 127.0.0.1:8888
4. Install CA cert: http://mitm.it (buka di browser setelah proxy aktif)
5. Jalankan Pixel Worlds (Steam/PC)
6. Login di game
7. Lihat output — semua request ke SocialFirst/PlayFab akan di-capture

Output disimpan ke: captured_traffic.json
"""

import json
import os
from datetime import datetime
from mitmproxy import http, ctx

CAPTURE_FILE = "captured_traffic.json"
TARGETS = ["sclfrst.com", "playfabapi.com", "pixelworlds"]

captured = []


def response(flow: http.HTTPFlow):
    """Intercept response — capture request + response untuk target domains."""
    url = flow.request.pretty_url
    host = flow.request.host

    # Filter hanya domain yang relevan
    if not any(t in host for t in TARGETS):
        return

    # Build capture entry
    entry = {
        "timestamp": datetime.now().isoformat(),
        "method": flow.request.method,
        "url": url,
        "host": host,
        "path": flow.request.path,
        # Request
        "request_headers": dict(flow.request.headers),
        "request_body": None,
        # Response
        "response_status": flow.response.status_code if flow.response else None,
        "response_headers": dict(flow.response.headers) if flow.response else {},
        "response_body": None,
    }

    # Request body
    if flow.request.content:
        try:
            entry["request_body"] = json.loads(flow.request.content)
        except (json.JSONDecodeError, UnicodeDecodeError):
            entry["request_body"] = flow.request.content.decode("utf-8", errors="replace")[:500]

    # Response body
    if flow.response and flow.response.content:
        try:
            entry["response_body"] = json.loads(flow.response.content)
        except (json.JSONDecodeError, UnicodeDecodeError):
            entry["response_body"] = flow.response.content.decode("utf-8", errors="replace")[:1000]

    captured.append(entry)

    # Print to console
    status = flow.response.status_code if flow.response else "?"
    ctx.log.info(f"{'='*60}")
    ctx.log.info(f"[{entry['timestamp']}] {flow.request.method} {url}")
    ctx.log.info(f"  Status: {status}")
    ctx.log.info(f"  Request Headers:")
    for k, v in flow.request.headers.items():
        ctx.log.info(f"    {k}: {v}")
    if entry["request_body"]:
        ctx.log.info(f"  Request Body: {json.dumps(entry['request_body'], indent=2)[:300]}")
    if entry["response_body"]:
        ctx.log.info(f"  Response Body: {json.dumps(entry['response_body'], indent=2)[:500]}")
    ctx.log.info(f"{'='*60}")

    # Save to file
    save_captured()


def save_captured():
    """Save all captured traffic to JSON file."""
    try:
        with open(CAPTURE_FILE, "w", encoding="utf-8") as f:
            json.dump(captured, f, indent=2, ensure_ascii=False)
    except Exception as e:
        ctx.log.error(f"Save error: {e}")


def done():
    """Called when mitmproxy shuts down."""
    save_captured()
    ctx.log.info(f"\n{'='*60}")
    ctx.log.info(f"Captured {len(captured)} requests. Saved to {CAPTURE_FILE}")
    ctx.log.info(f"{'='*60}")
