#!/usr/bin/env python3
"""Reject missing, incomplete or foreign OSV 2.3.8 JSON before its permissive reporter."""

import json
from pathlib import Path
import sys


def require(condition, message):
    """Reject an output that cannot represent a completed pinned-scanner result."""
    if not condition:
        raise ValueError(message)


def validate_licenses(config):
    """Check the license configuration emitted even when the scan finds no packages."""
    require(isinstance(config, dict) and isinstance(config.get("licenses"), dict),
            "invalid experimental configuration")
    licenses = config["licenses"]
    require(isinstance(licenses.get("summary"), bool), "invalid license summary flag")
    require("allowlist" in licenses and (licenses["allowlist"] is None or
            (isinstance(licenses["allowlist"], list) and
             all(isinstance(value, str) for value in licenses["allowlist"]))),
            "invalid license allowlist")


def validate_group(group):
    """Return the IDs that the pinned reporter may safely use to locate vulnerability groups."""
    require(isinstance(group, dict) and isinstance(group.get("ids"), list) and
            all(isinstance(value, str) and value for value in group["ids"]),
            "invalid vulnerability group")
    return group["ids"]


def validate_package(package):
    """Check package identity and require a valid group for every reported vulnerability."""
    require(isinstance(package, dict) and isinstance(package.get("package"), dict),
            "invalid package entry")
    identity = package["package"]
    require(all(isinstance(identity.get(key), str) for key in ("name", "version", "ecosystem")),
            "invalid package identity")
    vulnerabilities = package.get("vulnerabilities", [])
    groups = package.get("groups", [])
    require(isinstance(vulnerabilities, list) and isinstance(groups, list),
            "invalid vulnerability collection")
    group_ids = set()
    for group in groups:
        group_ids.update(validate_group(group))
    for vulnerability in vulnerabilities:
        require(isinstance(vulnerability, dict) and isinstance(vulnerability.get("id"), str) and
                vulnerability["id"] in group_ids, "ungrouped or invalid vulnerability")


def validate_source(source):
    """Check the scanned source and its collection of packages."""
    require(isinstance(source, dict), "invalid source entry")
    info = source.get("source")
    require(isinstance(info, dict) and isinstance(info.get("path"), str) and info["path"] and
            isinstance(info.get("type"), str) and info["type"], "invalid source identity")
    require("packages" in source and (source["packages"] is None or
            isinstance(source["packages"], list)), "invalid package collection")
    for package in source["packages"] or []:
        validate_package(package)


def validate(path):
    """Validate the source-scan result model while accepting genuine zero-package scans."""
    require(path.is_file() and not path.is_symlink(), "result must be a regular file")
    with path.open(encoding="utf-8") as result:
        data = json.load(result)
    require(isinstance(data, dict), "result must be a JSON object")
    require("results" in data and "experimental_config" in data, "missing OSV result fields")
    require(not (set(data) - {"results", "experimental_config", "experimental_generic_findings",
                             "image_metadata", "license_summary"}), "unexpected result fields")
    validate_licenses(data["experimental_config"])
    sources = data["results"]
    require(sources is None or isinstance(sources, list), "results must be an array or null")
    for source in sources or []:
        validate_source(source)


def main():
    """Check exactly one freshly generated file and fail before reporting on any defect."""
    if len(sys.argv) != 2:
        print("Usage: check-osv-results.py RESULT.json", file=sys.stderr)
        return 2
    try:
        validate(Path(sys.argv[1]))
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError) as error:
        print(f"Error: invalid OSV scan result: {error}", file=sys.stderr)
        return 1
    print("OSV result JSON is complete and structurally valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
