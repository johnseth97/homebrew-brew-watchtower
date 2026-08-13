#!/usr/bin/env python3
"""Verify that the Homebrew formula matches the deterministic release asset."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent


def fail(message: str) -> int:
    print(f"release verification failed: {message}", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-release.py VERSION", file=sys.stderr)
        return 2

    version = sys.argv[1]
    formula_path = ROOT / "Formula" / "brew-watchtower.rb"
    archive = ROOT / "dist" / f"brew-watchtower-{version}.tar.gz"

    if not formula_path.is_file():
        return fail(f"missing formula: {formula_path}")
    if not archive.is_file():
        return fail(f"missing archive: {archive}")

    formula = formula_path.read_text(encoding="utf-8")
    sha_match = re.search(r'^\s*sha256\s+"([0-9a-f]{64})"\s*$', formula, re.MULTILINE)
    url_match = re.search(r'^\s*url\s+"([^"]+)"\s*$', formula, re.MULTILINE)
    if not sha_match:
        return fail("formula does not contain exactly one valid SHA-256 declaration")
    if not url_match:
        return fail("formula does not contain exactly one URL declaration")

    expected_name = f"brew-watchtower-{version}.tar.gz"
    expected_tag = f"/v{version}/"
    formula_url = url_match.group(1)
    if not formula_url.endswith(f"/{expected_name}"):
        return fail(f"formula URL does not end with {expected_name}")
    if expected_tag not in formula_url:
        return fail(f"formula URL does not reference tag v{version}")

    formula_sha = sha_match.group(1)
    archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    if formula_sha != archive_sha:
        return fail(
            "formula SHA does not match rebuilt archive\n"
            f"  formula: {formula_sha}\n"
            f"  archive: {archive_sha}"
        )

    print(f"release verified: v{version} sha256={archive_sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
