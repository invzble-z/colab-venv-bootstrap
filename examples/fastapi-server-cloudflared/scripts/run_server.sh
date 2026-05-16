#!/usr/bin/env bash
# ============================================================
# run_server.sh — Start FastAPI server via uvicorn
# ============================================================
# Env vars (đã export bởi config.env source):
#   VENV_DIR, REPO_DIR, DRIVE_ROOT, PROJECT_SLUG
#
# Override:
#   HOST=0.0.0.0, PORT=8000
#   SERVER_DIR=$REPO_DIR/server  (folder chứa main.py)
#   SERVER_APP=main:app
# ============================================================

set -euo pipefail

# Load config.env nếu chưa có (vd chạy standalone từ shell)
if [ -z "${PROJECT_SLUG:-}" ]; then
    SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"
    # scripts/run_server.sh → colab/scripts → colab → config.env at parent
    CONFIG_FILE="$( cd "$SCRIPT_DIR/.." && pwd )/config.env"
    if [ -f "$CONFIG_FILE" ]; then
        set -a
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        set +a
    fi
fi

: "${PROJECT_SLUG:?PROJECT_SLUG must be set (run via bootstrap or source config.env)}"

BASE_ROOT="${BASE_ROOT:-/content/drive/MyDrive}"
REPO_DIR="${REPO_DIR:-$BASE_ROOT/$PROJECT_SLUG}"
DRIVE_ROOT="${DRIVE_ROOT:-$BASE_ROOT/${PROJECT_SLUG}_colab}"
VENV_DIR="${VENV_DIR:-/content/venvs/$PROJECT_SLUG}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
SERVER_DIR="${SERVER_DIR:-$REPO_DIR/server}"
SERVER_APP="${SERVER_APP:-main:app}"

LOG_DIR="${LOG_DIR:-$DRIVE_ROOT/logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/server.log}"
RUNTIME_DIR="${RUNTIME_DIR:-$DRIVE_ROOT/runtime}"
SERVER_PID_FILE="${SERVER_PID_FILE:-$RUNTIME_DIR/server.pid}"
LOG_TAIL_LINES="${LOG_TAIL_LINES:-120}"

mkdir -p "$LOG_DIR" "$RUNTIME_DIR" "$DRIVE_ROOT/cache/hf" "$DRIVE_ROOT/cache/xdg"

if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "[ERROR] Missing venv python at $VENV_DIR/bin/python"
    echo "        Run bootstrap_env.sh first."
    exit 1
fi

if [ ! -d "$SERVER_DIR" ]; then
    echo "[ERROR] Server dir not found: $SERVER_DIR"
    exit 1
fi

export HF_HOME="${HF_HOME:-$DRIVE_ROOT/cache/hf}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$DRIVE_ROOT/cache/hf/transformers}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$DRIVE_ROOT/cache/xdg}"
export PYTHONUNBUFFERED=1

cd "$SERVER_DIR"

# Stop previous instance if running
if [ -f "$SERVER_PID_FILE" ]; then
    OLD_PID="$(cat "$SERVER_PID_FILE" 2>/dev/null || true)"
    if [ -n "${OLD_PID}" ] && ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "[INFO] Stopping previous server pid=$OLD_PID"
        kill "$OLD_PID" || true
        sleep 2
    fi
fi

echo "[INFO] CUDA quick check"
"$VENV_DIR/bin/python" - <<'PY' || true
import torch
print("torch:", torch.__version__)
print("cuda_available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
PY

echo "[INFO] Starting uvicorn $SERVER_APP on ${HOST}:${PORT}"
nohup "$VENV_DIR/bin/python" -m uvicorn "$SERVER_APP" \
    --host "$HOST" --port "$PORT" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

echo "$SERVER_PID" > "$SERVER_PID_FILE"

sleep 3
if ps -p "$SERVER_PID" > /dev/null 2>&1; then
    echo "[DONE] Server running with pid=$SERVER_PID"
    echo "       Log file: $LOG_FILE"
    tail -n "$LOG_TAIL_LINES" "$LOG_FILE" || true
else
    echo "[ERROR] Server exited early. Last log lines:"
    tail -n "$LOG_TAIL_LINES" "$LOG_FILE" || true
    exit 1
fi
