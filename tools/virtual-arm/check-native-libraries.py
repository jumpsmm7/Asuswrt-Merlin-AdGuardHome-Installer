#!/usr/bin/env python3
"""Reject incomplete foreign ELF rootfs libraries before booting a guest."""

from pathlib import Path, PurePosixPath
import subprocess
import sys


def guest_link_parts(path, remaining, original, followed):
    """Expand one guest link with a bounded hop count and no host resolution."""
    if followed > 40:
        raise ValueError(f"guest symlink cycle: {original}")
    destination = path.readlink().as_posix()
    return list(PurePosixPath(destination).parts) + remaining, destination.startswith("/")


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
            pending, absolute = guest_link_parts(candidate, pending, relative, followed)
            if absolute:
                resolved = []
        else:
            resolved.append(part)
    return root.joinpath(*resolved)


def dynamic_dependencies(text):
    """Extract NEEDED bracket values using linear per-line delimiter parsing."""
    for line in text.splitlines():
        _, marker, tail = line.partition("(NEEDED)")
        if not marker:
            continue
        _, opening, tail = tail.partition("[")
        value, closing, _ = tail.partition("]")
        if opening and closing:
            yield value


def program_interpreters(text):
    """Extract program interpreter values without regex backtracking."""
    for line in text.splitlines():
        _, marker, tail = line.partition("Requesting program interpreter: ")
        value, closing, _ = tail.partition("]")
        if marker and closing:
            yield value


def missing_dependencies(root, path, names):
    """Return unresolved libraries and interpreters for one regular ELF file."""
    with path.open("rb") as stream:
        if stream.read(4) != b"\x7fELF":
            return []
    dynamic = subprocess.check_output(["readelf", "-d", str(path)], text=True)
    missing = [f"{path.relative_to(root)} needs {library}"
               for library in dynamic_dependencies(dynamic) if library not in names]
    headers = subprocess.check_output(["readelf", "-l", str(path)], text=True)
    missing.extend(f"{path.relative_to(root)} needs interpreter {interpreter}"
                   for interpreter in program_interpreters(headers)
                   if not guest_file(root, interpreter).is_file())
    return missing


def check(root):
    """Check every installed native ELF dependency and its interpreter."""
    paths = list(root.rglob("*"))
    names = {path.name for path in paths
             if guest_file(root, path.relative_to(root)).is_file()}
    missing = []
    for path in paths:
        if path.is_symlink() or not path.is_file():
            continue
        missing.extend(missing_dependencies(root, path, names))
    if missing:
        raise SystemExit("incomplete native libraries:\n" + "\n".join(missing))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-native-libraries.py ROOTFS")
    check(Path(sys.argv[1]))
