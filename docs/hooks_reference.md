# Hooks reference

Hook là file shell script đặt trong `<project>/colab/hooks/`. Bootstrap script auto-detect theo tên và chạy với `bash <hook-file>` (không cần `chmod +x`).

## Lifecycle hooks

Thứ tự thực thi:

```
bootstrap_env.sh
  │
  ├── apt install
  │     ├── [hook] pre_apt.sh
  │     ├── apt-get install ...
  │     └── [hook] post_apt.sh
  │
  ├── (fast path) reuse existing env? → done
  │
  ├── snapshot restore? → done
  │
  ├── create venv
  │
  ├── pip install
  │     ├── [hook] pre_install.sh
  │     ├── pip install $PIP_PRE_INSTALL
  │     ├── pip install torch (if INSTALL_TORCH=1)
  │     ├── pip install -r $REQUIREMENTS_FILE
  │     └── [hook] post_install.sh         ← phổ biến nhất
  │
  ├── write fingerprint + lock file
  │
  ├── verify
  │     ├── pip check
  │     ├── verify_env.py (REUSE_CHECK_MODULES)
  │     └── [hook] verify_extra.sh
  │
  └── save snapshot
```

## Hooks chi tiết

### `pre_apt.sh` / `post_apt.sh`

Hiếm dùng. Use cases:
- `pre_apt.sh`: thêm PPA tùy chỉnh trước khi install.
- `post_apt.sh`: post-config cho system package (vd `update-alternatives`).

### `pre_install.sh`

Trước khi pip install gì. Use cases:
- Setup env vars cho pip resolver (vd `PIP_NO_BUILD_ISOLATION`).
- Pre-create build dirs.

### `post_install.sh` (phổ biến nhất)

Sau khi pip install xong tất cả. Use cases điển hình:

**1. Clone repo phụ + install editable**
```bash
PIPER_REPO_DIR="$DRIVE_ROOT/external/piper"
[ ! -d "$PIPER_REPO_DIR/.git" ] && \
    git clone --depth 1 https://github.com/rhasspy/piper.git "$PIPER_REPO_DIR"
"$VENV_DIR/bin/python" -m pip install --no-deps -e "$PIPER_REPO_DIR/src/python"
```

**2. Build C/Cython extension**
```bash
(
    export PATH="$VENV_DIR/bin:$PATH"
    cd "$PIPER_REPO_DIR/src/python"
    bash build_monotonic_align.sh
)
```

**3. Swap package version (vd CPU → GPU)**
```bash
"$VENV_DIR/bin/python" -m pip uninstall -y onnxruntime onnxruntime-gpu
"$VENV_DIR/bin/python" -m pip install onnxruntime-gpu
```

**4. Download model weights**
```bash
MODEL_DIR="$DRIVE_ROOT/checkpoints"
mkdir -p "$MODEL_DIR"
"$VENV_DIR/bin/python" -c "
from huggingface_hub import hf_hub_download
hf_hub_download(repo_id='org/model', filename='model.bin', local_dir='$MODEL_DIR')
"
```

### `verify_extra.sh`

Sau khi default verify (pip check + verify_env.py) chạy xong. Use cases:
- Verify CUDA provider của onnxruntime.
- Verify model files đã tồn tại.
- Print system info để debug.

## Env vars có sẵn trong hooks

Hook nhận tất cả env vars đã export bởi bootstrap_env.sh:

| Var | Mô tả |
|---|---|
| `VENV_DIR` | Path venv (vd `/content/venvs/my_project`) |
| `REPO_DIR` | Path repo trên Drive |
| `DRIVE_ROOT` | Artifacts root trên Drive |
| `PIP_CACHE_DIR` | Pip cache dir |
| `HF_CACHE_DIR` / `HF_HOME` | HuggingFace cache |
| `COLAB_DIR` | `<project>/colab/` |
| `SUBMODULE_ROOT` | `<project>/colab/bootstrap/` |
| `HOOKS_DIR` | `<project>/colab/hooks/` |
| `PROJECT_SLUG`, `BASE_ROOT` | Từ config.env |

Pattern phổ biến trong hook:
```bash
#!/usr/bin/env bash
set -euo pipefail
VENV_PY="$VENV_DIR/bin/python"
# Dùng $VENV_PY thay cho python để chắc chắn chạy trong venv
```

## Hook fail strategy

Hook chạy với `bash $hook` — nếu hook `set -e` và 1 lệnh fail, hook exit nonzero → bootstrap **dừng** (vì bootstrap cũng `set -e`).

Nếu hook không critical, wrap với `|| true`:
```bash
# Trong hook
optional_step || echo "[WARN] optional step failed, continuing"
```

Hoặc trong bootstrap, mock hook fail:
```bash
# Trong hook
exit 0  # luôn success
```

## Test hook local

Trên Windows local, hook không chạy được (vì `bash`, Linux paths). Test trên WSL2:

```bash
# Trong WSL2
export PROJECT_SLUG="my_project"
export VENV_DIR=/tmp/test-venv
export REPO_DIR=/tmp/test-repo
export DRIVE_ROOT=/tmp/test-drive
export PIP_CACHE_DIR=/tmp/test-cache/pip
mkdir -p "$VENV_DIR" "$REPO_DIR" "$DRIVE_ROOT" "$PIP_CACHE_DIR"

bash colab/hooks/post_install.sh
```

Hoặc chạy notebook 01 trên Colab và xem log — nếu hook fail, sẽ thấy traceback trong cell output.
