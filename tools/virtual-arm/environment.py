#!/usr/bin/env python3
"""Record immutable native guest build provenance for feature acceptance."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys


def sha256(path):
    """Hash a build artifact without loading it all into memory."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def source_digest(source):
    """Bind cache validity to builders, native helper and pinned configuration."""
    files = [source / name for name in (
        "Dockerfile", "build-environments.sh", "environment.py",
        "rootfs-manifest.py", "check-native-libraries.py", "sources.sha256", "dns-query.c")]
    files += list((source / "configs").glob("*.config"))
    files += list((source / "patches").glob("*.patch"))
    records = [{"path": path.relative_to(source).as_posix(),
                "sha256": sha256(path)} for path in sorted(files)]
    return hashlib.sha256(json.dumps(records, sort_keys=True,
                                    separators=(",", ":")).encode()).hexdigest()


def command_line(*arguments):
    """Capture one native host tool version line for provenance."""
    return subprocess.check_output(arguments, text=True).splitlines()[0]


def record(source, target, architecture, compiler, compiler_flags, deb_arch):
    """Publish provenance only after all requested native tools are installed."""
    spec = importlib.util.spec_from_file_location(
        "rootfs_manifest", source / "rootfs-manifest.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    native_packages = []
    for package in sorted((Path("/native-packages") / deb_arch).glob("*.deb")):
        name, version, package_arch = subprocess.check_output(
            ["dpkg-deb", "-f", str(package), "Package", "Version", "Architecture"],
            text=True).splitlines()
        # Multiple dpkg-deb fields have labels, unlike a single field.
        native_packages.append({"name": name.split(": ", 1)[-1],
                                "version": version.split(": ", 1)[-1],
                                "architecture": package_arch.split(": ", 1)[-1],
                                "deb_sha256": sha256(package)})
    profiles = {
        # The armv5 label is an archive/package compatibility name.  Its
        # validation guest models the older RT-AC68U Cortex-A9 (ARMv7) and
        # deliberately keeps the software-float armel user ABI.
        "armv5": {"machine": "vexpress-a9", "cpu": "cortex-a9", "cpu_options": "cortex-a9,vfp=off,neon=off",
                  "memory": 256, "guest_architecture": "armv7l",
                  "router_model": "ASUS RT-AC68U", "float_abi": "soft",
                  "fpu": "none", "target_architecture": "armv7"},
        "armv7": {"machine": "virt", "cpu": "cortex-a15", "cpu_options": "cortex-a15", "memory": 512,
                  "guest_architecture": "armv7l", "router_model": "newer ARMv7",
                  "float_abi": "hard", "fpu": "vfpv3-d16+neon", "target_architecture": "armv7"},
        "armv8": {"machine": "virt", "cpu": "cortex-a53", "cpu_options": "cortex-a53", "memory": 1024,
                  "guest_architecture": "aarch64", "router_model": "newer ARMv8",
                  "float_abi": "aapcs64", "fpu": "simd", "target_architecture": "aarch64"},
    }
    profile = profiles[architecture]
    machine, cpu, memory = profile["machine"], profile["cpu"], profile["memory"]
    native_paths = {
        "jq": "usr/bin/jq", "curl": "usr/sbin/curl",
        "dnsmasq": "usr/sbin/dnsmasq", "ip": "usr/sbin/ip",
        "flock": "usr/bin/flock", "timeout": "usr/bin/timeout",
        "gawk": "usr/bin/gawk", "openssl": "usr/sbin/openssl",
        "agh-dns-query": "usr/bin/agh-dns-query",
    }
    kernel_release = (target / "build-kernel/include/config/kernel.release").read_text().strip()
    rootfs_digest = module.rootfs_content_digest(target / "rootfs")
    environment = {
        "schema_version": 1,
        "architecture": architecture,
        "execution_class": "qemu-full-system-tcg",
        "machine": machine, "cpu": cpu, "ram_mb": memory,
        "cpu_options": profile["cpu_options"],
        "target": {"archive_architecture": architecture if architecture != "armv8" else "arm64",
                    "debian_architecture": deb_arch,
                    "cpu_architecture": profile["target_architecture"],
                    "float_abi": profile["float_abi"], "fpu": profile["fpu"],
                    "router_model": profile["router_model"],
                    "guest_uname": profile["guest_architecture"]},
        "console": "ttyAMA0", "kernel_release": kernel_release,
        "kernel_sha256": sha256(target / "kernel"),
        "busybox_version": "v1.25.1",
        "busybox_sha256": sha256(target / "rootfs/bin/busybox"),
        "rootfs_content_digest": rootfs_digest,
        "rootfs_manifest_sha256": rootfs_digest,
        "source_manifest_sha256": source_digest(source),
        "kernel": {
            "version": "6.1.157", "sha256": sha256(target / "kernel"),
            "source_sha256": "697fbaa207e5bf10750e02272fd5f32e1fe98a53b17a97d68cb4ccede50acbbc",
            "config_sha256": sha256(target / "build-kernel/.config"),
        },
        "busybox": {
            "version": "1.25.1", "sha256": sha256(target / "rootfs/bin/busybox"),
            "source_sha256": "ddd2f68c9d486bbc1b798b7587e581fb76456c9f4ca14e022bdbb0600e45fca9",
            "config_sha256": sha256(target / "build-busybox/.config"),
        },
        "compiler": {"target": compiler, "version": command_line(compiler + "gcc", "--version"),
                     "flags": compiler_flags,
                     "float_abi": profile["float_abi"]},
        "qemu_version": command_line("qemu-system-arm", "--version"),
        "native_packages": native_packages,
        "native_tools": {name: {"path": "/" + path,
                                "sha256": sha256(target / "rootfs" / path)}
                         for name, path in native_paths.items()},
    }
    if (target / "dtb").exists():
        environment["dtb_sha256"] = sha256(target / "dtb")
    temporary = target / "environment.json.new"
    temporary.write_text(json.dumps(environment, sort_keys=True, indent=2) + "\n")
    temporary.replace(target / "environment.json")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "source-digest":
        print(source_digest(Path(sys.argv[2])))
    elif len(sys.argv) == 8 and sys.argv[1] == "record":
        record(Path(sys.argv[2]), Path(sys.argv[3]), *sys.argv[4:])
    else:
        raise SystemExit("usage: environment.py source-digest SOURCE | record SOURCE TARGET ARCH COMPILER FLAGS DEB_ARCH")
