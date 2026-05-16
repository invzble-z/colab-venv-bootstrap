# colab-venv-bootstrap

> Reusable toolkit để bootstrap virtual environment trên Google Colab với **snapshot-based fast restore**, dùng làm git submodule trong bất kỳ project nào cần train/serve trên Colab.

## Vấn đề toolkit này giải quyết

Khi train/serve trên Colab, mỗi runtime mới user phải:
- Cài lại Python (nếu cần version cụ thể như 3.10 cho torch < 2.0).
- Cài lại torch + CUDA wheel (~5-7 phút).
- Cài lại deps `requirements.txt` (~2-3 phút).
- Cài lại các bước project-specific (clone repo phụ, build Cython extension, swap onnxruntime-gpu, ...).

→ **Tổng cộng 10-15 phút mỗi lần** — lặp đi lặp lại trong cả phase train kéo dài tuần.

Toolkit này:
- **Cache venv dạng `.tar.gz` snapshot trên Drive**: lần sau restore ~30-60s thay vì cài lại.
- **Fingerprint hash `requirements.txt`**: tự detect khi nào cần rebuild.
- **Hook system** để mỗi project inject các bước riêng (không phải fork toolkit).
- **Config tập trung** trong 1 file `config.env` — không hard-code path/version trong notebook.

## Quick start

```powershell
# 1. Trong project gốc đã có git repo
cd D:\path\to\my-project
git submodule add https://github.com/<your-user>/colab-venv-bootstrap colab/bootstrap

# 2. Chạy init script — copy templates + tạo cấu trúc colab/
.\colab\bootstrap\scripts\init_project.ps1

# 3. Điền colab/config.env (PROJECT_SLUG, BASE_ROOT, PYTHON_BIN, requirements, ...)
notepad colab\config.env

# 4. (Tuỳ chọn) Viết colab/hooks/post_install.sh cho các bước project-specific
# 5. Commit + push lên GitHub
git add . && git commit -m "feat: integrate colab-venv-bootstrap"
git push
```

Trên Colab:
1. Mở `colab/00_clone_repo.ipynb` → clone/pull repo về Drive.
2. Mở `colab/01_bootstrap_env.ipynb` → bootstrap venv (lần đầu ~10 phút, lần sau ~30s).
3. Mở `colab/02_<task>.ipynb` → chạy task chính của project.

## Cấu trúc repo

```
colab-venv-bootstrap/
├── README.md                              ← file này
├── LICENSE                                ← MIT
├── .gitignore
│
├── notebooks/                             ← 2 notebook generic
│   ├── 00_clone_repo.ipynb
│   └── 01_bootstrap_env.ipynb
│
├── scripts/
│   ├── init_project.ps1                   ← PS1 onboarding cho project gốc
│   ├── bootstrap_env.sh                   ← core script (gọi từ notebook 01)
│   ├── lib/                               ← shared bash functions
│   │   ├── venv_helpers.sh
│   │   ├── apt_helpers.sh
│   │   └── hook_runner.sh
│   └── tools/
│       └── verify_env.py                  ← post-install verify
│
├── templates/
│   ├── config.env.example                 ← config mẫu commented
│   ├── 02_template.ipynb                  ← skeleton notebook 02
│   └── hooks/
│       └── post_install.sh.example
│
├── examples/                              ← reference projects
│   ├── piper-tts-finetuning/              ← TTS train, Python 3.10, cu117
│   └── fastapi-server-cloudflared/        ← FastAPI server + tunnel, cu121
│
└── docs/
    ├── config_reference.md                ← danh sách biến config.env
    ├── hooks_reference.md                 ← hook names + interface
    └── troubleshooting.md
```

## Cấu trúc sau khi tích hợp vào project gốc

```
my-project/
├── colab/
│   ├── bootstrap/                         ← submodule (toolkit này)
│   ├── config.env                         ← user điền
│   ├── hooks/                             ← project-specific hooks
│   │   ├── post_install.sh                ← (optional)
│   │   └── verify_extra.sh                ← (optional)
│   ├── 00_clone_repo.ipynb                ← copy từ submodule/notebooks
│   ├── 01_bootstrap_env.ipynb             ← copy từ submodule/notebooks
│   └── 02_<task>.ipynb                    ← project-specific
├── requirements.txt
└── ...
```

## Drive layout khi chạy trên Colab

```
<BASE_ROOT>/<PROJECT_SLUG>/                ← repo gốc (clone về Drive)
<BASE_ROOT>/<PROJECT_SLUG>_colab/          ← artifacts runtime
├── env/
│   ├── fingerprint.json
│   ├── venv_snapshot.tar.gz               ← ~2-3 GB
│   ├── venv_snapshot.meta.json
│   └── requirements.colab.lock.txt
├── cache/{pip,hf,xdg}/
├── external/                              ← repo phụ (vd piper), nếu hook clone
└── logs/

/content/venvs/<PROJECT_SLUG>/             ← venv (LOCAL DISK, không phải Drive)
```

**Lý do venv không đặt trên Drive**: Drive mount với flag `noexec` → không chạy được binary trong venv. Phải đặt trên `/content/` (local disk Colab) và snapshot lên Drive để restore khi runtime mới.

## Documentation

- [docs/config_reference.md](docs/config_reference.md) — toàn bộ biến `config.env`.
- [docs/hooks_reference.md](docs/hooks_reference.md) — hook names, interface, env vars.
- [docs/troubleshooting.md](docs/troubleshooting.md) — lỗi thường gặp.
- [examples/](examples/) — 2 reference project (TTS finetune, FastAPI server).

## License

MIT — xem [LICENSE](LICENSE).
