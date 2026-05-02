#!/usr/bin/env python3
"""CI-safe wrapper for apply-installer-hardening.py.

The original helper uses pathlib read/write helpers with a newline argument that
is not supported on every GitHub Actions Python runtime. This wrapper imports the
existing hardening rules but performs file I/O with built-in open().
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "installer"
HELPER = ROOT / "tools" / "apply-installer-hardening.py"


def main() -> int:
    if not INSTALLER.exists():
        print("Error: installer file not found", file=sys.stderr)
        return 1

    spec = importlib.util.spec_from_file_location("apply_installer_hardening", HELPER)
    if spec is None or spec.loader is None:
        print("Error: could not load apply-installer-hardening.py", file=sys.stderr)
        return 1

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    with INSTALLER.open("r", encoding="utf-8", newline="") as fh:
        original = fh.read()

    updated, changes = module.harden_installer(original)

    if changes == 0:
        print("No installer changes were needed.")
        return 0

    with INSTALLER.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(updated)

    print(f"Applied {changes} installer hardening change(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
