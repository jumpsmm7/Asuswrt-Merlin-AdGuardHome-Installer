#!/usr/bin/env python3
"""Assemble disposable initramfs payloads and record complete QEMU feature results."""

import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import shutil
import stat
import subprocess
import sys
import threading
import time


# The directory/archive names are product download targets, not CPU claims.
# In particular, the armv5 archive is the compatibility package selected for
# older RT-AC68U-class routers.  The router CPU is ARMv7 Cortex-A9, but the
# package and the guest toolchain intentionally use the software-float armel
# ABI.  Keep these identities separate so an armv5 archive can never silently
# turn into an ARMv5 CPU acceptance claim.
MACHINES = {
    "armv5": ("qemu-system-arm", "vexpress-a9", "cortex-a9", "256", "armv7l"),
    "armv7": ("qemu-system-arm", "virt", "cortex-a15", "512", "armv7l"),
    "armv8": ("qemu-system-aarch64", "virt", "cortex-a53", "1024", "aarch64"),
}
CPU_OPTIONS = {
    "armv5": "cortex-a9,vfp=off,neon=off",
    "armv7": "cortex-a15",
    "armv8": "cortex-a53",
}
TARGETS = {
    "armv5": {
        "archive_architecture": "armv5",
        "debian_architecture": "armel",
        "cpu_architecture": "armv7",
        "float_abi": "soft",
        "fpu": "none",
        "router_model": "ASUS RT-AC68U",
        "guest_uname": "armv7l",
    },
    "armv7": {
        "archive_architecture": "armv7",
        "debian_architecture": "armhf",
        "cpu_architecture": "armv7",
        "float_abi": "hard",
        "fpu": "vfpv3-d16+neon",
        "router_model": "newer ARMv7",
        "guest_uname": "armv7l",
    },
    "armv8": {
        "archive_architecture": "arm64",
        "debian_architecture": "arm64",
        "cpu_architecture": "aarch64",
        "float_abi": "aapcs64",
        "fpu": "simd",
        "router_model": "newer ARMv8",
        "guest_uname": "aarch64",
    },
}
RUNTIME_FILES = ("installer", "AdGuardHome.sh", "S99AdGuardHome", "rc.func.AdGuardHome")


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def digest_file(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def checked_output(command):
    return subprocess.check_output(command, text=True).strip()


def atomic_json(path, value):
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def verify_cached_environment(repository, cache, environment, architecture):
    """Reject modified/stale kernels, userlands and build inputs before booting them."""
    _, machine, cpu, memory, _ = MACHINES[architecture]
    if (environment.get("architecture"), environment.get("machine"), environment.get("cpu"), environment.get("ram_mb")) != (architecture, machine, cpu, int(memory)):
        raise ValueError("Cached environment does not match the requested ARM CPU/memory")
    if environment.get("target") != TARGETS[architecture] or environment.get("cpu_options") != CPU_OPTIONS[architecture]:
        raise ValueError("Cached environment does not match the requested package ABI/CPU feature contract")
    if environment.get("execution_class") != "qemu-full-system-tcg" or environment.get("busybox_version") != "v1.25.1":
        raise ValueError("Cached environment is not the pinned native full-system BusyBox environment")
    for path, field in ((cache / "kernel", "kernel_sha256"), (cache / "rootfs/bin/busybox", "busybox_sha256")):
        if path.is_symlink() or digest_file(path) != environment.get(field):
            raise ValueError(f"Cached artifact digest mismatch: {path}")
    if architecture == "armv5":
        if not environment.get("dtb_sha256"):
            raise ValueError("ARMv5 compatibility guest requires a device tree digest")
        if (cache / "dtb").is_symlink() or not (cache / "dtb").is_file() or digest_file(cache / "dtb") != environment.get("dtb_sha256"):
            raise ValueError("Cached device tree digest mismatch")
    elif environment.get("dtb_sha256") or (cache / "dtb").exists():
        raise ValueError("Unexpected device tree for the selected virtual machine")
    rootfs_digest = checked_output([sys.executable, str(repository / "tools/virtual-arm/rootfs-manifest.py"), str(cache / "rootfs")])
    if rootfs_digest != environment.get("rootfs_content_digest"):
        raise ValueError("Cached native root filesystem was modified")
    source_digest = checked_output([sys.executable, str(repository / "tools/virtual-arm/environment.py"), "source-digest", str(repository / "tools/virtual-arm")])
    if source_digest != environment.get("source_manifest_sha256"):
        raise ValueError("Cached environment was built from stale source/configuration inputs")


def add_cpio(stream, number, name, mode, data=b""):
    """Write deterministic newc records without needing host root or device access."""
    encoded_name = name.encode() + b"\0"
    fields = (number, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded_name), 0)
    header = b"070701" + b"".join(f"{value:08x}".encode() for value in fields)
    stream.write(header + encoded_name)
    stream.write(b"\0" * (-(len(header) + len(encoded_name)) % 4))
    stream.write(data)
    stream.write(b"\0" * (-len(data) % 4))


def source_payload(repository, rows, architecture):
    """Include runtime, selected fixture dependencies and this CPU's release archives."""
    selected = set(RUNTIME_FILES)
    selected.update(row[2] for row in rows)
    pending = list(selected)
    while pending:
        relative = pending.pop()
        path = repository / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing or unsafe payload file: {relative}")
        text = path.read_text(errors="replace")
        for dependency in re.findall(r"(?:tests|tools)/[A-Za-z0-9_./-]+\.sh", text):
            if dependency not in selected and (repository / dependency).is_file():
                selected.add(dependency)
                pending.append(dependency)
    for runtime in RUNTIME_FILES:
        for suffix in (".md5sum", ".sha256sum"):
            if (repository / (runtime + suffix)).is_file():
                selected.add(runtime + suffix)
    # The secure-download regression checks the repository's documented TLS
    # policy. Include that policy input in the immutable guest payload.
    if any(row[2] == "tests/installer-secure-download-fallback.sh" for row in rows):
        selected.add("README.md")
    if any(row[2] == "tests/virtual-arm-native.sh" for row in rows):
        selected.update("tools/virtual-arm/native/" + name for name in ("nvram", "service", "cru", "get_mtlan"))
        archives = sorted((repository / architecture).glob("*.tar.gz"))
        if not archives:
            raise ValueError(f"No native AdGuardHome archives for {architecture}")
        for archive in archives:
            selected.add(archive.relative_to(repository).as_posix())
            for suffix in (".md5sum", ".sha256sum"):
                selected.add(archive.relative_to(repository).as_posix() + suffix)
    fixtures = repository / "tests/fixtures"
    if fixtures.is_dir():
        selected.update(path.relative_to(repository).as_posix() for path in fixtures.rglob("*") if path.is_file())
    return selected


def build_initramfs(repository, cache, output, rows, architecture, configuration, selection):
    entries = {}
    rootfs = cache / "rootfs"
    if not rootfs.is_dir():
        raise ValueError(f"Guest root filesystem is missing: {rootfs}")
    for path in sorted(rootfs.rglob("*")):
        name = path.relative_to(rootfs).as_posix()
        metadata = path.lstat()
        if stat.S_ISREG(metadata.st_mode):
            entries[name] = (metadata.st_mode, path.read_bytes())
        elif stat.S_ISDIR(metadata.st_mode):
            entries[name] = (metadata.st_mode, b"")
        elif stat.S_ISLNK(metadata.st_mode):
            entries[name] = (metadata.st_mode, os.readlink(path).encode())
        else:
            raise ValueError(f"Guest rootfs contains unsupported special file: {path}")
    for relative in source_payload(repository, rows, architecture):
        source = repository / relative
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Missing or unsafe payload file: {relative}")
        entries["repo/" + relative] = (stat.S_IFREG | (source.stat().st_mode & 0o777), source.read_bytes())
    entries["init"] = (stat.S_IFREG | 0o755, (repository / "tools/virtual-arm/guest-init.sh").read_bytes())
    entries["usr/lib/agh-virtual-arm/guest-runner.sh"] = (stat.S_IFREG | 0o755, (repository / "tools/virtual-arm/guest-runner.sh").read_bytes())
    entries["etc/agh-virtual-arm.conf"] = (stat.S_IFREG | 0o600, configuration.encode())
    entries["etc/agh-virtual-arm-selection.tsv"] = (stat.S_IFREG | 0o444, selection)
    entries["etc/inittab"] = (stat.S_IFREG | 0o644, b"::once:/bin/sh /usr/lib/agh-virtual-arm/guest-runner.sh\n")
    for name in list(entries):
        parent = Path(name).parent
        while parent.as_posix() != ".":
            entries.setdefault(parent.as_posix(), (stat.S_IFDIR | 0o755, b""))
            parent = parent.parent
    with output.open("wb") as destination:
        with gzip.GzipFile(fileobj=destination, mode="wb", mtime=0) as compressed:
            for number, (name, (mode, data)) in enumerate(sorted(entries.items()), 1):
                add_cpio(compressed, number, name, mode, data)
            add_cpio(compressed, len(entries) + 1, "TRAILER!!!", 0)


def qemu_command(architecture, cache, initramfs, token):
    executable, machine, _, memory, _ = MACHINES[architecture]
    arguments = [executable, "-machine", machine, "-cpu", CPU_OPTIONS[architecture], "-m", memory,
                 "-accel", "tcg", "-nographic", "-monitor", "none", "-nic", "none",
                 "-no-reboot", "-kernel", str(cache / "kernel"), "-initrd", str(initramfs),
                 "-append", "console=ttyAMA0 rdinit=/init panic=-1"]
    if (cache / "dtb").is_file():
        arguments.extend(["-dtb", str(cache / "dtb")])
    if shutil.which(executable):
        return arguments
    if not shutil.which("docker"):
        raise ValueError(f"{executable} or Docker is required for full-system ARM execution")
    image = os.environ.get("AGH_VIRTUAL_ARM_TOOLS_IMAGE", "agh-virtual-arm-builder:v1")
    return ["docker", "run", "--rm", "--init", "--name", "agh-virtual-arm-" + token, "--network", "none", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--user", f"{os.getuid()}:{os.getgid()}",
            "--read-only", "--tmpfs", "/tmp:rw,nosuid,nodev,size=32m",
            "--mount", f"type=bind,src={cache},dst={cache},readonly",
            "--mount", f"type=bind,src={initramfs.parent},dst={initramfs.parent},readonly",
            image, *arguments]


def run_guest(command, directory, rows, token, boot_seconds, scenario_seconds, expected_architecture, scenario_grace_seconds=30):
    """Require a real boot, ordered scenario endpoints and the guest completion record."""
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    messages = queue.Queue()

    def read_output():
        for line in iter(process.stdout.readline, b""):
            messages.put(line)
        messages.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    boot = {"status": "fail"}
    native_tools = {}
    results = []
    current = None
    scenario_started = None
    endpoint_recorded = None
    done = False
    error = "Guest exited without complete evidence"
    limit = boot_seconds + (scenario_seconds + 30) * len(rows)
    serial_path = directory / "serial.log"
    try:
        with serial_path.open("wb") as serial:
            while True:
                elapsed = time.monotonic() - started
                if elapsed > limit or (boot["status"] != "pass" and elapsed > boot_seconds):
                    error = "Whole-guest timeout" if boot["status"] == "pass" else "Guest boot timeout"
                    break
                if current is not None and time.monotonic() - scenario_started > scenario_seconds + scenario_grace_seconds:
                    error = "Guest scenario timeout: " + current["scenario"]
                    break
                if current is None and endpoint_recorded is not None and time.monotonic() - endpoint_recorded > max(1, scenario_grace_seconds):
                    error = "Guest scenario start/completion timeout"
                    break
                try:
                    line = messages.get(timeout=1)
                except queue.Empty:
                    continue
                if line is None:
                    break
                serial.write(line)
                serial.flush()
                decoded = line.decode(errors="replace").rstrip("\r\n")
                fields = decoded.split("\t")
                if len(fields) < 3 or fields[:2] != ["AGH_VM", token]:
                    if fields[0] == "NATIVE_TOOL" and len(fields) == 3:
                        native_tools[fields[1]] = fields[2]
                    if current is not None:
                        current["stream"].write(line)
                    if current is not None or decoded.startswith("NATIVE_TOOL") or re.search(r"FAIL:|Kernel panic|Out of memory|not syncing|can't execute", decoded):
                        print(decoded, flush=True)
                    continue
                kind = fields[2]
                if kind == "BOOT" and len(fields) == 10 and boot["status"] != "pass":
                    if fields[3] != expected_architecture or fields[4] != MACHINES[expected_architecture][4] or fields[6] != "v1.25.1":
                        error = "Guest architecture or BusyBox version does not match the requested environment"
                        break
                    boot = {"status": "pass", "architecture": fields[3], "reported_architecture": fields[3], "machine": fields[4],
                            "kernel_release": fields[5], "busybox_version": fields[6].removeprefix("v"),
                            "environment_digest": fields[7], "cpu_features": fields[8],
                            "token": token, "native_tools": native_tools}
                    endpoint_recorded = time.monotonic()
                    print(f"{expected_architecture}: booted {fields[4]}, Linux {fields[5]}, BusyBox {fields[6]}", flush=True)
                elif kind == "START" and len(fields) == 6 and boot["status"] == "pass" and current is None:
                    index = len(results)
                    if index >= len(rows) or fields[3:5] != rows[index][:2]:
                        error = "Guest scenario ordering does not match the exact selection"
                        break
                    scenario_log = directory / (fields[4] + ".log")
                    current = {"feature": fields[3], "scenario": fields[4], "test": rows[index][2],
                               "log": scenario_log.name, "stream": scenario_log.open("wb")}
                    scenario_started = time.monotonic()
                    print(f"{expected_architecture}: {fields[3]}/{fields[4]}", flush=True)
                elif kind == "END" and len(fields) == 8 and current is not None and fields[3:5] == [current["feature"], current["scenario"]]:
                    current.pop("stream").close()
                    current.update(exit_status=int(fields[5]), elapsed_seconds=int(fields[6]),
                                   status="pass" if fields[5] == "0" else "fail")
                    current["log_sha256"] = digest_file(directory / current["log"])
                    results.append(current)
                    print(f"{expected_architecture}: {current['scenario']} {current['status']} (exit {current['exit_status']})", flush=True)
                    current = None
                    scenario_started = None
                    endpoint_recorded = time.monotonic()
                elif kind == "DONE" and len(fields) == 5 and current is None and len(results) == len(rows):
                    done = True
                    error = "" if fields[3] == "0" and all(row["status"] == "pass" for row in results) else "One or more guest scenarios failed"
                    break
                elif kind == "ERROR" and len(fields) in (5, 6):
                    error = f"Native guest tool failed before boot acceptance: {fields[3]} (exit {fields[4]})"
                    break
                else:
                    error = "Malformed or unexpected guest result marker"
                    break
    finally:
        if current is not None:
            current.pop("stream").close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
        process.wait()
        if command[:2] == ["docker", "run"]:
            container = command[command.index("--name") + 1]
            subprocess.run(["docker", "rm", "-f", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)
        reader.join(timeout=2)
        process.stdout.close()
    if error:
        print(f"{expected_architecture}: {error}; full serial log: {serial_path}", file=sys.stderr, flush=True)
        if boot["status"] != "pass":
            for line in serial_path.read_text(errors="replace").splitlines()[-30:]:
                print(f"{expected_architecture}: {line}", file=sys.stderr, flush=True)
    return boot, results, done, error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--features", required=True)
    parser.add_argument("--architectures", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--defer-acceptance", choices=("0", "1"), default="0")
    options = parser.parse_args()
    repository, output, cache = (path.resolve() for path in (options.repository, options.output, options.cache))
    architectures = list(MACHINES) if options.architectures == "all" else options.architectures.split(",")
    if not architectures or len(set(architectures)) != len(architectures) or any(architecture not in MACHINES for architecture in architectures):
        parser.error("Architectures must be a nonempty, unique selection from armv5,armv7,armv8")
    output.mkdir(parents=True, exist_ok=True)
    (output / "acceptance.json").unlink(missing_ok=True)
    checker = repository / "tools/virtual-arm/check-evidence.py"
    manifest = repository / "tools/virtual-arm/features.tsv"
    selection = subprocess.check_output([sys.executable, str(checker), "--select", "--features", options.features, "--manifest", str(manifest)])
    rows = [line.split("\t") for line in selection.decode().splitlines()]
    if not rows or any(len(row) != 3 for row in rows):
        raise ValueError("The feature selection contains no executable scenarios")
    features = list(dict.fromkeys(row[0] for row in rows)) if options.features == "all" else options.features.split(",")
    content_digest = checked_output([sys.executable, str(checker), "--content-digest", "--repository", str(repository)])
    metadata = {}
    for line in manifest.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 5 and fields[0] != "feature":
            metadata[(fields[0], fields[1])] = fields
    try:
        commit_label = checked_output(["git", "-C", str(repository), "rev-parse", "HEAD"])
        dirty = bool(checked_output(["git", "-C", str(repository), "status", "--porcelain"]))
    except (FileNotFoundError, subprocess.CalledProcessError):
        commit_label, dirty = "unversioned", True
    scenario_seconds = int(os.environ.get("AGH_VIRTUAL_ARM_SCENARIO_TIMEOUT", "900"))
    boot_seconds = int(os.environ.get("AGH_VIRTUAL_ARM_BOOT_TIMEOUT", "180"))
    if not 1 <= scenario_seconds <= 7200 or not 1 <= boot_seconds <= 1800:
        raise ValueError("Virtual-only timeout budgets must be positive and bounded")
    (output / "selection.tsv").write_bytes(selection)
    evidence_paths = []
    failed = False
    for architecture in architectures:
        directory = output / architecture
        directory.mkdir(exist_ok=True)
        evidence_path = directory / "evidence.json"
        evidence_path.unlink(missing_ok=True)
        (directory / "serial.log").unlink(missing_ok=True)
        token = secrets.token_hex(16)
        environment_path = cache / architecture / "environment.json"
        evidence = {"schema_version": 1, "architecture": architecture, "content_digest": content_digest,
                    "commit_label": commit_label, "source_dirty": dirty, "requested_features": features,
                    "selection_digest": digest_bytes(selection), "started_at": timestamp(), "environment": {},
                    "guest_boot": {"status": "fail"}, "results": [], "status": "fail",
                    "execution": {"engine": "qemu-system-tcg", "network": "none", "source_read_only": True,
                                  "boot_timeout_seconds": boot_seconds, "scenario_timeout_seconds": scenario_seconds}}
        try:
            environment_raw = environment_path.read_bytes()
            environment = json.loads(environment_raw)
            environment_digest = digest_bytes(environment_raw)
            evidence.update(environment=environment, environment_digest=environment_digest)
            (directory / "environment.json").write_bytes(environment_raw)
            verify_cached_environment(repository, cache / architecture, environment, architecture)
            configuration = f"ARCHITECTURE='{architecture}'\nRUN_TOKEN='{token}'\nENVIRONMENT_DIGEST='{environment_digest}'\nCONTENT_DIGEST='{content_digest}'\nSCENARIO_TIMEOUT_SECONDS='{scenario_seconds}'\n"
            initramfs = directory / "initramfs.cpio.gz"
            build_initramfs(repository, cache / architecture, initramfs, rows, architecture, configuration, selection)
            evidence["execution"]["initramfs_sha256"] = digest_file(initramfs)
            command = qemu_command(architecture, cache / architecture, initramfs, token)
            evidence["execution"]["command"] = command
            executable = MACHINES[architecture][0]
            executable_index = len(command) - len(command[command.index(executable):])
            actual_qemu_version = checked_output(command[:executable_index + 1] + ["--version"]).splitlines()[0]
            if actual_qemu_version != environment.get("qemu_version"):
                raise ValueError("QEMU version differs from the recorded native environment")
            evidence["execution"]["qemu_version"] = actual_qemu_version
            boot, results, done, error = run_guest(command, directory, rows, token, boot_seconds, scenario_seconds, architecture)
            for result in results:
                fields = metadata[(result["feature"], result["scenario"])]
                result.update(evidence_class=fields[3], assertions=fields[4], source_sha256=digest_file(repository / result["test"]))
            evidence.update(guest_boot=boot, results=results, guest_complete=done, error=error,
                            status="pass" if done and not error else "fail")
            verify_cached_environment(repository, cache / architecture, environment, architecture)
        except (OSError, ValueError, subprocess.CalledProcessError) as exception:
            evidence.update(status="fail", error=str(exception))
            print(f"{architecture}: {exception}", file=sys.stderr, flush=True)
        serial_path = directory / "serial.log"
        if serial_path.is_file():
            evidence["execution"].update(serial_log=serial_path.name, serial_log_sha256=digest_file(serial_path))
        fresh_digest = checked_output([sys.executable, str(checker), "--content-digest", "--repository", str(repository)])
        if fresh_digest != content_digest:
            evidence.update(status="fail", error="Tested source changed while the virtual matrix was executing")
        evidence["finished_at"] = timestamp()
        (directory / "initramfs.cpio.gz").unlink(missing_ok=True)
        atomic_json(evidence_path, evidence)
        evidence_paths.append(str(evidence_path))
        failed = failed or evidence["status"] != "pass"
    verify_command = [sys.executable, str(checker), "--repository", str(repository), "--manifest", str(manifest),
                      "--features", options.features, "--architectures", options.architectures,
                      "--summary", str(output / "acceptance.json")]
    if options.defer_acceptance == "1":
        verify_command.append("--partial")
    acceptance = subprocess.call([*verify_command, *evidence_paths])
    return 1 if failed else acceptance


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exception:
        print(f"Virtual ARM execution failed: {exception}", file=sys.stderr)
        sys.exit(1)
