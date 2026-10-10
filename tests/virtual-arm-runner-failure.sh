#!/bin/sh
# Host protocol failures must remain failures; these fixtures never create ARM acceptance.
set -eu
REPOSITORY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "${REPOSITORY}" <<'PYTHON'
import gzip
import importlib.util
import io
import os
import json
from pathlib import Path
import sys
import tempfile
import time
from unittest import mock

repository = Path(sys.argv[1])
specification = importlib.util.spec_from_file_location("virtual_arm_runner", repository / "tools/virtual-arm/run-matrix.py")
runner = importlib.util.module_from_spec(specification)
specification.loader.exec_module(runner)
assert runner.MACHINES["armv5"][1:3] == ("vexpress-a9", "cortex-a9")
assert runner.MACHINES["armv5"][4] == "armv7l"
assert runner.CPU_OPTIONS["armv5"] == "cortex-a9,vfp=off,neon=off"
assert runner.TARGETS["armv5"]["cpu_architecture"] == "armv7"
assert runner.TARGETS["armv5"]["float_abi"] == "soft"
assert runner.TARGETS["armv5"]["router_model"] == "ASUS RT-AC68U"
token = "0123456789abcdef0123456789abcdef"
rows = [["hooks", "example", "tests/example.sh"]]


def exercise(root, name, source, docker=False, close_error=False, remove_error=False, **options):
    """Use real serial subprocesses and require their reap/pipe cleanup on failure."""
    directory = root / name
    directory.mkdir()
    command = directory / "fake-serial.py"
    command.write_text(source)
    real_popen = runner.subprocess.Popen
    real_open = Path.open
    launched = []

    def launch(arguments, **kwargs):
        """Start the selected fake serial process and retain it for cleanup checks."""
        process = real_popen([sys.executable, str(command)] if docker else arguments, **kwargs)
        launched.append(process)
        return process

    class FaultyLog:
        """Close the real log, then inject a filesystem close failure."""

        def __init__(self, stream):
            """Wrap a real log stream whose close operation will fail predictably."""
            self.stream = stream

        def write(self, value):
            """Forward scenario output to the underlying real log stream."""
            return self.stream.write(value)

        def close(self):
            """Close the stream and then raise the injected close failure."""
            self.stream.close()
            raise OSError("injected scenario log close failure")

    def open_file(path, *arguments, **kwargs):
        """Replace only the selected scenario log with the close-failure wrapper."""
        stream = real_open(path, *arguments, **kwargs)
        return FaultyLog(stream) if close_error and path.name == "example.log" else stream

    arguments = ["docker", "run", "--name", "host-fixture-only"] if docker else [sys.executable, str(command)]
    started = time.monotonic()
    with mock.patch.object(runner.subprocess, "Popen", side_effect=launch), \
            mock.patch.object(Path, "open", side_effect=open_file, autospec=True), \
            mock.patch.object(runner.subprocess, "run") as remove_container:
        if remove_error:
            remove_container.side_effect = runner.subprocess.TimeoutExpired("docker rm", 30)
        try:
            boot, results, done, error = runner.run_guest(arguments, directory, rows, token, 1, 1, "armv5", **options)
        finally:
            for process in launched:
                leaked = process.poll() is None
                pipe_closed = process.stdout.closed
                # A red regression must also clean up its own fixture processes.
                if leaked:
                    process.kill()
                    process.wait()
                if not pipe_closed:
                    process.stdout.close()
                assert not leaked, name + " left its serial/QEMU subprocess running"
                assert pipe_closed, name + " left its serial pipe open"
            if docker:
                remove_container.assert_called_once_with(
                    ["docker", "rm", "-f", "host-fixture-only"],
                    stdout=runner.subprocess.DEVNULL, stderr=runner.subprocess.DEVNULL, timeout=30, check=False)
    assert error and not (done and all(result["status"] == "pass" for result in results)), name
    assert (directory / "serial.log").is_file(), name
    assert time.monotonic() - started < 5, name + " did not terminate promptly"
    return boot, results, done, error


with tempfile.TemporaryDirectory(prefix="virtual-arm-runner-") as temporary:
    root = Path(temporary)
    boot, _, done, _ = exercise(root, "missing-boot", "print('unrelated serial output')\n")
    assert boot["status"] == "fail" and not done
    _, _, _, error = exercise(root, "boot-timeout", "import time\ntime.sleep(30)\n")
    assert error == "Guest boot timeout"
    bad_boot = f"AGH_VM\t{token}\tBOOT\tarmv5\taarch64\t6.1.157\tv1.25.1\t{'a' * 64}\tnone\t"
    _, _, _, error = exercise(root, "wrong-cpu", "print(" + repr(bad_boot) + ", flush=True)\n")
    assert "architecture" in error
    good_boot = f"AGH_VM\t{token}\tBOOT\tarmv5\t{runner.MACHINES['armv5'][4]}\t6.1.157\tv1.25.1\t{'a' * 64}\tnone\t"
    _, _, done, error = exercise(root, "idle-after-boot", "import time\nprint(" + repr(good_boot) + ", flush=True)\ntime.sleep(30)\n", scenario_grace_seconds=0)
    assert not done and error == "Guest scenario start/completion timeout"
    _, _, done, _ = exercise(root, "wrong-token", "print(" + repr(good_boot.replace(token, "0" * 32)) + ", flush=True)\n")
    assert not done
    missing_result = f"AGH_VM\t{token}\tDONE\t0\t"
    _, _, done, _ = exercise(root, "missing-result", "print(" + repr(good_boot) + ", flush=True)\nprint(" + repr(missing_result) + ", flush=True)\n")
    assert not done
    records = [good_boot, f"AGH_VM\t{token}\tSTART\thooks\texample\t", "concrete scenario failure", f"AGH_VM\t{token}\tEND\thooks\texample\t124\t1\t", f"AGH_VM\t{token}\tDONE\t1\t"]
    _, results, done, error = exercise(root, "scenario-timeout", "\n".join("print(" + repr(record) + ", flush=True)" for record in records) + "\n")
    assert done and results[0]["exit_status"] == 124 and results[0]["status"] == "fail"
    assert error == "One or more guest scenarios failed"
    assert results[0]["log_sha256"] == runner.digest_file(root / "scenario-timeout/example.log")
    wrong_order = f"AGH_VM\t{token}\tSTART\thooks\tunexpected\t"
    _, _, done, error = exercise(root, "wrong-order", "print(" + repr(good_boot) + ", flush=True)\nprint(" + repr(wrong_order) + ", flush=True)\n")
    assert not done and "ordering" in error
    started = f"AGH_VM\t{token}\tSTART\thooks\texample\t"
    _, _, done, error = exercise(root, "hung-scenario", "import time\nprint(" + repr(good_boot) + ", flush=True)\nprint(" + repr(started) + ", flush=True)\ntime.sleep(30)\n", scenario_grace_seconds=0)
    assert not done and error == "Guest scenario timeout: example"

    for name, exit_status, elapsed in (
            ("empty-status", "", "1"), ("bad-status", "invalid", "1"),
            ("unicode-status", "٠", "1"), ("unicode-elapsed", "0", "١"),
            ("negative-status", "-1", "1"), ("large-status", "256", "1"),
            ("empty-elapsed", "0", ""), ("bad-elapsed", "0", "invalid"),
            ("negative-elapsed", "0", "-1"), ("large-elapsed", "0", "32"),
            ("oversized-elapsed", "0", "9" * 5000)):
        malformed_end = f"AGH_VM\t{token}\tEND\thooks\texample\t{exit_status}\t{elapsed}\t"
        records = [good_boot, started, "retained malformed-END evidence", malformed_end]
        source = "import time\n" + "\n".join("print(" + repr(record) + ", flush=True)" for record in records) + "\ntime.sleep(30)\n"
        _, results, done, error = exercise(root, "malformed-end-" + name, source)
        assert not done and not results and "exit status or elapsed time" in error, name
        assert "retained malformed-END evidence" in (root / ("malformed-end-" + name) / "example.log").read_text()

    malformed_end = f"AGH_VM\t{token}\tEND\thooks\texample\tbad\t1\t"
    records = [good_boot, started, "retained malformed-END evidence", malformed_end]
    source = "import time\n" + "\n".join("print(" + repr(record) + ", flush=True)" for record in records) + "\ntime.sleep(30)\n"
    _, results, done, error = exercise(root, "malformed-end-docker", source, docker=True)
    assert not done and not results and "exit status or elapsed time" in error
    try:
        exercise(root, "log-close-failure", source, docker=True, close_error=True)
    except OSError as error:
        assert "injected scenario log close failure" in str(error), error
    else:
        raise AssertionError("scenario log close failure was hidden")
    try:
        exercise(root, "container-remove-failure", source, docker=True, remove_error=True)
    except runner.subprocess.TimeoutExpired:
        pass
    else:
        raise AssertionError("container-removal timeout was hidden")


def archive_entries(path):
    """Decode real newc records to check the payload actually written to the guest."""
    content = gzip.decompress(path.read_bytes())
    entries = {}
    position = 0
    while position < len(content):
        assert content[position:position + 6] == b"070701"
        fields = [int(content[position + 6 + index * 8:position + 14 + index * 8], 16) for index in range(13)]
        name_start = position + 110
        name = content[name_start:name_start + fields[11] - 1].decode()
        data_start = (name_start + fields[11] + 3) & ~3
        entries[name] = content[data_start:data_start + fields[6]]
        position = (data_start + fields[6] + 3) & ~3
        if name == "TRAILER!!!":
            return entries
    raise AssertionError("initramfs has no newc trailer")


def require_unsafe(operation, description):
    """Require a rejected host path rather than relying on absence from the image."""
    try:
        operation()
    except (ValueError, OSError):
        return
    raise AssertionError("unsafe host path was accepted: " + description)


with tempfile.TemporaryDirectory(prefix="virtual-arm-payload-") as temporary:
    root = Path(temporary)
    candidate = root / "repository"
    (candidate / "tests").mkdir(parents=True)
    (candidate / "tools/helpers").mkdir(parents=True)
    (candidate / "tools/virtual-arm").mkdir()
    for name in runner.RUNTIME_FILES:
        (candidate / name).write_text("#!/bin/sh\n")
    test = candidate / "tests/example.sh"
    test.write_text("#!/bin/sh\nsh tests/helper.sh\nsh tests/missing.sh\n")
    (candidate / "tests/helper.sh").write_text("#!/bin/sh\nsh tools/helpers/inner.sh\n")
    (candidate / "tools/helpers/inner.sh").write_text("#!/bin/sh\nprintf 'confined dependency'\n")
    for name in ("guest-init.sh", "guest-runner.sh"):
        (candidate / "tools/virtual-arm" / name).write_text("#!/bin/sh\n")
    sentinel = root / "secret.sh"
    sentinel.write_text("PRIVATE OUTSIDE HOST SENTINEL\n")
    sentinel_identity = sentinel.stat()
    outside = root / "outside"
    outside.mkdir()
    (outside / "secret.sh").hardlink_to(sentinel)
    real_fdopen = runner.os.fdopen

    def confined_fdopen(descriptor, *arguments, **keywords):
        """Fail if any outside sentinel reaches a byte-reading file descriptor."""
        identity = os.fstat(descriptor)
        assert (identity.st_dev, identity.st_ino) != (sentinel_identity.st_dev, sentinel_identity.st_ino), "outside host bytes were opened"
        return real_fdopen(descriptor, *arguments, **keywords)

    with mock.patch.object(runner.os, "fdopen", side_effect=confined_fdopen):
        payload = runner.source_payload(candidate, rows, "armv7")
        assert {"tests/helper.sh", "tools/helpers/inner.sh"} <= payload
        assert "tests/missing.sh" not in payload
        cache = root / "cache"
        (cache / "rootfs/bin").mkdir(parents=True)
        (cache / "rootfs/bin/busybox").write_bytes(b"native busybox fixture")
        (cache / "rootfs/bin/[").symlink_to("busybox")
        initramfs = root / "guest.cpio.gz"
        runner.build_initramfs(candidate, cache, initramfs, rows, "armv7", "ARCHITECTURE='armv7'\n", b"selection fixture")
        entries = archive_entries(initramfs)
        assert entries["repo/tests/helper.sh"] == (candidate / "tests/helper.sh").read_bytes()
        assert entries["repo/tools/helpers/inner.sh"] == (candidate / "tools/helpers/inner.sh").read_bytes()
        assert entries["bin/["] == b"busybox", "legitimate BusyBox applet name was rejected"
        assert all(sentinel.read_bytes() not in value for value in entries.values())

        for relative in ("tests/../../secret.sh", str(sentinel), "tests/./example.sh", "tests//example.sh", "tests/example.sh\n", "tests\\example.sh"):
            require_unsafe(lambda: runner.source_payload(candidate, [["hooks", "example", relative]], "armv7"), relative)
        for dependency in ("tests/../../secret.sh", "tools/../../secret.sh"):
            test.write_text("#!/bin/sh\nsh " + dependency + "\n")
            require_unsafe(lambda: runner.source_payload(candidate, rows, "armv7"), dependency)
        (candidate / "tests/linked.sh").symlink_to(sentinel)
        test.write_text("#!/bin/sh\nsh tests/linked.sh\n")
        require_unsafe(lambda: runner.source_payload(candidate, rows, "armv7"), "symlink file")
        (candidate / "tests/linked").symlink_to(outside, target_is_directory=True)
        test.write_text("#!/bin/sh\nsh tests/linked/secret.sh\n")
        require_unsafe(lambda: runner.source_payload(candidate, rows, "armv7"), "symlink parent")

        race = candidate / "tests/race"
        race.mkdir()
        (race / "secret.sh").write_text("safe repository content\n")
        real_payload_file = runner.payload_file

        def swapped_parent(repository_path, relative, required=True):
            """Replace a validated parent to prove descriptor-based reads reject swaps."""
            result = real_payload_file(repository_path, relative, required)
            race.rename(candidate / "tests/race-original")
            race.symlink_to(outside, target_is_directory=True)
            return result

        with mock.patch.object(runner, "payload_file", side_effect=swapped_parent):
            require_unsafe(lambda: runner.read_payload(candidate, "tests/race/secret.sh"), "parent swapped after validation")

    for name in ("../secret.sh", "repo/../../secret.sh", "/secret.sh", "repo/a\x00b", "repo/a\nb", "repo//file"):
        require_unsafe(lambda: runner.add_cpio(io.BytesIO(), 1, name, 0), "archive entry " + repr(name))

metadata = runner.manifest_metadata(repository / "tools/virtual-arm/features.tsv")
assert runner.requested_features("hooks", metadata) == ["hooks"]
assert runner.requested_features("all", metadata) == list(dict.fromkeys(feature for feature, _ in metadata))
for feature_value in ("--select", "hooks,--content-digest", "hooks,hooks", "hooks,unknown", "hooks,", "hooks\n"):
    with mock.patch.object(runner.subprocess, "check_output") as child:
        require_unsafe(lambda: runner.MatrixRun(repository, Path("unused"), Path("unused"), feature_value), "feature argument " + repr(feature_value))
        child.assert_not_called()

native_rows = [["native_dns", "virtual-arm-native", "tests/virtual-arm-native.sh"]]
for architecture in runner.MACHINES:
    payload = runner.source_payload(repository, native_rows, architecture)
    for model in ("nvram", "service", "cru", "get_mtlan"):
        assert "tools/virtual-arm/native/" + model in payload, "native firmware model omitted from guest payload"
    assert any(name.startswith(architecture + "/") and name.endswith(".tar.gz") for name in payload), "native archive omitted"
    assert not any(name.startswith(other + "/") for name in payload for other in runner.MACHINES if other != architecture), "unrelated architecture archive included"

with tempfile.TemporaryDirectory(prefix="virtual-arm-dtb-") as temporary:
    root = Path(temporary)
    cache = root / "armv5"
    (cache / "rootfs/bin").mkdir(parents=True)
    (cache / "kernel").write_bytes(b"kernel")
    (cache / "rootfs/bin/busybox").write_bytes(b"busybox")
    (cache / "dtb").write_bytes(b"vexpress dtb")
    rootfs_digest = runner.checked_output([
        sys.executable, str(repository / "tools/virtual-arm/rootfs-manifest.py"), str(cache / "rootfs")
    ])
    source_digest = runner.checked_output([
        sys.executable, str(repository / "tools/virtual-arm/environment.py"), "source-digest",
        str(repository / "tools/virtual-arm")
    ])
    environment = {
        "architecture": "armv5", "machine": "vexpress-a9", "cpu": "cortex-a9", "ram_mb": 256,
        "target": runner.TARGETS["armv5"], "cpu_options": runner.CPU_OPTIONS["armv5"],
        "execution_class": "qemu-full-system-tcg", "busybox_version": "v1.25.1",
        "kernel_sha256": runner.digest_file(cache / "kernel"),
        "busybox_sha256": runner.digest_file(cache / "rootfs/bin/busybox"),
        "dtb_sha256": runner.digest_file(cache / "dtb"),
        "rootfs_content_digest": rootfs_digest, "source_manifest_sha256": source_digest,
    }
    (cache / "dtb").unlink()
    try:
        runner.verify_cached_environment(repository, cache, environment, "armv5")
    except ValueError as error:
        assert "device tree digest mismatch" in str(error), error
    else:
        raise AssertionError("deleted armv5 DTB was accepted")
    (cache / "dtb").write_bytes(b"vexpress dtb")
    environment.pop("dtb_sha256")
    try:
        runner.verify_cached_environment(repository, cache, environment, "armv5")
    except ValueError as error:
        assert "requires a device tree digest" in str(error), error
    else:
        raise AssertionError("armv5 environment without DTB metadata was accepted")

with tempfile.TemporaryDirectory(prefix="virtual-arm-postcheck-") as temporary:
    root = Path(temporary)
    cache = root / "cache" / "armv5"
    cache.mkdir(parents=True)
    (cache / "environment.json").write_text(json.dumps({"qemu_version": "test QEMU version"}))
    output = root / "results"

    def output_fixture(command):
        """Return deterministic command output for the post-run provenance fixture."""
        if command[0] == "qemu-system-arm":
            return "test QEMU version"
        if command[0] == "git":
            return "host-fixture" if "rev-parse" in command else ""
        return "b" * 64

    def initramfs_fixture(repository, cache, destination, *unused):
        """Write a marker initramfs without performing an ARM build."""
        destination.write_bytes(b"host fixture; no ARM execution")

    def guest_fixture(command, directory, *unused):
        """Return a synthetic passing guest result for post-run error handling."""
        (directory / "serial.log").write_text("host fixture; no ARM execution\n")
        return {"status": "pass"}, [], True, ""

    arguments = ["run-matrix.py", "--repository", str(repository), "--features", "hooks", "--architectures", "armv5", "--output", str(output), "--cache", str(root / "cache"), "--defer-acceptance", "1"]
    with mock.patch.object(sys, "argv", arguments), \
            mock.patch.object(runner, "checked_output", side_effect=output_fixture), \
            mock.patch.object(runner, "verify_cached_environment", side_effect=[None, ValueError("post-run native artifact changed")]), \
            mock.patch.object(runner, "build_initramfs", side_effect=initramfs_fixture), \
            mock.patch.object(runner, "qemu_command", return_value=["qemu-system-arm"]), \
            mock.patch.object(runner, "run_guest", side_effect=guest_fixture), \
            mock.patch.object(runner.subprocess, "call", return_value=0):
        assert runner.main() == 1, "post-run provenance failure returned success"
    evidence = json.loads((output / "armv5/evidence.json").read_text())
    assert evidence["status"] == "fail" and evidence["error"] == "post-run native artifact changed", "post-run provenance failure retained a green result"

print("Virtual ARM runner failure contracts passed (host fixtures; no feature acceptance).")
PYTHON
