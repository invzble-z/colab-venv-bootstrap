# Example: FastAPI server với Cloudflare tunnel

Reference cho usecase **serve realtime API** trên Colab (FastAPI + uvicorn + WebSocket), expose qua **Cloudflare tunnel** để client bên ngoài kết nối được.

## Đặc điểm

| Aspect | Value |
|---|---|
| Python | Default Colab (3.12 hoặc whatever Colab cung cấp) |
| Torch | torch + torchaudio mới (cu121) |
| Requirements layout | `server/requirements.txt` |
| Post-install hooks | Swap `onnxruntime` → `onnxruntime-gpu` để dùng CUDA cho TTS inference |
| Notebook 02 | `02_run_server.ipynb` — khởi động uvicorn + cloudflared, lấy URL |

## Files

- [`config.env`](config.env) — config cho FastAPI server.
- [`hooks/post_install.sh`](hooks/post_install.sh) — swap onnxruntime-gpu.
- [`scripts/run_server.sh`](scripts/run_server.sh) — start uvicorn (background, lưu PID).
- [`scripts/cloudflared_start.sh`](scripts/cloudflared_start.sh) — download cloudflared + tạo tunnel, parse URL.
- `02_run_server.ipynb` — notebook orchestrate (TODO: copy từ GradProject).

## Cách dùng

```powershell
git submodule add https://github.com/<user>/colab-venv-bootstrap colab/bootstrap
.\colab\bootstrap\scripts\init_project.ps1 -TaskName run_server

# Copy example files
Copy-Item colab\bootstrap\examples\fastapi-server-cloudflared\config.env colab\config.env -Force
Copy-Item colab\bootstrap\examples\fastapi-server-cloudflared\hooks\post_install.sh colab\hooks\ -Force

# Scripts run_server + cloudflared — copy vào colab/scripts/ của project
New-Item -ItemType Directory -Force colab\scripts | Out-Null
Copy-Item colab\bootstrap\examples\fastapi-server-cloudflared\scripts\*.sh colab\scripts\ -Force

notepad colab\config.env
```

## Note kỹ thuật

### Tại sao swap onnxruntime → onnxruntime-gpu

Một số package TTS (vd `piper-tts`) khi cài qua pip pull `onnxruntime` (CPU build) làm transitive dep. CPU và GPU build cùng expose module name `onnxruntime` → không coexist. Phải uninstall CPU rồi install GPU. **Đặt ở post_install hook** để chạy SAU khi pip install xong requirements (tránh resolver pip override).

Verify bằng:
```python
import onnxruntime as ort
print("CUDAExecutionProvider" in ort.get_available_providers())
# → True nếu GPU build OK
```

### Cloudflare tunnel quick start

Cloudflared download từ release page mới nhất (~30s), tạo tunnel ephemeral (URL random, không cần đăng ký). Log parse regex `https://*.trycloudflare.com` để lấy URL public. WebSocket URL = `wss://{url}/ws`.

### Server PID file

`run_server.sh` lưu PID vào `$DRIVE_ROOT/runtime/server.pid` để session sau biết server đang chạy, không khởi động trùng. Tương tự `cloudflared.pid`.

### HF cache trên Drive

`HF_HOME=$DRIVE_ROOT/cache/hf` để HuggingFace models download 1 lần, các session sau dùng lại — tiết kiệm 5-10 phút download Whisper / NLLB / Piper models.
