#!/bin/sh
# Host protocol failures must remain failures; these fixtures never create ARM acceptance.
set -eu
REPOSITORY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
python3 - "${REPOSITORY}" <<'PYTHON'
import importlib.util
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
        process = real_popen([sys.executable, str(command)] if docker else arguments, **kwargs)
        launched.append(process)
        return process

    class FaultyLog:
        """Close the real log, then inject a filesystem close failure."""

        def __init__(self, stream):
            self.stream = stream

        def write(self, value):
            return self.stream.write(value)

        def close(self):
            self.stream.close()
            raise OSError("injected scenario log close failure")

    def open_file(path, *arguments, **kwargs):
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
        if command[0] == "qemu-system-arm":
            return "test QEMU version"
        if command[0] == "git":
            return "host-fixture" if "rev-parse" in command else ""
        return "b" * 64

    def initramfs_fixture(repository, cache, destination, *unused):
        destination.write_bytes(b"host fixture; no ARM execution")

    def guest_fixture(command, directory, *unused):
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
