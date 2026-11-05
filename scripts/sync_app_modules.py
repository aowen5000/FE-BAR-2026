#!/usr/bin/env python3
"""
scripts/sync_app_modules.py

Copies fraud_triage_agent.py and lakebase_cases.py from the repo root into app/
and verifies byte-for-byte identity via SHA-256.

Run from the repo root:
    python scripts/sync_app_modules.py

The validation notebook (validation_notebooks/app_validation.ipynb) re-checks
the SHA-256 after deployment to confirm the deployed copies are identical.
"""

import hashlib
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_DIR   = REPO_ROOT / "app"
MODULES   = ["fraud_triage_agent.py", "lakebase_cases.py"]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    APP_DIR.mkdir(exist_ok=True)
    all_ok = True
    print(f"{'Module':<30}  {'SHA-256 (root)':<64}  {'Match'}")
    print("-" * 105)
    for name in MODULES:
        src  = REPO_ROOT / name
        dest = APP_DIR   / name
        if not src.exists():
            print(f"{name:<30}  MISSING at {src}")
            all_ok = False
            continue
        shutil.copy2(src, dest)
        h_src  = sha256(src)
        h_dest = sha256(dest)
        match  = h_src == h_dest
        tag    = "MATCH" if match else "MISMATCH"
        if not match:
            all_ok = False
        print(f"{name:<30}  {h_src}  {tag}")
    print()
    if all_ok:
        print("OK: app/ contains byte-identical copies of both modules.")
    else:
        raise SystemExit("ERROR: one or more modules did not copy correctly.")


if __name__ == "__main__":
    main()
