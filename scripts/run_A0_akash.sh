#!/bin/bash

. "/ins/setup_venv.sh" "$@"
. "/ins/copy_A0.sh" "$@"


python /a0/prepare.py --dockerized=true

echo "Starting A0 (Akash-patched, listening on port 5000)..."
# AKASH FIX: Listen on 5000 instead of 80 — nginx handles port 80
exec python /a0/run_ui.py \
    --dockerized=true \
    --port=5000 \
    --host="127.0.0.1"
