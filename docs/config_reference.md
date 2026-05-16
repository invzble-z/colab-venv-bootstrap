# config.env reference

File `colab/config.env` (trong project gốc) chứa tất cả biến để bootstrap dùng. Bash-style: `KEY="value"`, không space quanh `=`.

## Biến BẮT BUỘC

### `PROJECT_SLUG`

Slug duy nhất cho project. Dùng để derive paths:
- `REPO_DIR` = `$BASE_ROOT/$PROJECT_SLUG`
- `DRIVE_ROOT` = `$BASE_ROOT/${PROJECT_SLUG}_colab`
- `VENV_DIR` = `/content/venvs/$PROJECT_SLUG`

Ví dụ: `PROJECT_SLUG="piper_vi_male_finetune"`.

## Biến TÙY CHỌN (có default)

### Path

| Biến | Default | Mô tả |
|---|---|---|
| `BASE_ROOT` | `/content/drive/MyDrive` | Drive root chứa project |
| `REPO_DIR` | `$BASE_ROOT/$PROJECT_SLUG` | Override nếu repo ở chỗ khác |
| `DRIVE_ROOT` | `$BASE_ROOT/${PROJECT_SLUG}_colab` | Artifacts root |
| `VENV_DIR` | `/content/venvs/$PROJECT_SLUG` | Venv local (KHÔNG đặt trên Drive — `noexec`) |
| `PIP_CACHE_DIR` | `$DRIVE_ROOT/cache/pip` | Pip cache (persist giữa session) |
| `HF_CACHE_DIR` | `$DRIVE_ROOT/cache/hf` | HuggingFace cache |

### Python

| Biến | Default | Mô tả |
|---|---|---|
| `PYTHON_BIN` | `python3` | Binary để tạo venv |
| `APT_PYTHON_PACKAGES` | `""` | Cài Python phiên bản cụ thể (vd `python3.10 python3.10-venv python3.10-dev`) |
| `APT_EXTRA_PACKAGES` | `""` | APT packages bổ sung (vd `espeak-ng libsndfile1`) |

**Khi nào cần `python3.10`**:
- torch < 2.0 (chỉ có wheel cho ≤ 3.10).
- pytorch-lightning 1.7.x (yêu cầu torch < 2.0).
- Bất kỳ package nào pin Python < 3.11.

Colab default Python 2026 là 3.12, nên `python3.10` phải apt install (script tự fallback deadsnakes PPA nếu repo default không có).

### Torch

| Biến | Default | Mô tả |
|---|---|---|
| `INSTALL_TORCH` | `1` | `0` = bỏ qua torch |
| `TORCH_INDEX_URL` | `.../whl/cu121` | Wheel index theo CUDA version |
| `TORCH_INDEX_FLAG` | `--extra-index-url` | `--index-url` để force chỉ torch index |
| `TORCH_REQUIREMENTS_FILE` | `""` | Path tới file torch riêng (vd `requirements-pytorch.txt`) |

**Tại sao tách torch ra file riêng**: torch có index URL khác PyPI, tách giúp pip resolver không nhầm. Cũng giúp pin chính xác torch version mà không ảnh hưởng deps khác. Xem [piper example](../examples/piper-tts-finetuning/).

### Requirements + pre-install

| Biến | Default | Mô tả |
|---|---|---|
| `REQUIREMENTS_FILE` | `requirements.txt` | Path từ repo root |
| `PIP_PRE_INSTALL` | `pip setuptools wheel` | Cài TRƯỚC requirements (pin nếu cần) |

**Khi nào cần pin `PIP_PRE_INSTALL`**:
- `pytorch-lightning 1.7.x`: cần `pip<24.1 setuptools<81 wheel` (xem piper example).
- Package legacy yêu cầu pip cũ: pin phù hợp.

### Reuse check

| Biến | Default | Mô tả |
|---|---|---|
| `REUSE_CHECK_MODULES` | `torch` | Space-separated. Verify import được sau cài + quyết định reuse hay rebuild |

Script `verify_env.py` import từng module và print version. Nếu module fail import → exit 1, bootstrap rebuild venv.

Ví dụ:
- TTS finetune: `"torch pytorch_lightning librosa piper_train"`
- FastAPI server: `"torch fastapi faster_whisper onnxruntime"`

### Snapshot

| Biến | Default | Mô tả |
|---|---|---|
| `ENABLE_VENV_SNAPSHOT` | `1` | Lưu snapshot venv lên Drive |
| `FORCE_REINSTALL` | `0` | `1` = rebuild từ đầu, bỏ qua snapshot |

**Khi cần `FORCE_REINSTALL=1`**:
- Snapshot corrupt.
- Đổi major Python (3.10 → 3.11).
- Lỗi import lạ.

### GitHub

| Biến | Default | Mô tả |
|---|---|---|
| `GITHUB_REPO_URL` | (none) | URL không có token, vd `https://github.com/u/r.git` |
| `GITHUB_BRANCH` | `main` | |
| `GITHUB_SPARSE_CHECKOUT` | `""` | Space-separated subfolders, vd `"server colab"` |

Token GitHub được hỏi qua `getpass` trong notebook (KHÔNG lưu config.env).

## Pattern thường gặp

### Pattern A — Train với torch pinned cũ

```bash
PYTHON_BIN="python3.10"
APT_PYTHON_PACKAGES="python3.10 python3.10-venv python3.10-dev"
TORCH_INDEX_URL="https://download.pytorch.org/whl/cu117"
TORCH_REQUIREMENTS_FILE="requirements-pytorch.txt"
PIP_PRE_INSTALL="pip<24.1 setuptools<81 wheel"
```

### Pattern B — Server với torch mới + GPU package

```bash
PYTHON_BIN="python3"
TORCH_INDEX_URL="https://download.pytorch.org/whl/cu121"
TORCH_INDEX_FLAG="--index-url"
# torch + torchaudio cài default version, không cần TORCH_REQUIREMENTS_FILE
REQUIREMENTS_FILE="server/requirements.txt"
REUSE_CHECK_MODULES="torch fastapi onnxruntime"
# post_install hook swap onnxruntime → onnxruntime-gpu
```

### Pattern C — CPU-only / không cần torch

```bash
INSTALL_TORCH=0
REQUIREMENTS_FILE="requirements.txt"
REUSE_CHECK_MODULES="numpy pandas"
```
