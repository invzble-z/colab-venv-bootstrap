#!/usr/bin/env bash
# ============================================================
# post_install.sh — FastAPI server specific
# ============================================================
# Swap onnxruntime CPU build → onnxruntime-gpu để có CUDAExecutionProvider
# cho TTS inference (piper-tts) chạy trên GPU.
#
# Cả 2 build cùng expose module name `onnxruntime` nên phải uninstall trước rồi install GPU.
# Chạy sau requirements để không bị resolver pip đè ngược.
# ============================================================

set -euo pipefail

VENV_PY="$VENV_DIR/bin/python"

echo "[HOOK] Swapping onnxruntime → onnxruntime-gpu"
"$VENV_PY" -m pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null || true
"$VENV_PY" -m pip install --cache-dir "$PIP_CACHE_DIR" onnxruntime-gpu

# Verify CUDAExecutionProvider available
VERIFY=$(
    "$VENV_PY" - <<'PY'
try:
    import onnxruntime as ort
    print("1" if "CUDAExecutionProvider" in ort.get_available_providers() else "0")
except Exception as e:
    print(f"err: {e}")
PY
)

if [ "$VERIFY" = "1" ]; then
    echo "[HOOK] onnxruntime-gpu OK (CUDAExecutionProvider available)"
else
    echo "[WARN] onnxruntime-gpu installed but CUDAExecutionProvider missing: $VERIFY"
fi

echo "[HOOK] fastapi post_install done"
