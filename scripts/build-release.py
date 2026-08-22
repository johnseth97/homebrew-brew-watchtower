#!/usr/bin/env python3
"""Build a deterministic release archive for the Homebrew formula."""

from __future__ import annotations

import gzip
import hashlib
import io
from pathlib import Path
import sys
import tarfile


ROOT = Path(__file__).resolve().parent.parent
STATIC_FILES = (
    ("bin/brew-watchtower", 0o755),
    ("completions/brew-watchtower.bash", 0o644),
    ("completions/_brew-watchtower", 0o644),
    ("man/brew-watchtower.1", 0o644),
    ("LICENSE", 0o644),
)


def lib_files() -> tuple[tuple[str, int], ...]:
    # Derived from disk rather than hardcoded: bin/brew-watchtower sources
    # every lib/*.sh module unconditionally, so a hardcoded subset here
    # silently drops one out of the release tarball whenever a module is
    # added (that's exactly how v0.10.1 shipped without lib/brewfile.sh).
    return tuple(
        (f"lib/{path.name}", 0o644)
        for path in sorted((ROOT / "lib").glob("*.sh"))
    )


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].replace(".", "").isdigit():
        print("usage: build-release.py VERSION", file=sys.stderr)
        return 2

    version = sys.argv[1]
    prefix = f"brew-watchtower-{version}"
    output_dir = ROOT / "dist"
    output_dir.mkdir(exist_ok=True)
    output = output_dir / f"{prefix}.tar.gz"

    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for relative, mode in STATIC_FILES + lib_files():
            source = ROOT / relative
            data = source.read_bytes()
            info = tarfile.TarInfo(f"{prefix}/{relative}")
            info.size = len(data)
            info.mode = mode
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "wheel"
            archive.addfile(info, io.BytesIO(data))

    with output.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            compressed.write(tar_buffer.getvalue())

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (output.with_suffix(output.suffix + ".sha256")).write_text(
        f"{digest}  {output.name}\n", encoding="utf-8"
    )
    print(output)
    print(digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
