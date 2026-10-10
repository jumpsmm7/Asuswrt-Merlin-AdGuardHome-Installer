#!/usr/bin/env python3
"""Fingerprint guest paths, modes, regular-file contents and symlink targets."""

import hashlib
import json
import os
from pathlib import Path
import stat
import sys


def rootfs_records(root):
    """Walk without following guest symlinks into the validation host."""
    root = Path(root)
    records = []
    for directory, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(directory) / name
            info = path.lstat()
            record = {
                "path": path.relative_to(root).as_posix(),
                "mode": stat.S_IMODE(info.st_mode),
            }
            if stat.S_ISLNK(info.st_mode):
                record.update(type="symlink", target=os.readlink(path))
            elif stat.S_ISDIR(info.st_mode):
                record.update(type="directory")
            elif stat.S_ISREG(info.st_mode):
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
                record.update(type="file", sha256=digest.hexdigest())
            else:
                raise ValueError(f"unsupported rootfs entry: {path}")
            records.append(record)
    return sorted(records, key=lambda record: record["path"])


def rootfs_content_digest(root):
    """Return the SHA-256 of the canonical complete rootfs record list."""
    encoded = (json.dumps(rootfs_records(root), sort_keys=True,
                          separators=(",", ":")) + "\n").encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: rootfs-manifest.py ROOTFS")
    print(rootfs_content_digest(sys.argv[1]))
