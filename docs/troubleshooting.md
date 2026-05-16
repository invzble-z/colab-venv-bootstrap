# Troubleshooting

## Bootstrap-time errors

### `[ERROR] Repo not found at <REPO_DIR>`

**Nguyên nhân**: Notebook 00_clone_repo chưa được chạy, hoặc `PROJECT_SLUG` / `BASE_ROOT` không match folder thực tế trên Drive.

**Fix**:
1. Verify Drive đã mount: `ls /content/drive/MyDrive`.
2. Verify folder tồn tại: `ls $BASE_ROOT/$PROJECT_SLUG`.
3. Verify có `.git/`: `ls $BASE_ROOT/$PROJECT_SLUG/.git`.
4. Nếu chưa có repo → chạy `00_clone_repo.ipynb`.

### `[ERROR] python3.10 not found after apt install`

**Nguyên nhân**: APT_PYTHON_PACKAGES có `python3.10` nhưng apt-get fail (repo default Ubuntu không có).

**Fix**: Script đã tự thử deadsnakes PPA. Nếu vẫn fail:
```bash
# Trong cell Colab
!sudo apt-get install -y software-properties-common
!sudo add-apt-repository -y ppa:deadsnakes/ppa
!sudo apt-get update
!sudo apt-get install -y python3.10 python3.10-venv python3.10-dev
```

### `Permission denied: /content/drive/.../bin/python`

**Nguyên nhân**: Venv đang đặt trên Drive — Drive mount với `noexec`.

**Fix**: Đảm bảo `VENV_DIR` ở `/content/venvs/...` (local disk), không phải `/content/drive/...`.

### `pip install` báo `Could not find a version that satisfies torch==X`

**Nguyên nhân**:
1. Python version không có wheel torch tương ứng (vd Python 3.12 + torch 1.13).
2. CUDA index URL sai.

**Fix**:
1. Check torch wheel ở [pytorch.org/whl](https://pytorch.org/get-started/previous-versions/).
2. Match Python version (vd `python3.10` cho torch 1.13).
3. Verify `TORCH_INDEX_URL` đúng (cu117, cu118, cu121, cu126, ...).

### `pkg_resources` / `pip` errors khi cài pytorch-lightning 1.7.x

**Nguyên nhân**: pip 24.1+ siết PEP 440, refuse `torch (>=1.9.*)` syntax. setuptools 81+ remove `pkg_resources`.

**Fix**: `PIP_PRE_INSTALL="pip<24.1 setuptools<81 wheel"` trong config.env.

## Snapshot-related

### Snapshot restore fail / `[INFO] Snapshot incompatible`

**Nguyên nhân**:
- `requirements.txt` hash khác lần build snapshot.
- Python major.minor khác.

**Fix**: Bình thường — script tự rebuild venv + tạo snapshot mới sau cài xong. Mất ~10 phút lần này, lần sau lại fast restore.

Nếu muốn force xóa snapshot:
```python
# Cell Colab
!rm -f /content/drive/MyDrive/.../env/venv_snapshot.tar.gz
!rm -f /content/drive/MyDrive/.../env/venv_snapshot.meta.json
```

### Snapshot extract corrupt

**Nguyên nhân**: tar.gz bị corrupt (Drive upload bị gián đoạn, Colab crash giữa write).

**Fix**:
```python
FORCE_REINSTALL=1 bash colab/bootstrap/scripts/bootstrap_env.sh
```

## Runtime/Colab issues

### "You are not connected to a runtime" giữa session

**Nguyên nhân**: Colab disconnect (timeout, quota).

**Fix**:
1. Reconnect runtime → mount lại Drive.
2. Mở lại notebook 01 → snapshot restore ~30-60s.
3. Tiếp tục notebook 02. Nếu là train: resume từ checkpoint cuối trên Drive.

### Snapshot quá lớn (> 5 GB), Drive đầy

**Fix**:
- Giảm venv size: pip uninstall các package không cần.
- Disable snapshot: `ENABLE_VENV_SNAPSHOT=0` → mỗi session sẽ cài lại (~10 phút).

## Hook errors

### Hook không được gọi

**Check**:
1. File ở đúng `<project>/colab/hooks/<name>.sh` (không `.example`).
2. Tên hook đúng: `pre_apt`, `post_apt`, `pre_install`, `post_install`, `verify_extra`.
3. Bootstrap script log có in `[HOOK] Running <name>.sh`? Nếu không → file path sai.

### Hook fail làm bootstrap dừng

**Check log**: bootstrap output sẽ in stderr của hook. Common issues:
- `set -e` + lệnh fail giữa chừng.
- Env var không tồn tại (vd quên check `[ -z "${X:-}" ]`).
- Path không tồn tại.

**Quick fix**: comment lại lệnh fail trong hook, rerun bootstrap với `FORCE_REINSTALL=0` (sẽ skip nếu venv healthy).

## Verify CUDA

```python
# Cell Colab
!{VENV_PYTHON} -c "
import torch
print('torch:', torch.__version__)
print('cuda_available:', torch.cuda.is_available())
print('device_count:', torch.cuda.device_count())
if torch.cuda.is_available():
    print('device:', torch.cuda.get_device_name(0))
    print('compute_cap:', torch.cuda.get_device_capability(0))
"
```

Nếu `cuda_available: False`:
- Check Colab runtime: Runtime → Change runtime type → T4 GPU.
- Check torch wheel: `pip show torch | grep Version` — phải có `+cu1XX` suffix.
- Reinstall torch với đúng index: `FORCE_REINSTALL=1`.

## Submodule issues

### `init_project.ps1` báo "Script đang chạy từ repo dev"

**Nguyên nhân**: Bạn chạy script từ chính folder `colab-venv-bootstrap` (đang phát triển toolkit), không phải từ project gốc.

**Fix**: Add làm submodule trong project gốc rồi chạy:
```powershell
cd D:\path\to\my-project
git submodule add https://github.com/<you>/colab-venv-bootstrap colab/bootstrap
.\colab\bootstrap\scripts\init_project.ps1
```

### `git submodule update --init --recursive` không pull được

**Nguyên nhân**: Submodule URL sai, hoặc bạn ở behind firewall.

**Fix**:
```bash
# Check submodule URL
cat .gitmodules

# Reset submodule
git submodule deinit -f colab/bootstrap
rm -rf .git/modules/colab/bootstrap
git submodule update --init --recursive
```

## Khi cần debug sâu

### Print all env vars khi bootstrap

Thêm vào đầu `bootstrap_env.sh` (sau load config):
```bash
echo "=== ENV DUMP ==="
env | grep -E '^(PROJECT_|BASE_|REPO_|DRIVE_|VENV_|PIP_|HF_|TORCH_|REQUIREMENTS_|REUSE_)' | sort
echo "================"
```

### Verify hook nhận đúng env

Thêm vào đầu hook:
```bash
echo "=== HOOK ENV ==="
echo "VENV_DIR=$VENV_DIR"
echo "REPO_DIR=$REPO_DIR"
echo "DRIVE_ROOT=$DRIVE_ROOT"
echo "==============="
```

### Test bootstrap không pull update

Trên Colab, nếu muốn test script local trước khi push:
```python
# Cell Colab
!cd /content/my-project && bash colab/bootstrap/scripts/bootstrap_env.sh
```
