"""Verify venv health sau khi bootstrap.

Đọc REUSE_CHECK_MODULES từ env, import từng module, print version.
Exit code:
  0 — tất cả OK
  1 — có module fail import
  2 — config error
"""

from __future__ import annotations

import importlib
import importlib.util
import os
import sys


def check_module(name: str) -> tuple[bool, str]:
    """Trả về (ok, version_or_error)."""
    spec = importlib.util.find_spec(name)
    if spec is None:
        return False, "not found"
    try:
        mod = importlib.import_module(name)
        version = getattr(mod, "__version__", "(no __version__)")
        return True, str(version)
    except Exception as exc:  # noqa: BLE001
        return False, f"import error: {exc!r}"


def main() -> int:
    modules_env = os.environ.get("REUSE_CHECK_MODULES", "").strip()
    if not modules_env:
        # Default: chỉ check torch (nếu có)
        modules = ["torch"]
    else:
        modules = modules_env.split()

    print("=" * 47)
    print(" verify_env.py — module import check")
    print("=" * 47)
    print(f"Python : {sys.version.split()[0]}")
    print(f"Exec   : {sys.executable}")
    print()

    failed: list[tuple[str, str]] = []
    for name in modules:
        ok, info = check_module(name)
        marker = "OK  " if ok else "FAIL"
        print(f"  [{marker}] {name:<30s} {info}")
        if not ok:
            failed.append((name, info))

    print()
    if failed:
        print(f"[ERROR] {len(failed)} module(s) failed:")
        for name, info in failed:
            print(f"  - {name}: {info}")
        return 1

    print("[OK] All modules imported successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
