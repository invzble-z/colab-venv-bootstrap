# Example: Piper TTS fine-tuning

Reference cho usecase **train TTS model** trên Colab T4, base Piper-train + torch 1.13.

## Đặc điểm

| Aspect | Value |
|---|---|
| Python | 3.10 (cần apt install vì Colab default 3.12) |
| Torch | 1.13.1 + cu117 (yêu cầu cho `pytorch-lightning 1.7.7`) |
| Requirements layout | `requirements.txt` (main) + `requirements-pytorch.txt` (torch riêng) |
| APT packages | python3.10, espeak-ng, libsndfile1, build-essential |
| Post-install hooks | Clone `rhasspy/piper` → install editable → build Cython `monotonic_align` |
| Notebook 02 | `02_train.ipynb` — chạy `piper_train` từ checkpoint |

## Files

- [`config.env`](config.env) — config đã điền cho piper finetuning.
- [`hooks/post_install.sh`](hooks/post_install.sh) — clone piper repo + build monotonic_align.
- `02_train.ipynb` — notebook train (TODO: copy từ piper project).

## Cách dùng

Trong project gốc (vd `piper_vi_male_finetuning/`):

```powershell
git submodule add https://github.com/<user>/colab-venv-bootstrap colab/bootstrap
.\colab\bootstrap\scripts\init_project.ps1 -TaskName train

# Copy config + hook từ example này
Copy-Item colab\bootstrap\examples\piper-tts-finetuning\config.env colab\config.env -Force
Copy-Item colab\bootstrap\examples\piper-tts-finetuning\hooks\post_install.sh colab\hooks\post_install.sh -Force

# Sửa colab\config.env: PROJECT_SLUG, BASE_ROOT, GITHUB_REPO_URL cho phù hợp
notepad colab\config.env
```

## Note kỹ thuật

### Pin pip < 24.1 + setuptools < 81

`pytorch-lightning 1.7.7` (Piper requirement) yêu cầu:
- pip < 24.1 vì pip 24.1+ siết PEP 440, refuse `torch (>=1.9.*)` của lightning.
- setuptools < 81 vì setuptools 81+ remove `pkg_resources` mà lightning vẫn import.

→ `PIP_PRE_INSTALL="pip<24.1 setuptools<81 wheel"` trong config.env.

### Tách torch ra file riêng

Piper repo dùng pattern:
- `requirements-pytorch.txt`: chỉ torch + torchaudio pin version
- `requirements.txt`: deps khác (lightning, librosa, ...)

→ Lý do: torch index URL khác nhau (cu117 vs PyPI), tách giúp pip resolver không nhầm lẫn.

→ Trong config: `TORCH_REQUIREMENTS_FILE="requirements-pytorch.txt"`.

### `--no-deps` cho piper-train

`piper-train` setup.py có dep cứng `piper-phonemize~=1.1.0`, package C++ binding. Trên Colab Linux cài được, nhưng nếu pip resolver gặp xung đột thì dùng `--no-deps` để bypass (các deps khác đã có trong `requirements.txt`).

### Build monotonic_align

Piper sử dụng Cython extension `monotonic_align` (tính alignment cho VITS). Build script `build_monotonic_align.sh` cần `cythonize` từ Cython package — phải export PATH với venv/bin trước khi build.
