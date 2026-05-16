<#
.SYNOPSIS
    Onboarding script: copy templates và setup cấu trúc `colab/` trong project gốc
    sau khi `git submodule add colab-venv-bootstrap colab/bootstrap`.

.DESCRIPTION
    Chạy script này TỪ submodule sau khi đã add vào project gốc. Script sẽ:
      1. Verify đang chạy trong submodule context (parent có .git).
      2. Copy templates/config.env.example → ../../config.env (nếu chưa có).
      3. Copy notebooks/{00,01}.ipynb → ../../<file>.ipynb (nếu chưa có).
      4. Copy templates/02_template.ipynb → ../../02_<task>.ipynb (hỏi task name).
      5. Tạo thư mục ../../hooks/ + copy hooks/post_install.sh.example.
      6. Print "next steps".

.PARAMETER TaskName
    Tên task cho notebook 02 (vd "train", "run_server", "infer"). Mặc định "task".

.PARAMETER Force
    Overwrite các file đã tồn tại (mặc định: skip).

.PARAMETER NonInteractive
    Không hỏi user (dùng giá trị mặc định cho TaskName).

.EXAMPLE
    # Từ project gốc, sau khi `git submodule add ... colab/bootstrap`
    .\colab\bootstrap\scripts\init_project.ps1

.EXAMPLE
    .\colab\bootstrap\scripts\init_project.ps1 -TaskName train -Force
#>

[CmdletBinding()]
param(
    [string]$TaskName = "",
    [switch]$Force,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

# ============================================================
# Resolve paths
# ============================================================
$ScriptDir = $PSScriptRoot                                # .../colab/bootstrap/scripts
$SubmoduleRoot = Resolve-Path (Join-Path $ScriptDir "..")  # .../colab/bootstrap
$ColabDir = Resolve-Path (Join-Path $SubmoduleRoot "..") -ErrorAction SilentlyContinue  # .../colab
$ProjectRoot = if ($ColabDir) { Resolve-Path (Join-Path $ColabDir "..") -ErrorAction SilentlyContinue } else { $null }

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " colab-venv-bootstrap :: init_project.ps1" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Detect context: dev mode vs project-integration mode
# ============================================================
$IsDevMode = $false

if (-not $ProjectRoot -or -not (Test-Path (Join-Path $ProjectRoot ".git"))) {
    $IsDevMode = $true
}

if ($IsDevMode) {
    Write-Host "[INFO] Script đang chạy từ repo dev (không phải submodule context)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Script này chỉ có tác dụng khi đã add toolkit làm submodule trong project gốc:"
    Write-Host ""
    Write-Host "  cd D:\path\to\my-project" -ForegroundColor Gray
    Write-Host "  git submodule add https://github.com/<user>/colab-venv-bootstrap colab/bootstrap" -ForegroundColor Gray
    Write-Host "  .\colab\bootstrap\scripts\init_project.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Hoặc nếu đây là context dev (bạn đang phát triển toolkit), script không cần chạy."
    Write-Host ""
    exit 0
}

Write-Host "[INFO] Project root  : $ProjectRoot"
Write-Host "[INFO] colab/ folder : $ColabDir"
Write-Host "[INFO] Submodule     : $SubmoduleRoot"
Write-Host ""

# ============================================================
# Verify submodule structure
# ============================================================
$RequiredPaths = @(
    "templates/config.env.example",
    "templates/hooks/post_install.sh.example"
)

foreach ($rel in $RequiredPaths) {
    $full = Join-Path $SubmoduleRoot $rel
    if (-not (Test-Path $full)) {
        Write-Host "[ERROR] Không tìm thấy: $full" -ForegroundColor Red
        Write-Host "        Submodule có thể bị thiếu file. Chạy:" -ForegroundColor Red
        Write-Host "          git submodule update --init --recursive" -ForegroundColor Gray
        exit 1
    }
}

# ============================================================
# Ask TaskName if interactive
# ============================================================
if (-not $TaskName -and -not $NonInteractive) {
    Write-Host "Notebook 02 là notebook chính của project (vd train/run_server/infer)."
    $input = Read-Host "Tên task cho notebook 02 [task]"
    if ($input) { $TaskName = $input.Trim() }
}
if (-not $TaskName) { $TaskName = "task" }

# Sanitize: chỉ cho phép a-z 0-9 _
if ($TaskName -notmatch '^[a-zA-Z0-9_]+$') {
    Write-Host "[ERROR] TaskName chỉ được chứa a-z, A-Z, 0-9, _" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Task name     : $TaskName"
Write-Host ""

# ============================================================
# Copy helper
# ============================================================
function Copy-Template {
    param(
        [string]$SrcRel,
        [string]$DstRel,
        [string]$Label
    )

    $src = Join-Path $SubmoduleRoot $SrcRel
    $dst = Join-Path $ColabDir $DstRel
    $dstDir = Split-Path $dst -Parent

    if (-not (Test-Path $src)) {
        Write-Host "  [SKIP]  $Label" -ForegroundColor DarkYellow
        Write-Host "          source missing: $SrcRel" -ForegroundColor DarkGray
        return $false
    }

    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }

    if ((Test-Path $dst) -and -not $Force) {
        Write-Host "  [KEEP]  $Label" -ForegroundColor Gray
        Write-Host "          $dst" -ForegroundColor DarkGray
        Write-Host "          (đã tồn tại — dùng -Force để ghi đè)" -ForegroundColor DarkGray
        return $false
    }

    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "  [COPY]  $Label" -ForegroundColor Green
    Write-Host "          → $dst" -ForegroundColor DarkGray
    return $true
}

# ============================================================
# Copy templates
# ============================================================
Write-Host "[STEP] Copy templates → $ColabDir" -ForegroundColor Cyan

$copiedConfig = Copy-Template "templates/config.env.example" "config.env" "config.env"

# Notebook 00 + 01 — generic
$copied00 = Copy-Template "notebooks/00_clone_repo.ipynb" "00_clone_repo.ipynb" "00_clone_repo.ipynb"
$copied01 = Copy-Template "notebooks/01_bootstrap_env.ipynb" "01_bootstrap_env.ipynb" "01_bootstrap_env.ipynb"

# Notebook 02 — từ template
$copied02 = Copy-Template "templates/02_template.ipynb" "02_$TaskName.ipynb" "02_$TaskName.ipynb"

# Hooks folder
$hooksDir = Join-Path $ColabDir "hooks"
if (-not (Test-Path $hooksDir)) {
    New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
    Write-Host "  [MKDIR] hooks/" -ForegroundColor Green
}

$copiedHook = Copy-Template "templates/hooks/post_install.sh.example" "hooks/post_install.sh.example" "hooks/post_install.sh.example"

Write-Host ""

# ============================================================
# Print next steps
# ============================================================
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " Setup hoàn tất — các bước tiếp theo" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$step = 1
Write-Host "${step}. Điền colab/config.env với PROJECT_SLUG, BASE_ROOT, PYTHON_BIN, requirements path, ..." -ForegroundColor White
Write-Host "   notepad `"$ColabDir\config.env`"" -ForegroundColor Gray
Write-Host "   docs: $SubmoduleRoot\docs\config_reference.md" -ForegroundColor DarkGray
Write-Host ""

$step++
Write-Host "${step}. (Tuỳ chọn) Viết hooks project-specific:" -ForegroundColor White
Write-Host "   - colab/hooks/post_install.sh — chạy sau pip install (clone repo phụ, build Cython, ...)" -ForegroundColor Gray
Write-Host "   - colab/hooks/verify_extra.sh — custom verify steps" -ForegroundColor Gray
Write-Host "   docs: $SubmoduleRoot\docs\hooks_reference.md" -ForegroundColor DarkGray
Write-Host "   Tham khảo: $SubmoduleRoot\examples\" -ForegroundColor DarkGray
Write-Host ""

if (-not $copied00 -or -not $copied01 -or -not $copied02) {
    $step++
    Write-Host "${step}. ⚠ Một số notebook generic chưa được tạo trong submodule (Phase 2 - cần MCP Jupyter)." -ForegroundColor Yellow
    Write-Host "   Tạm thời tham khảo notebook trong examples/ để tự tạo:" -ForegroundColor Gray
    Write-Host "   - examples/piper-tts-finetuning/02_train.ipynb" -ForegroundColor DarkGray
    Write-Host "   - examples/fastapi-server-cloudflared/02_run_server.ipynb" -ForegroundColor DarkGray
    Write-Host ""
}

$step++
Write-Host "${step}. Commit + push lên GitHub:" -ForegroundColor White
Write-Host "   git add ." -ForegroundColor Gray
Write-Host "   git commit -m `"feat: integrate colab-venv-bootstrap`"" -ForegroundColor Gray
Write-Host "   git push" -ForegroundColor Gray
Write-Host ""

$step++
Write-Host "${step}. Trên Google Colab:" -ForegroundColor White
Write-Host "   a) Mở colab/00_clone_repo.ipynb → clone/pull repo về Drive" -ForegroundColor Gray
Write-Host "   b) Mở colab/01_bootstrap_env.ipynb → bootstrap venv" -ForegroundColor Gray
Write-Host "   c) Mở colab/02_$TaskName.ipynb → chạy task chính" -ForegroundColor Gray
Write-Host ""

Write-Host "Hoàn tất. Chúc may mắn!" -ForegroundColor Green
Write-Host ""
