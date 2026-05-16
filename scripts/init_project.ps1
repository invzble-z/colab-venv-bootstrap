<#
.SYNOPSIS
    Onboarding script: copy templates and setup `colab/` structure in project root
    after `git submodule add colab-venv-bootstrap colab/bootstrap`.

.DESCRIPTION
    Run from project root after adding submodule. Script will:
      1. Verify running in submodule context (parent has .git).
      2. Copy templates/config.env.example -> ../../config.env (if missing).
      3. Copy notebooks/{00,01}.ipynb -> ../../<file>.ipynb (if missing).
      4. Copy templates/02_template.ipynb -> ../../02_<task>.ipynb (ask task name).
      5. Create ../../hooks/ + copy hooks/post_install.sh.example.
      6. Print next steps.

.PARAMETER TaskName
    Task name for notebook 02 (e.g. "train", "run_server", "infer"). Default: "task".

.PARAMETER Force
    Overwrite existing files (default: skip).

.PARAMETER NonInteractive
    No prompts (use default values).

.EXAMPLE
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
    Write-Host "[INFO] Script running from dev repo (not submodule context)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This script only works after adding toolkit as submodule in project root:"
    Write-Host ""
    Write-Host "  cd D:\path\to\my-project" -ForegroundColor Gray
    Write-Host "  git submodule add https://github.com/<user>/colab-venv-bootstrap colab/bootstrap" -ForegroundColor Gray
    Write-Host "  .\colab\bootstrap\scripts\init_project.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or if this is dev context (developing the toolkit), no need to run."
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
        Write-Host "[ERROR] Not found: $full" -ForegroundColor Red
        Write-Host "        Submodule may be missing files. Run:" -ForegroundColor Red
        Write-Host "          git submodule update --init --recursive" -ForegroundColor Gray
        exit 1
    }
}

# ============================================================
# Ask TaskName if interactive
# ============================================================
if (-not $TaskName -and -not $NonInteractive) {
    Write-Host "Notebook 02 is the main task notebook (e.g. train/run_server/infer)."
    $userInput = Read-Host "Task name for notebook 02 [task]"
    if ($userInput) { $TaskName = $userInput.Trim() }
}
if (-not $TaskName) { $TaskName = "task" }

# Sanitize: only a-z 0-9 _ allowed
if ($TaskName -notmatch '^[a-zA-Z0-9_]+$') {
    Write-Host "[ERROR] TaskName must contain only a-z, A-Z, 0-9, _" -ForegroundColor Red
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
        Write-Host "          (already exists - use -Force to overwrite)" -ForegroundColor DarkGray
        return $false
    }

    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "  [COPY]  $Label" -ForegroundColor Green
    Write-Host "          -> $dst" -ForegroundColor DarkGray
    return $true
}

# ============================================================
# Copy templates
# ============================================================
Write-Host "[STEP] Copy templates -> $ColabDir" -ForegroundColor Cyan

$copiedConfig = Copy-Template "templates/config.env.example" "config.env" "config.env"

# Notebook 00 + 01 (generic)
$copied00 = Copy-Template "notebooks/00_clone_repo.ipynb" "00_clone_repo.ipynb" "00_clone_repo.ipynb"
$copied01 = Copy-Template "notebooks/01_bootstrap_env.ipynb" "01_bootstrap_env.ipynb" "01_bootstrap_env.ipynb"

# Notebook 02 (from template)
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
Write-Host " Setup completed - next steps" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$step = 1
Write-Host "${step}. Edit colab/config.env: PROJECT_SLUG, BASE_ROOT, PYTHON_BIN, requirements path, ..." -ForegroundColor White
Write-Host "   notepad `"$ColabDir\config.env`"" -ForegroundColor Gray
Write-Host "   docs: $SubmoduleRoot\docs\config_reference.md" -ForegroundColor DarkGray
Write-Host ""

$step++
Write-Host "${step}. (Optional) Write project-specific hooks:" -ForegroundColor White
Write-Host "   - colab/hooks/post_install.sh    (after pip install: clone subrepo, build Cython, ...)" -ForegroundColor Gray
Write-Host "   - colab/hooks/verify_extra.sh    (custom verify steps)" -ForegroundColor Gray
Write-Host "   docs: $SubmoduleRoot\docs\hooks_reference.md" -ForegroundColor DarkGray
Write-Host "   References: $SubmoduleRoot\examples\" -ForegroundColor DarkGray
Write-Host ""

$step++
Write-Host "${step}. Commit + push to GitHub:" -ForegroundColor White
Write-Host "   git add ." -ForegroundColor Gray
Write-Host "   git commit -m `"feat: integrate colab-venv-bootstrap`"" -ForegroundColor Gray
Write-Host "   git push" -ForegroundColor Gray
Write-Host ""

$step++
Write-Host "${step}. On Google Colab:" -ForegroundColor White
Write-Host "   a) Open colab/00_clone_repo.ipynb -> clone/pull repo to Drive" -ForegroundColor Gray
Write-Host "   b) Open colab/01_bootstrap_env.ipynb -> bootstrap venv" -ForegroundColor Gray
Write-Host "   c) Open colab/02_$TaskName.ipynb -> run main task" -ForegroundColor Gray
Write-Host ""

Write-Host "Done." -ForegroundColor Green
Write-Host ""
