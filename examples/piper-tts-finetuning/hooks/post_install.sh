#!/usr/bin/env bash
# ============================================================
# post_install.sh — Piper-train specific steps
# ============================================================
# 1. Clone rhasspy/piper vào DRIVE_ROOT/external/piper
# 2. Install piper-train (editable, --no-deps để bypass piper-phonemize dep cứng)
# 3. Build monotonic_align Cython extension
# ============================================================

set -euo pipefail

VENV_PY="$VENV_DIR/bin/python"
PIPER_REPO_DIR="$DRIVE_ROOT/external/piper"

# ------------------------------------------------------------
# Clone piper repo nếu chưa có
# ------------------------------------------------------------
if [ ! -d "$PIPER_REPO_DIR/.git" ]; then
    echo "[HOOK] Cloning rhasspy/piper into $PIPER_REPO_DIR"
    rm -rf "$PIPER_REPO_DIR"
    git clone --depth 1 https://github.com/rhasspy/piper.git "$PIPER_REPO_DIR"
fi

# ------------------------------------------------------------
# Install piper-train editable
# ------------------------------------------------------------
# --no-deps để bypass piper-phonemize dep cứng (đã được cài qua requirements.txt
# với env marker sys_platform != 'win32').
echo "[HOOK] Installing piper-train editable from $PIPER_REPO_DIR/src/python"
"$VENV_PY" -m pip install --no-deps --cache-dir "$PIP_CACHE_DIR" \
    -e "$PIPER_REPO_DIR/src/python"

# ------------------------------------------------------------
# Build monotonic_align Cython extension
# ------------------------------------------------------------
# Subshell phải có venv/bin trong PATH để build_monotonic_align.sh tìm thấy
# `cythonize` binary (từ cython package vừa cài trong venv).
echo "[HOOK] Building monotonic_align Cython extension"
(
    export PATH="$VENV_DIR/bin:$PATH"
    cd "$PIPER_REPO_DIR/src/python"
    chmod +x build_monotonic_align.sh || true
    bash build_monotonic_align.sh
) || echo "[WARN] monotonic_align build had warnings (may still work)"

echo "[HOOK] piper post_install done"
