#!/usr/bin/env bash
# ============================================================
# bootstrap_env.sh — Generic venv bootstrap với snapshot cho Colab
# ============================================================
# Đọc config từ <project>/colab/config.env và build venv trên local disk
# (/content/venvs/<slug>). Snapshot venv được lưu Drive cho fast-restore.
#
# Sử dụng:
#   bash <project>/colab/bootstrap/scripts/bootstrap_env.sh
#
# Hooks (optional, đặt tại <project>/colab/hooks/<name>.sh):
#   pre_apt.sh, post_apt.sh, pre_install.sh, post_install.sh, verify_extra.sh
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# Path resolution
# ------------------------------------------------------------
SCRIPT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"
SUBMODULE_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
COLAB_DIR="$( cd "$SUBMODULE_ROOT/.." && pwd )"

CONFIG_FILE="${CONFIG_FILE:-$COLAB_DIR/config.env}"
HOOKS_DIR="${HOOKS_DIR:-$COLAB_DIR/hooks}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    echo "        Create one from $SUBMODULE_ROOT/templates/config.env.example"
    exit 1
fi

# shellcheck source=/dev/null
set -a
source "$CONFIG_FILE"
set +a

# ------------------------------------------------------------
# Required vars + defaults
# ------------------------------------------------------------
: "${PROJECT_SLUG:?PROJECT_SLUG must be set in config.env}"

BASE_ROOT="${BASE_ROOT:-/content/drive/MyDrive}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
APT_PYTHON_PACKAGES="${APT_PYTHON_PACKAGES:-}"
APT_EXTRA_PACKAGES="${APT_EXTRA_PACKAGES:-}"

INSTALL_TORCH="${INSTALL_TORCH:-1}"
TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu121}"
TORCH_INDEX_FLAG="${TORCH_INDEX_FLAG:---extra-index-url}"
TORCH_REQUIREMENTS_FILE="${TORCH_REQUIREMENTS_FILE:-}"

REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-requirements.txt}"

PIP_PRE_INSTALL="${PIP_PRE_INSTALL:-pip setuptools wheel}"
REUSE_CHECK_MODULES="${REUSE_CHECK_MODULES:-torch}"

ENABLE_VENV_SNAPSHOT="${ENABLE_VENV_SNAPSHOT:-1}"
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"

# Derived paths (có thể override trong config.env)
REPO_DIR="${REPO_DIR:-$BASE_ROOT/$PROJECT_SLUG}"
DRIVE_ROOT="${DRIVE_ROOT:-${BASE_ROOT}/${PROJECT_SLUG}_colab}"
VENV_DIR="${VENV_DIR:-/content/venvs/$PROJECT_SLUG}"

PIP_CACHE_DIR="${PIP_CACHE_DIR:-$DRIVE_ROOT/cache/pip}"
HF_CACHE_DIR="${HF_CACHE_DIR:-$DRIVE_ROOT/cache/hf}"

VENV_SNAPSHOT_FILE="${VENV_SNAPSHOT_FILE:-$DRIVE_ROOT/env/venv_snapshot.tar.gz}"
VENV_SNAPSHOT_META="${VENV_SNAPSHOT_META:-$DRIVE_ROOT/env/venv_snapshot.meta.json}"
LOCK_FILE="${LOCK_FILE:-$DRIVE_ROOT/env/requirements.colab.lock.txt}"
FINGERPRINT_FILE="${FINGERPRINT_FILE:-$DRIVE_ROOT/env/fingerprint.json}"

# Export cho hooks + Python subprocesses
export PROJECT_SLUG BASE_ROOT
export REPO_DIR DRIVE_ROOT VENV_DIR
export PIP_CACHE_DIR HF_CACHE_DIR
export COLAB_DIR SUBMODULE_ROOT HOOKS_DIR
export VENV_SNAPSHOT_FILE VENV_SNAPSHOT_META LOCK_FILE FINGERPRINT_FILE
export PYTHON_BIN REUSE_CHECK_MODULES

# HuggingFace cache
export HF_HOME="${HF_HOME:-$HF_CACHE_DIR}"

# ------------------------------------------------------------
# Init directories
# ------------------------------------------------------------
mkdir -p "$DRIVE_ROOT/env" \
         "$DRIVE_ROOT/cache/pip" \
         "$DRIVE_ROOT/cache/hf" \
         "$DRIVE_ROOT/logs" \
         "$DRIVE_ROOT/external"
mkdir -p "$(dirname "$VENV_DIR")"

# ------------------------------------------------------------
# Validate repo
# ------------------------------------------------------------
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "[ERROR] Repo not found at $REPO_DIR"
    echo "        Run 00_clone_repo.ipynb first."
    exit 1
fi

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
log_section() {
    echo ""
    echo "==============================================="
    echo " $1"
    echo "==============================================="
}

run_hook() {
    local name="$1"
    local hook="$HOOKS_DIR/${name}.sh"
    if [ -f "$hook" ]; then
        echo "[HOOK] Running ${name}.sh"
        bash "$hook"
    fi
}

venv_has_python() { [ -x "$VENV_DIR/bin/python" ]; }
venv_has_pip() { "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; }

compute_req_hash() {
    local files=()
    if [ -n "$REQUIREMENTS_FILE" ] && [ -f "$REPO_DIR/$REQUIREMENTS_FILE" ]; then
        files+=("$REPO_DIR/$REQUIREMENTS_FILE")
    fi
    if [ -n "$TORCH_REQUIREMENTS_FILE" ] && [ -f "$REPO_DIR/$TORCH_REQUIREMENTS_FILE" ]; then
        files+=("$REPO_DIR/$TORCH_REQUIREMENTS_FILE")
    fi
    if [ ${#files[@]} -eq 0 ]; then
        echo "no-requirements"
        return
    fi
    sha256sum "${files[@]}" | sha256sum | awk '{print $1}'
}

REQ_HASH=$(compute_req_hash)
export REQ_HASH

can_reuse_existing_env() {
    [ "$FORCE_REINSTALL" = "1" ] && return 1
    venv_has_python && venv_has_pip || return 1
    [ -f "$FINGERPRINT_FILE" ] || return 1

    local reuse
    reuse=$(
        "$VENV_DIR/bin/python" - <<'PY'
import importlib.util, json, os
fp = os.environ.get("FINGERPRINT_FILE", "")
req_hash = os.environ.get("REQ_HASH", "")
venv_dir = os.environ.get("VENV_DIR", "")
modules = os.environ.get("REUSE_CHECK_MODULES", "torch").split()

def has(name):
    return importlib.util.find_spec(name) is not None

ok = False
try:
    with open(fp) as f:
        data = json.load(f)
    ok = (
        data.get("requirements_sha256") == req_hash
        and data.get("venv_dir") == venv_dir
        and all(has(m) for m in modules)
    )
except Exception:
    ok = False
print("1" if ok else "0")
PY
    )
    [ "$reuse" = "1" ]
}

snapshot_compatible() {
    [ -f "$VENV_SNAPSHOT_META" ] || return 1
    local ok
    ok=$(
        "$PYTHON_BIN" - <<'PY'
import json, os, sys
meta = os.environ.get("VENV_SNAPSHOT_META", "")
req_hash = os.environ.get("REQ_HASH", "")
mm = f"{sys.version_info.major}.{sys.version_info.minor}"
result = False
try:
    with open(meta) as f:
        d = json.load(f)
    result = (
        d.get("requirements_sha256") == req_hash
        and str(d.get("python_major_minor", "")) == mm
    )
except Exception:
    result = False
print("1" if result else "0")
PY
    )
    [ "$ok" = "1" ]
}

restore_snapshot() {
    [ "$ENABLE_VENV_SNAPSHOT" = "1" ] || return 1
    [ -f "$VENV_SNAPSHOT_FILE" ] || return 1
    if ! snapshot_compatible; then
        echo "[INFO] Snapshot incompatible (requirements/python changed). Skipping."
        return 1
    fi

    echo "[INFO] Restoring venv snapshot from Drive..."
    rm -rf "$VENV_DIR"
    mkdir -p "$(dirname "$VENV_DIR")"
    if ! tar -xzf "$VENV_SNAPSHOT_FILE" -C "$(dirname "$VENV_DIR")"; then
        echo "[WARN] Extract failed."
        rm -rf "$VENV_DIR"
        return 1
    fi
    if venv_has_python && venv_has_pip; then
        echo "[INFO] Snapshot restored."
        return 0
    fi
    rm -rf "$VENV_DIR"
    return 1
}

create_venv() {
    if [ -d "$VENV_DIR" ] && venv_has_python && venv_has_pip; then
        return 0
    fi
    rm -rf "$VENV_DIR"
    echo "[INFO] Creating venv at $VENV_DIR (--copies for Drive noexec safety)"
    if ! "$PYTHON_BIN" -m venv --copies "$VENV_DIR" 2>/dev/null; then
        echo "[WARN] venv module failed. Falling back to virtualenv."
        "$PYTHON_BIN" -m pip install --upgrade virtualenv
        "$PYTHON_BIN" -m virtualenv --always-copy "$VENV_DIR"
    fi
    if ! venv_has_pip; then
        "$VENV_DIR/bin/python" -m ensurepip --upgrade
    fi
    if ! venv_has_python || ! venv_has_pip; then
        echo "[ERROR] Failed to create usable venv"
        exit 1
    fi
}

write_snapshot() {
    [ "$ENABLE_VENV_SNAPSHOT" = "1" ] || return 0
    venv_has_python || return 0

    echo "[INFO] Saving venv snapshot to Drive..."
    local parent base tmp mm
    parent="$(dirname "$VENV_DIR")"
    base="$(basename "$VENV_DIR")"
    tmp="$VENV_SNAPSHOT_FILE.tmp"
    rm -f "$tmp"
    if tar -czf "$tmp" -C "$parent" "$base"; then
        mv -f "$tmp" "$VENV_SNAPSHOT_FILE"
        mm=$("$VENV_DIR/bin/python" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        cat > "$VENV_SNAPSHOT_META" <<EOF
{
  "generated_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "requirements_sha256": "$REQ_HASH",
  "python_major_minor": "$mm",
  "snapshot_file": "$VENV_SNAPSHOT_FILE"
}
EOF
        echo "[INFO] Snapshot saved: $VENV_SNAPSHOT_FILE"
    else
        rm -f "$tmp"
        echo "[WARN] Snapshot tar failed."
    fi
}

print_done() {
    echo ""
    echo "==============================================="
    echo "[DONE] Bootstrap completed"
    echo "==============================================="
    echo "  project       : $PROJECT_SLUG"
    echo "  venv          : $VENV_DIR"
    echo "  drive root    : $DRIVE_ROOT"
    echo "  fingerprint   : $FINGERPRINT_FILE"
    echo "  lock file     : $LOCK_FILE"
    echo ""
    echo "Activate venv:"
    echo "  source $VENV_DIR/bin/activate"
    echo ""
}

install_apt_packages() {
    local all_packages
    all_packages=$(echo "$APT_PYTHON_PACKAGES $APT_EXTRA_PACKAGES" | xargs)
    [ -z "$all_packages" ] && return 0

    run_hook "pre_apt"

    echo "[INFO] apt install: $all_packages"
    apt-get update -qq
    if ! apt-get install -y $all_packages 2>/dev/null; then
        if [[ "$APT_PYTHON_PACKAGES" =~ python3\.1[0-9] ]]; then
            echo "[INFO] Python 3.10/3.11 not in default repos. Adding deadsnakes PPA..."
            apt-get install -y software-properties-common
            add-apt-repository -y ppa:deadsnakes/ppa
            apt-get update -qq
            apt-get install -y $all_packages
        else
            echo "[ERROR] apt install failed"
            return 1
        fi
    fi

    run_hook "post_apt"
}

# ============================================================
# Main flow
# ============================================================
log_section "Config summary"
echo "  PROJECT_SLUG       : $PROJECT_SLUG"
echo "  BASE_ROOT          : $BASE_ROOT"
echo "  REPO_DIR           : $REPO_DIR"
echo "  DRIVE_ROOT         : $DRIVE_ROOT"
echo "  VENV_DIR           : $VENV_DIR"
echo "  PYTHON_BIN         : $PYTHON_BIN"
echo "  REQUIREMENTS_FILE  : $REQUIREMENTS_FILE"
echo "  TORCH_REQ_FILE     : ${TORCH_REQUIREMENTS_FILE:-(none)}"
echo "  TORCH_INDEX_URL    : $TORCH_INDEX_URL"
echo "  REUSE_CHECK        : $REUSE_CHECK_MODULES"
echo "  FORCE_REINSTALL    : $FORCE_REINSTALL"
echo "  ENABLE_SNAPSHOT    : $ENABLE_VENV_SNAPSHOT"
echo "  REQ_HASH           : $REQ_HASH"

log_section "APT packages"
install_apt_packages

if ! command -v "$PYTHON_BIN" &>/dev/null; then
    echo "[ERROR] $PYTHON_BIN not found after apt install. Check APT_PYTHON_PACKAGES."
    exit 1
fi
echo "[INFO] $($PYTHON_BIN --version 2>&1)"

# Fast reuse before anything else
if can_reuse_existing_env; then
    echo "[INFO] Existing venv is healthy and requirements unchanged. Reusing."
    print_done
    exit 0
fi

log_section "Venv preparation"

# Try snapshot restore
if ! venv_has_python || ! venv_has_pip; then
    restore_snapshot || true
fi

# Create venv if still missing
create_venv

# Re-check reuse after restore
if can_reuse_existing_env; then
    echo "[INFO] Snapshot restore satisfied requirements. Reusing."
    print_done
    exit 0
fi

log_section "Installing dependencies"

run_hook "pre_install"

echo "[INFO] Pre-install: $PIP_PRE_INSTALL"
"$VENV_DIR/bin/python" -m pip install --upgrade $PIP_PRE_INSTALL

# Torch (optional, có thể từ file riêng hoặc default)
if [ "$INSTALL_TORCH" = "1" ]; then
    if [ -n "$TORCH_REQUIREMENTS_FILE" ] && [ -f "$REPO_DIR/$TORCH_REQUIREMENTS_FILE" ]; then
        echo "[INFO] Installing torch from $TORCH_REQUIREMENTS_FILE ($TORCH_INDEX_URL)"
        "$VENV_DIR/bin/python" -m pip install --cache-dir "$PIP_CACHE_DIR" \
            $TORCH_INDEX_FLAG "$TORCH_INDEX_URL" \
            -r "$REPO_DIR/$TORCH_REQUIREMENTS_FILE"
    else
        echo "[INFO] Installing torch + torchaudio default ($TORCH_INDEX_URL)"
        "$VENV_DIR/bin/python" -m pip install --cache-dir "$PIP_CACHE_DIR" \
            $TORCH_INDEX_FLAG "$TORCH_INDEX_URL" \
            torch torchaudio
    fi
fi

# Main requirements
if [ -n "$REQUIREMENTS_FILE" ] && [ -f "$REPO_DIR/$REQUIREMENTS_FILE" ]; then
    REQ_TO_INSTALL="$REPO_DIR/$REQUIREMENTS_FILE"
    # Nếu torch đã cài riêng và REQUIREMENTS_FILE có torch lines → filter ra
    # để không bị override version.
    if [ "$INSTALL_TORCH" = "1" ] && [ -z "$TORCH_REQUIREMENTS_FILE" ]; then
        FILTERED="/tmp/${PROJECT_SLUG}_req_filtered.txt"
        grep -viE '^[[:space:]]*(torch|torchaudio|torchvision)([[:space:]<>=!~]|$)' \
            "$REQ_TO_INSTALL" > "$FILTERED" || true
        if ! cmp -s "$REQ_TO_INSTALL" "$FILTERED"; then
            echo "[INFO] Filtered torch lines from $REQUIREMENTS_FILE to avoid override"
            REQ_TO_INSTALL="$FILTERED"
        fi
    fi
    echo "[INFO] Installing $REQUIREMENTS_FILE"
    "$VENV_DIR/bin/python" -m pip install --cache-dir "$PIP_CACHE_DIR" -r "$REQ_TO_INSTALL"
fi

log_section "Post-install hooks"
run_hook "post_install"

log_section "Lock file + fingerprint"
echo "[INFO] Writing lock file"
"$VENV_DIR/bin/python" -m pip freeze > "$LOCK_FILE"

PY_VER=$("$VENV_DIR/bin/python" -c "import platform; print(platform.python_version())")
TORCH_VER=$("$VENV_DIR/bin/python" -c "
import importlib.util
if importlib.util.find_spec('torch'):
    import torch; print(torch.__version__)
else:
    print('not-installed')
")

cat > "$FINGERPRINT_FILE" <<EOF
{
  "generated_at_utc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "python_version": "$PY_VER",
  "torch_version": "$TORCH_VER",
  "requirements_sha256": "$REQ_HASH",
  "venv_dir": "$VENV_DIR",
  "reuse_check_modules": "$REUSE_CHECK_MODULES"
}
EOF

log_section "Verification"
"$VENV_DIR/bin/python" -m pip check || echo "[WARN] pip check found issues (may be OK)"

if [ -f "$SUBMODULE_ROOT/scripts/tools/verify_env.py" ]; then
    "$VENV_DIR/bin/python" "$SUBMODULE_ROOT/scripts/tools/verify_env.py" || \
        echo "[WARN] verify_env.py had issues"
fi

run_hook "verify_extra"

log_section "Snapshot"
write_snapshot

print_done
