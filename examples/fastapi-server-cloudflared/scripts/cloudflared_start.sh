#!/usr/bin/env bash
# ============================================================
# cloudflared_start.sh — Tạo tunnel ephemeral cho server
# ============================================================
# Download cloudflared binary (1 lần, cache trên /content/bin),
# tạo tunnel tới http://127.0.0.1:$PORT, parse URL từ log.
# ============================================================

set -euo pipefail

# Load config.env nếu chưa có
if [ -z "${PROJECT_SLUG:-}" ]; then
    SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"
    CONFIG_FILE="$( cd "$SCRIPT_DIR/.." && pwd )/config.env"
    if [ -f "$CONFIG_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        set +a
    fi
fi

: "${PROJECT_SLUG:?PROJECT_SLUG must be set}"

BASE_ROOT="${BASE_ROOT:-/content/drive/MyDrive}"
DRIVE_ROOT="${DRIVE_ROOT:-$BASE_ROOT/${PROJECT_SLUG}_colab}"

PORT="${PORT:-8000}"
BIN_DIR="${BIN_DIR:-/content/bin}"
LOG_DIR="${LOG_DIR:-$DRIVE_ROOT/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/tunnel.log}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-$BIN_DIR/cloudflared}"
RUNTIME_DIR="${RUNTIME_DIR:-$DRIVE_ROOT/runtime}"

mkdir -p "$BIN_DIR" "$LOG_DIR" "$RUNTIME_DIR"

if [ ! -x "$CLOUDFLARED_BIN" ]; then
    echo "[INFO] Downloading cloudflared binary"
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -O "$CLOUDFLARED_BIN"
    chmod +x "$CLOUDFLARED_BIN"
fi

# Stop previous tunnel
if [ -f "$RUNTIME_DIR/cloudflared.pid" ]; then
    OLD_PID="$(cat "$RUNTIME_DIR/cloudflared.pid" 2>/dev/null || true)"
    if [ -n "${OLD_PID}" ] && ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "[INFO] Stopping previous tunnel pid=$OLD_PID"
        kill "$OLD_PID" || true
        sleep 2
    fi
fi

# Truncate log để parse URL mới (không bị URL cũ trong file)
: > "$LOG_FILE"

echo "[INFO] Starting cloudflared tunnel to http://127.0.0.1:${PORT}"
nohup "$CLOUDFLARED_BIN" tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate \
    > "$LOG_FILE" 2>&1 &
TUNNEL_PID=$!

echo "$TUNNEL_PID" > "$RUNTIME_DIR/cloudflared.pid"

echo "[INFO] Waiting for Cloudflare URL..."
TIMEOUT="${TUNNEL_TIMEOUT:-60}"
COUNT=0
PUBLIC_URL=""

while [ -z "$PUBLIC_URL" ] && [ $COUNT -lt $TIMEOUT ]; do
    PUBLIC_URL=$(grep -Eo 'https://[-0-9a-z]+\.trycloudflare\.com' "$LOG_FILE" | head -n1 || true)
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ -n "$PUBLIC_URL" ]; then
    echo "$PUBLIC_URL" > "$RUNTIME_DIR/last_public_url.txt"
    echo "[DONE] Public URL : $PUBLIC_URL"
    echo "[DONE] WebSocket  : ${PUBLIC_URL/https/wss}/ws"
else
    echo "[ERROR] Cloudflare failed to provide URL after ${TIMEOUT}s"
    tail -n 80 "$LOG_FILE"
    exit 1
fi
