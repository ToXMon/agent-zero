#!/bin/bash
# Healthcheck script for Agent Zero on Akash
# Checks if the web UI is responding and if SearXNG is alive

FAILURES=0
MAX_FAILURES=3

check_a0() {
    curl -sf --max-time 5 http://127.0.0.1:5000/health > /dev/null 2>&1
}

check_searxng() {
    curl -sf --max-time 5 http://127.0.0.1:55510/ > /dev/null 2>&1
}

if ! check_a0; then
    echo "Agent Zero health check FAILED"
    exit 1
fi

if ! check_searxng; then
    echo "SearXNG health check FAILED (non-fatal)"
    # Don't fail the whole container for SearXNG — it auto-restarts via supervisord
fi

exit 0
