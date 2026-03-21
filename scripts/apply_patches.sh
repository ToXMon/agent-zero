#!/bin/bash
set -e

# Apply Agent Zero patches for Akash deployment reliability
# This script modifies the Agent Zero source in-place inside the container

A0_DIR="${1:-/a0}"

echo "=== Applying Agent Zero Akash reliability patches ==="

# ─── Fix 1: Socket.IO ping/pong tuning ───────────────────────────────────────
echo "[1/5] Patching Socket.IO ping/pong for Akash proxy compatibility..."
sed -i \
  's/ping_interval=25,.*$/ping_interval=15,   # Akash fix: keep connection alive through proxy/' \
  "$A0_DIR/run_ui.py"
sed -i \
  's/ping_timeout=20,.*$/ping_timeout=120,   # Akash fix: tolerate event loop delays during heavy tasks/' \
  "$A0_DIR/run_ui.py"

# Add uvicorn ws_ping parameters if not already present
if ! grep -q "ws_ping_interval" "$A0_DIR/run_ui.py"; then
  sed -i \
    's/ws="wsproto",/ws="wsproto",\n        ws_ping_interval=20,\n        ws_ping_timeout=120,/' \
    "$A0_DIR/run_ui.py"
fi

# ─── Fix 2: Code execution timeouts ──────────────────────────────────────────
echo "[2/5] Increasing code execution timeouts..."
sed -i \
  's/"first_output_timeout": 30,/"first_output_timeout": 120,   # Akash fix: npm\/pip can take >30s/' \
  "$A0_DIR/python/tools/code_execution_tool.py"
sed -i \
  's/"between_output_timeout": 15,/"between_output_timeout": 60,  # Akash fix: large installs pause between chunks/' \
  "$A0_DIR/python/tools/code_execution_tool.py"
# Only replace the first occurrence of max_exec_timeout: 180 (CODE_EXEC_TIMEOUTS)
sed -i \
  '0,/"max_exec_timeout": 180,/{s/"max_exec_timeout": 180,/"max_exec_timeout": 600,   # Akash fix: 10min for full installs/}' \
  "$A0_DIR/python/tools/code_execution_tool.py"
# Increase OUTPUT_TIMEOUTS too
sed -i \
  's/"first_output_timeout": 90,/"first_output_timeout": 180,/' \
  "$A0_DIR/python/tools/code_execution_tool.py"
sed -i \
  's/"between_output_timeout": 45,/"between_output_timeout": 120,/' \
  "$A0_DIR/python/tools/code_execution_tool.py"
sed -i \
  's/"max_exec_timeout": 300,/"max_exec_timeout": 900,   # Akash fix: 15min for long output/' \
  "$A0_DIR/python/tools/code_execution_tool.py"

# ─── Fix 3: SSH keepalive and async fixes ─────────────────────────────────────
echo "[3/5] Patching SSH session for better keepalive and async behavior..."
# Reduce keepalive interval from 5s to 3s
sed -i \
  's/keepalive_interval: int = 5/keepalive_interval: int = 3/' \
  "$A0_DIR/python/helpers/shell_ssh.py"
# Fix blocking time.sleep in connect loop → asyncio.sleep
sed -i \
  's/                    time.sleep(0.1)/                    await asyncio.sleep(0.1)  # Akash fix: non-blocking/' \
  "$A0_DIR/python/helpers/shell_ssh.py"
# Increase SSH window size for bursty output
if ! grep -q "default_window_size" "$A0_DIR/python/helpers/shell_ssh.py"; then
  sed -i \
    '/transport.set_keepalive(keepalive_interval)/a\                    transport.default_window_size = 2 * 1024 * 1024  # Akash fix: 2MB window for bursty output' \
    "$A0_DIR/python/helpers/shell_ssh.py"
fi

# ─── Fix 4: SearXNG timeout ──────────────────────────────────────────────────
echo "[4/5] Adding SearXNG request timeout..."
cat > "$A0_DIR/python/helpers/searxng.py" << 'SEARXNG_EOF'
import asyncio
import aiohttp
from python.helpers import runtime

URL = "http://localhost:55510/search"
# Akash fix: explicit timeout prevents indefinite hangs that block the event loop
SEARCH_TIMEOUT = aiohttp.ClientTimeout(total=45, connect=10)

async def search(query: str):
    return await runtime.call_development_function(_search, query=query)

async def _search(query: str):
    try:
        async with aiohttp.ClientSession(timeout=SEARCH_TIMEOUT) as session:
            async with session.post(URL, data={"q": query, "format": "json"}) as response:
                return await response.json()
    except asyncio.TimeoutError:
        return {"results": [], "error": "Search timed out after 45s — SearXNG may be overloaded"}
    except aiohttp.ClientError as e:
        return {"results": [], "error": f"Search connection error: {str(e)}"}
SEARXNG_EOF

# ─── Fix 5: WebSocket client reconnection resilience ─────────────────────────
echo "[5/5] Enhancing WebSocket client reconnection behavior..."
# The client-side already has reconnection:true and retry logic.
# Ensure the transports prefer websocket (skip polling which adds latency on Akash)
sed -i \
  's/transports: \["websocket", "polling"\],/transports: ["websocket"],  \/\/ Akash fix: skip polling, direct WS only/' \
  "$A0_DIR/webui/js/websocket.js"

echo "=== All patches applied successfully ==="
