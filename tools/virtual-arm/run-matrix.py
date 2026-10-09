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
SERIAL_LOG = "serial.log"
IDENTIFIER = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")


def digest_bytes(value):
    """Return the lowercase SHA-256 digest of the provided bytes."""
    return hashlib.sha256(value).hexdigest()


def digest_file(path):
    """Return a file's SHA-256 digest without loading it all into memory."""
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def timestamp():
    """Return the current timezone-aware UTC timestamp in ISO 8601 format."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def checked_output(command):
    """Run a command and return stripped stdout, propagating execution failures."""
    return subprocess.check_output(command, text=True).strip()


def atomic_json(path, value):
    """Publish sorted JSON through a sibling staging file and atomic replacement."""
    temporary = path.with_name(path.name + ".new")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def verify_device_tree(cache, environment, architecture):
    """Require the legacy guest's pinned DTB and reject DTBs on other machines."""
    device_tree = cache / "dtb"
    if architecture != "armv5":
        if environment.get("dtb_sha256") or device_tree.exists():
            raise ValueError("Unexpected device tree for the selected virtual machine")
        return
    if not environment.get("dtb_sha256"):
        raise ValueError("ARMv5 compatibility guest requires a device tree digest")
    if device_tree.is_symlink() or not device_tree.is_file() or digest_file(device_tree) != environment["dtb_sha256"]:
        raise ValueError("Cached device tree digest mismatch")


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
    verify_device_tree(cache, environment, architecture)
    rootfs_digest = checked_output([sys.executable, str(repository / "tools/virtual-arm/rootfs-manifest.py"), str(cache / "rootfs")])
    if rootfs_digest != environment.get("rootfs_content_digest"):
        raise ValueError("Cached native root filesystem was modified")
    source_digest = checked_output([sys.executable, str(repository / "tools/virtual-arm/environment.py"), "source-digest", str(repository / "tools/virtual-arm")])
    if source_digest != environment.get("source_manifest_sha256"):
        raise ValueError("Cached environment was built from stale source/configuration inputs")


def relative_name(value):
    """Reject absolute, noncanonical and control-bearing archive/payload names."""
    if not isinstance(value, str) or not value or value.startswith("/"):
        raise ValueError(f"Unsafe payload/archive name: {value!r}")
    if any(part in ("", ".", "..") for part in value.split("/")):
        raise ValueError(f"Unsafe payload/archive name: {value!r}")
    if "\\" in value or any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError(f"Unsafe payload/archive name: {value!r}")
    return value


def payload_file(repository, relative, required=True):
    """Confine a regular payload file to the repository before inspecting bytes."""
    root = repository.resolve()
    candidate = root / relative_name(relative)
    if candidate.resolve() != candidate:
        raise ValueError(f"Missing or unsafe payload file: {relative}")
    if not candidate.is_file():
        if required:
            raise ValueError(f"Missing or unsafe payload file: {relative}")
        return None
    return candidate


def read_payload(repository, relative):
    """Read repository bytes through nonfollowing directory descriptors."""
    payload_file(repository, relative)
    parts = relative.split("/")
    directory = os.open(repository.resolve(), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as source:
            metadata = os.fstat(source.fileno())
            if not stat.S_ISREG(metadata.st_mode):
                raise ValueError(f"Missing or unsafe payload file: {relative}")
            return metadata.st_mode, source.read()
    finally:
        os.close(directory)


def add_cpio(stream, number, name, mode, data=b""):
    """Write deterministic newc records without needing host root or device access."""
    encoded_name = relative_name(name).encode() + b"\0"
    fields = (number, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(encoded_name), 0)
    header = b"070701" + b"".join(f"{value:08x}".encode() for value in fields)
    stream.write(header + encoded_name)
    stream.write(b"\0" * (-(len(header) + len(encoded_name)) % 4))
    stream.write(data)
    stream.write(b"\0" * (-len(data) % 4))


def dependency_payload(repository, selected):
    """Discover shell dependencies only after canonical repository confinement."""
    pending = list(selected)
    while pending:
        relative = pending.pop()
        _, content = read_payload(repository, relative)
        for dependency in re.findall(r"(?:tests|tools)/[A-Za-z0-9_./-]+\.sh", content.decode(errors="replace")):
            source = payload_file(repository, dependency, required=False)
            if source is not None and dependency not in selected:
                selected.add(dependency)
                pending.append(dependency)


def native_payload(repository, architecture):
    """Select the requested package archive, checksums and firmware model tools."""
    selected = {"tools/virtual-arm/native/" + name for name in ("nvram", "service", "cru", "get_mtlan")}
    archives = sorted((repository / architecture).glob("*.tar.gz"))
    if not archives:
        raise ValueError(f"No native AdGuardHome archives for {architecture}")
    for archive in archives:
        relative = archive.relative_to(repository).as_posix()
        selected.update((relative, relative + ".md5sum", relative + ".sha256sum"))
    return selected


def source_payload(repository, rows, architecture):
    """Include confined runtime, selected dependencies and this CPU's archives."""
    selected = set(RUNTIME_FILES)
    selected.update(row[2] for row in rows)
    dependency_payload(repository, selected)
    for runtime in RUNTIME_FILES:
        selected.update(runtime + suffix for suffix in (".md5sum", ".sha256sum")
                        if payload_file(repository, runtime + suffix, required=False) is not None)
    # The secure-download test checks the repository's documented TLS policy.
    if any(row[2] == "tests/installer-secure-download-fallback.sh" for row in rows):
        selected.add("README.md")
    if any(row[2] == "tests/virtual-arm-native.sh" for row in rows):
        selected.update(native_payload(repository, architecture))
    fixtures = repository / "tests/fixtures"
    if fixtures.is_dir():
        selected.update(path.relative_to(repository).as_posix() for path in fixtures.rglob("*") if path.is_file())
    for relative in selected:
        payload_file(repository, relative)
    return selected


def build_initramfs(repository, cache, output, rows, architecture, configuration, selection):
    """Write a gzip/newc guest image with native rootfs, candidate and control files."""
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
        mode, content = read_payload(repository, relative)
        entries["repo/" + relative_name(relative)] = (stat.S_IFREG | (mode & 0o777), content)
    entries["init"] = (stat.S_IFREG | 0o755, read_payload(repository, "tools/virtual-arm/guest-init.sh")[1])
    entries["usr/lib/agh-virtual-arm/guest-runner.sh"] = (stat.S_IFREG | 0o755, read_payload(repository, "tools/virtual-arm/guest-runner.sh")[1])
    entries["etc/agh-virtual-arm.conf"] = (stat.S_IFREG | 0o600, configuration.encode())
    entries["etc/agh-virtual-arm-selection.tsv"] = (stat.S_IFREG | 0o444, selection)
    entries["etc/inittab"] = (stat.S_IFREG | 0o644, b"::once:/bin/sh /usr/lib/agh-virtual-arm/guest-runner.sh\n")
    # Adding parent entries mutates the mapping, so iterate a fixed name snapshot.
    for name in tuple(entries):
        parent = Path(name).parent
        while parent.as_posix() != ".":
            entries.setdefault(parent.as_posix(), (stat.S_IFDIR | 0o755, b""))
            parent = parent.parent
    with output.open("wb") as destination, gzip.GzipFile(fileobj=destination, mode="wb", mtime=0) as compressed:
        for number, (name, (mode, data)) in enumerate(sorted(entries.items()), 1):
            add_cpio(compressed, number, name, mode, data)
        add_cpio(compressed, len(entries) + 1, "TRAILER!!!", 0)


def qemu_command(architecture, cache, initramfs, token):
    """Return an isolated TCG launch command using host QEMU or the tools container."""
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


class GuestProtocol:
    """Parse the ordered guest protocol while retaining incomplete failure state."""

    def __init__(self, directory, rows, token, architecture, scenario_seconds, grace_seconds):
        """Bind protocol records to the exact scenario selection and guest target."""
        self.directory, self.rows, self.token, self.architecture = directory, rows, token, architecture
        self.maximum_elapsed = scenario_seconds + grace_seconds
        self.boot = {"status": "fail"}
        self.native_tools = {}
        self.results = []
        self.current = None
        self.scenario_started = None
        self.endpoint_recorded = None
        self.done = False
        self.error = "Guest exited without complete evidence"

    def timeout_error(self, elapsed, limit, boot_seconds, grace_seconds):
        """Identify boot, whole-run, active-scenario and between-endpoint timeouts."""
        if elapsed > limit or (self.boot["status"] != "pass" and elapsed > boot_seconds):
            return "Whole-guest timeout" if self.boot["status"] == "pass" else "Guest boot timeout"
        now = time.monotonic()
        if self.current is not None and now - self.scenario_started > self.maximum_elapsed:
            return "Guest scenario timeout: " + self.current["scenario"]
        if self.current is None and self.endpoint_recorded is not None and now - self.endpoint_recorded > max(1, grace_seconds):
            return "Guest scenario start/completion timeout"
        return ""

    def output_line(self, line, decoded, fields):
        """Retain scenario logs and print diagnostics outside authenticated markers."""
        if fields[0] == "NATIVE_TOOL" and len(fields) == 3:
            self.native_tools[fields[1]] = fields[2]
        if self.current is not None:
            self.current["stream"].write(line)
        if self.current is not None or decoded.startswith("NATIVE_TOOL") or re.search(r"FAIL:|Kernel panic|Out of memory|not syncing|can't execute", decoded):
            print(decoded, flush=True)

    def boot_record(self, fields):
        """Accept one boot record only for the requested CPU and pinned BusyBox."""
        if len(fields) != 10 or self.boot["status"] == "pass":
            return False
        if fields[3] != self.architecture or fields[4] != MACHINES[self.architecture][4] or fields[6] != "v1.25.1":
            self.error = "Guest architecture or BusyBox version does not match the requested environment"
            return True
        self.boot = {"status": "pass", "architecture": fields[3], "reported_architecture": fields[3], "machine": fields[4],
                     "kernel_release": fields[5], "busybox_version": fields[6].removeprefix("v"),
                     "environment_digest": fields[7], "cpu_features": fields[8],
                     "token": self.token, "native_tools": self.native_tools}
        self.endpoint_recorded = time.monotonic()
        print(f"{self.architecture}: booted {fields[4]}, Linux {fields[5]}, BusyBox {fields[6]}", flush=True)
        return None

    def start_record(self, fields):
        """Open the next scenario log only when its identity matches the selection."""
        if len(fields) != 6 or self.boot["status"] != "pass" or self.current is not None:
            return False
        index = len(self.results)
        if index >= len(self.rows) or fields[3:5] != self.rows[index][:2]:
            self.error = "Guest scenario ordering does not match the exact selection"
            return True
        scenario_log = self.directory / (fields[4] + ".log")
        self.current = {"feature": fields[3], "scenario": fields[4], "test": self.rows[index][2],
                        "log": scenario_log.name, "stream": scenario_log.open("wb")}
        self.scenario_started = time.monotonic()
        print(f"{self.architecture}: {fields[3]}/{fields[4]}", flush=True)
        return None

    def end_numbers(self, fields):
        """Parse bounded ASCII result fields before integer conversion."""
        if (not re.fullmatch(r"\d{1,3}", fields[5], re.ASCII) or
                len(fields[6]) > len(str(self.maximum_elapsed)) or
                not re.fullmatch(r"\d+", fields[6], re.ASCII)):
            self.error = "Malformed guest scenario exit status or elapsed time"
            return None
        exit_status, elapsed = int(fields[5]), int(fields[6])
        if exit_status > 255 or elapsed > self.maximum_elapsed:
            self.error = "Guest scenario exit status or elapsed time is out of range"
            return None
        return exit_status, elapsed

    def end_record(self, fields):
        """Publish a result only after matching END fields and a closed scenario log."""
        if len(fields) != 8 or self.current is None or fields[3:5] != [self.current["feature"], self.current["scenario"]]:
            return False
        numbers = self.end_numbers(fields)
        if numbers is None:
            return True
        exit_status, elapsed = numbers
        self.current.pop("stream").close()
        self.current.update(exit_status=exit_status, elapsed_seconds=elapsed,
                            status="pass" if exit_status == 0 else "fail")
        self.current["log_sha256"] = digest_file(self.directory / self.current["log"])
        self.results.append(self.current)
        print(f"{self.architecture}: {self.current['scenario']} {self.current['status']} (exit {exit_status})", flush=True)
        self.current, self.scenario_started = None, None
        self.endpoint_recorded = time.monotonic()
        return None

    def done_record(self, fields):
        """Require all scenario endpoints before accepting the guest completion record."""
        if len(fields) != 5 or self.current is not None or len(self.results) != len(self.rows):
            return False
        self.done = True
        self.error = "" if fields[3] == "0" and all(row["status"] == "pass" for row in self.results) else "One or more guest scenarios failed"
        return True

    def error_record(self, fields):
        """Retain a guest native-tool failure before boot acceptance."""
        if len(fields) not in (5, 6):
            return False
        self.error = f"Native guest tool failed before boot acceptance: {fields[3]} (exit {fields[4]})"
        return True

    def consume(self, line):
        """Return whether parsing must stop after one authenticated protocol marker."""
        decoded = line.decode(errors="replace").rstrip("\r\n")
        fields = decoded.split("\t")
        if len(fields) < 3 or fields[:2] != ["AGH_VM", self.token]:
            self.output_line(line, decoded, fields)
            return False
        handlers = {"BOOT": self.boot_record, "START": self.start_record, "END": self.end_record,
                    "DONE": self.done_record, "ERROR": self.error_record}
        handler = handlers.get(fields[2])
        outcome = handler(fields) if handler is not None else False
        if outcome is False:
            self.error = "Malformed or unexpected guest result marker"
            return True
        return outcome is True

    def close_scenario(self):
        """Close an unfinished log without converting its partial output to a result."""
        if self.current is not None:
            stream = self.current.pop("stream", None)
            if stream is not None:
                stream.close()


def stop_guest(process, command, reader):
    """Reap the guest and continue container/pipe cleanup through earlier errors."""
    try:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
        process.wait()
    finally:
        try:
            if command[:2] == ["docker", "run"]:
                container = command[command.index("--name") + 1]
                subprocess.run(["docker", "rm", "-f", container], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=30, check=False)
        finally:
            reader.join(timeout=2)
            process.stdout.close()


def serial_messages(process, messages):
    """Queue process stdout lines and an EOF sentinel for the bounded parser."""
    for line in iter(process.stdout.readline, b""):
        messages.put(line)
    messages.put(None)


def read_guest_messages(messages, serial, protocol, started, limit, boot_seconds, grace_seconds):
    """Read serial output with bounded boot, scenario and completion deadlines."""
    while True:
        error = protocol.timeout_error(time.monotonic() - started, limit, boot_seconds, grace_seconds)
        if error:
            protocol.error = error
            return
        try:
            line = messages.get(timeout=1)
        except queue.Empty:
            continue
        if line is None:
            return
        serial.write(line)
        serial.flush()
        if protocol.consume(line):
            return


def run_guest(command, directory, rows, token, boot_seconds, scenario_seconds, expected_architecture, scenario_grace_seconds=30):
    """Require a real boot, ordered scenario endpoints and the guest completion record."""
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    messages = queue.Queue()
    reader = threading.Thread(target=serial_messages, args=(process, messages), daemon=True)
    reader.start()
    protocol = GuestProtocol(directory, rows, token, expected_architecture, scenario_seconds, scenario_grace_seconds)
    limit = boot_seconds + (scenario_seconds + 30) * len(rows)
    serial_path = directory / SERIAL_LOG
    try:
        with serial_path.open("wb") as serial:
            read_guest_messages(messages, serial, protocol, started, limit, boot_seconds, scenario_grace_seconds)
    finally:
        try:
            protocol.close_scenario()
        finally:
            stop_guest(process, command, reader)
    if protocol.error:
        print(f"{expected_architecture}: {protocol.error}; full serial log: {serial_path}", file=sys.stderr, flush=True)
        if protocol.boot["status"] != "pass":
            for line in serial_path.read_text(errors="replace").splitlines()[-30:]:
                print(f"{expected_architecture}: {line}", file=sys.stderr, flush=True)
    return protocol.boot, protocol.results, protocol.done, protocol.error


def manifest_metadata(manifest):
    """Load canonical feature/scenario IDs and annotation fields from the manifest."""
    metadata = {}
    for line in manifest.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 5 and fields[0] != "feature":
            if not IDENTIFIER.fullmatch(fields[0]) or not IDENTIFIER.fullmatch(fields[1]):
                raise ValueError("The feature manifest contains an invalid feature/scenario ID")
            metadata[(fields[0], fields[1])] = fields
    return metadata


def requested_features(value, metadata):
    """Map a CLI selection to canonical manifest IDs before any child-process call."""
    supported = list(dict.fromkeys(feature for feature, _ in metadata))
    if value == "all":
        return supported
    requested = value.split(",")
    if (not requested or len(set(requested)) != len(requested) or
            any(not IDENTIFIER.fullmatch(item) or item not in supported for item in requested)):
        raise ValueError("Features must be a nonempty, unique selection of known manifest IDs")
    # Child processes receive IDs originating in the manifest, never option text.
    return [feature for feature in supported if feature in requested]


def selected_rows(selection):
    """Reject empty or malformed checker output before guest payload assembly."""
    rows = [line.split("\t") for line in selection.decode().splitlines()]
    if not rows or any(len(row) != 3 for row in rows):
        raise ValueError("The feature selection contains no executable scenarios")
    for feature, scenario, test in rows:
        if not IDENTIFIER.fullmatch(feature) or not IDENTIFIER.fullmatch(scenario):
            raise ValueError("The feature selection contains an invalid feature/scenario ID")
        relative_name(test)
    return rows


def version_identity(repository):
    """Record Git provenance when available while allowing non-Git diagnostic inputs."""
    try:
        commit = checked_output(["git", "-C", str(repository), "rev-parse", "HEAD"])
        dirty = bool(checked_output(["git", "-C", str(repository), "status", "--porcelain"]))
        return commit, dirty
    except (FileNotFoundError, subprocess.CalledProcessError):
        return "unversioned", True


class MatrixRun:
    """Bind common provenance to each native target's fail-closed evidence report."""

    def __init__(self, repository, output, cache, feature_value):
        """Load validated selection and bounded host-only timeout budgets once."""
        self.repository, self.output, self.cache = repository, output, cache
        self.checker = repository / "tools/virtual-arm/check-evidence.py"
        self.manifest = repository / "tools/virtual-arm/features.tsv"
        self.metadata = manifest_metadata(self.manifest)
        self.features = requested_features(feature_value, self.metadata)
        self.feature_argument = ",".join(self.features)
        self.selection = subprocess.check_output([sys.executable, str(self.checker), "--select",
                                                  "--features=" + self.feature_argument, "--manifest", str(self.manifest)])
        self.rows = selected_rows(self.selection)
        self.content_digest = self.fresh_digest()
        self.commit_label, self.dirty = version_identity(repository)
        self.scenario_seconds = int(os.environ.get("AGH_VIRTUAL_ARM_SCENARIO_TIMEOUT", "900"))
        self.boot_seconds = int(os.environ.get("AGH_VIRTUAL_ARM_BOOT_TIMEOUT", "180"))
        if not 1 <= self.scenario_seconds <= 7200 or not 1 <= self.boot_seconds <= 1800:
            raise ValueError("Virtual-only timeout budgets must be positive and bounded")
        (output / "selection.tsv").write_bytes(self.selection)

    def fresh_digest(self):
        """Compute the current content identity using the canonical evidence checker."""
        return checked_output([sys.executable, str(self.checker), "--content-digest", "--repository", str(self.repository)])

    def initial_evidence(self, architecture):
        """Start each target report as failing until complete native evidence arrives."""
        return {"schema_version": 1, "architecture": architecture, "content_digest": self.content_digest,
                "commit_label": self.commit_label, "source_dirty": self.dirty, "requested_features": self.features,
                "selection_digest": digest_bytes(self.selection), "started_at": timestamp(), "environment": {},
                "guest_boot": {"status": "fail"}, "results": [], "status": "fail",
                "execution": {"engine": "qemu-system-tcg", "network": "none", "source_read_only": True,
                              "boot_timeout_seconds": self.boot_seconds, "scenario_timeout_seconds": self.scenario_seconds}}

    def execute_architecture(self, architecture, directory, evidence):
        """Verify a pinned guest, execute scenarios, and recheck native artifacts."""
        token = secrets.token_hex(16)
        cache = self.cache / architecture
        environment_raw = (cache / "environment.json").read_bytes()
        environment = json.loads(environment_raw)
        environment_digest = digest_bytes(environment_raw)
        evidence.update(environment=environment, environment_digest=environment_digest)
        (directory / "environment.json").write_bytes(environment_raw)
        verify_cached_environment(self.repository, cache, environment, architecture)
        configuration = f"ARCHITECTURE='{architecture}'\nRUN_TOKEN='{token}'\nENVIRONMENT_DIGEST='{environment_digest}'\nCONTENT_DIGEST='{self.content_digest}'\nSCENARIO_TIMEOUT_SECONDS='{self.scenario_seconds}'\n"
        initramfs = directory / "initramfs.cpio.gz"
        build_initramfs(self.repository, cache, initramfs, self.rows, architecture, configuration, self.selection)
        evidence["execution"]["initramfs_sha256"] = digest_file(initramfs)
        command = qemu_command(architecture, cache, initramfs, token)
        evidence["execution"]["command"] = command
        executable_index = command.index(MACHINES[architecture][0])
        actual_qemu_version = checked_output(command[:executable_index + 1] + ["--version"]).splitlines()[0]
        if actual_qemu_version != environment.get("qemu_version"):
            raise ValueError("QEMU version differs from the recorded native environment")
        evidence["execution"]["qemu_version"] = actual_qemu_version
        boot, results, done, error = run_guest(command, directory, self.rows, token, self.boot_seconds, self.scenario_seconds, architecture)
        for result in results:
            fields = self.metadata[(result["feature"], result["scenario"])]
            _, source = read_payload(self.repository, result["test"])
            result.update(evidence_class=fields[3], assertions=fields[4], source_sha256=digest_bytes(source))
        evidence.update(guest_boot=boot, results=results, guest_complete=done, error=error,
                        status="pass" if done and not error else "fail")
        verify_cached_environment(self.repository, cache, environment, architecture)

    def record_architecture(self, architecture):
        """Publish a fresh report even when boot, scenario or provenance checks fail."""
        directory = self.output / architecture
        directory.mkdir(exist_ok=True)
        evidence_path = directory / "evidence.json"
        evidence_path.unlink(missing_ok=True)
        (directory / SERIAL_LOG).unlink(missing_ok=True)
        evidence = self.initial_evidence(architecture)
        try:
            self.execute_architecture(architecture, directory, evidence)
        except (OSError, ValueError, subprocess.CalledProcessError) as exception:
            evidence.update(status="fail", error=str(exception))
            print(f"{architecture}: {exception}", file=sys.stderr, flush=True)
        serial_path = directory / SERIAL_LOG
        if serial_path.is_file():
            evidence["execution"].update(serial_log=serial_path.name, serial_log_sha256=digest_file(serial_path))
        if self.fresh_digest() != self.content_digest:
            evidence.update(status="fail", error="Tested source changed while the virtual matrix was executing")
        evidence["finished_at"] = timestamp()
        (directory / "initramfs.cpio.gz").unlink(missing_ok=True)
        atomic_json(evidence_path, evidence)
        return evidence_path, evidence["status"] != "pass"

    def acceptance_command(self, architectures, defer_acceptance):
        """Build the aggregate checker command from validated canonical selections."""
        command = [sys.executable, str(self.checker), "--repository", str(self.repository),
                   "--manifest", str(self.manifest), "--features=" + self.feature_argument,
                   "--architectures=" + ",".join(architectures), "--summary", str(self.output / "acceptance.json")]
        if defer_acceptance == "1":
            command.append("--partial")
        return command


def main():
    """Execute selected guest scenarios, retain evidence and return acceptance status."""
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
    matrix = MatrixRun(repository, output, cache, options.features)
    evidence_paths, failed = [], False
    for architecture in architectures:
        evidence_path, architecture_failed = matrix.record_architecture(architecture)
        evidence_paths.append(str(evidence_path))
        failed = failed or architecture_failed
    acceptance = subprocess.call([*matrix.acceptance_command(architectures, options.defer_acceptance), *evidence_paths])
    return 1 if failed else acceptance


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as exception:
        print(f"Virtual ARM execution failed: {exception}", file=sys.stderr)
        sys.exit(1)
