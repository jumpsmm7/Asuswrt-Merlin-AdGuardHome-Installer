#!/usr/bin/env python3
"""Reject incomplete foreign ELF rootfs libraries before booting a guest."""

from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def guest_file(root, relative):
    """Resolve absolute and relative guest symlinks without visiting the host."""
    pending = list(PurePosixPath(relative).parts)
    resolved = []
    followed = 0
    while pending:
        part = pending.pop(0)
        if part in ("", "/", "."):
            continue
        if part == "..":
            if not resolved:
                raise ValueError(f"guest symlink escapes root: {relative}")
            resolved.pop()
            continue
        candidate = root.joinpath(*resolved, part)
        if candidate.is_symlink():
            followed += 1
            if followed > 40:
                raise ValueError(f"guest symlink cycle: {relative}")
            destination = candidate.readlink().as_posix()
            if destination.startswith("/"):
                resolved = []
            pending = list(PurePosixPath(destination).parts) + pending
        else:
            resolved.append(part)
    return root.joinpath(*resolved)


def check(root):
    """Check every installed native ELF dependency and its interpreter."""
    paths = list(root.rglob("*"))
    names = {path.name for path in paths
             if guest_file(root, path.relative_to(root)).is_file()}
    missing = []
    for path in paths:
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        dynamic = subprocess.check_output(["readelf", "-d", str(path)], text=True)
        for library in re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic):
            if library not in names:
                missing.append(f"{path.relative_to(root)} needs {library}")
        headers = subprocess.check_output(["readelf", "-l", str(path)], text=True)
        for interpreter in re.findall(r"Requesting program interpreter: (.*?)\]", headers):
            target = guest_file(root, interpreter)
            if not target.is_file():
                missing.append(f"{path.relative_to(root)} needs interpreter {interpreter}")
    if missing:
        raise SystemExit("incomplete native libraries:\n" + "\n".join(missing))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-native-libraries.py ROOTFS")
    check(Path(sys.argv[1]))
