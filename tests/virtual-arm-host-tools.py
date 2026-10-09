#!/usr/bin/env python3
"""Exercise host provenance, image construction and serial failure boundaries."""

import contextlib
import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import runpy
import shutil
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY = Path(__file__).resolve().parents[1]
SOURCE = REPOSITORY / "tools/virtual-arm"


def load_tool(name):
    """Import the actual host tool without replacing its implementation."""
    specification = importlib.util.spec_from_file_location(
        "host_test_" + name.replace("-", "_"), SOURCE / (name + ".py"))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


ROOTFS = load_tool("rootfs-manifest")
ENVIRONMENT = load_tool("environment")
LIBRARIES = load_tool("check-native-libraries")
RUNNER = load_tool("run-matrix")


class HostArtifactValidation(unittest.TestCase):
    """Check genuine temporary files and guest symlinks without booting QEMU."""

    def setUp(self):
        """Create a private directory for each artifact mutation test."""
        self.temporary = tempfile.TemporaryDirectory(prefix="virtual-arm-host-tools-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_rootfs_tracks_modes_bytes_and_guest_symlinks(self):
        """Bind rootfs identity to content and modes without following guest links."""
        directory = self.root / "rootfs"
        (directory / "bin").mkdir(parents=True)
        binary = directory / "bin/tool"
        binary.write_bytes(b"guest binary")
        (directory / "tool").symlink_to("/bin/tool")
        first = ROOTFS.rootfs_content_digest(directory)
        records = ROOTFS.rootfs_records(directory)
        self.assertEqual([record["path"] for record in records], ["bin", "bin/tool", "tool"])
        self.assertEqual(records[-1]["target"], "/bin/tool")
        binary.chmod(0o755)
        self.assertNotEqual(first, ROOTFS.rootfs_content_digest(directory))
        binary.write_bytes(b"changed guest binary")
        self.assertNotEqual(first, ROOTFS.rootfs_content_digest(directory))
        os.mkfifo(directory / "unexpected-fifo")
        with self.assertRaises(ValueError):
            ROOTFS.rootfs_records(directory)

    def test_rootfs_cli_and_usage(self):
        """Exercise the published manifest command and reject missing arguments."""
        with mock.patch.object(sys, "argv", ["rootfs-manifest.py", str(self.root)]), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            runpy.run_path(str(SOURCE / "rootfs-manifest.py"), run_name="__main__")
        self.assertEqual(output.getvalue().strip(), ROOTFS.rootfs_content_digest(self.root))
        with mock.patch.object(sys, "argv", ["rootfs-manifest.py"]), self.assertRaises(SystemExit):
            runpy.run_path(str(SOURCE / "rootfs-manifest.py"), run_name="__main__")

    def test_guest_library_links_are_confined(self):
        """Resolve guest absolute/relative links and reject parent escape or cycles."""
        (self.root / "lib").mkdir()
        library = self.root / "lib/libguest.so"
        library.write_bytes(b"guest library")
        (self.root / "absolute").symlink_to("/lib/libguest.so")
        (self.root / "relative").symlink_to("lib/../lib/libguest.so")
        self.assertEqual(LIBRARIES.guest_file(self.root, "/./absolute"), library)
        self.assertEqual(LIBRARIES.guest_file(self.root, "relative"), library)
        (self.root / "escape").symlink_to("../outside")
        (self.root / "cycle").symlink_to("cycle")
        for path in ("escape", "cycle", "../../host"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                LIBRARIES.guest_file(self.root, path)

    def test_native_library_checker_accepts_and_rejects_real_elf_dependencies(self):
        """Inspect an actual native ELF, then remove its required library/interpreter."""
        binary = self.root / "bin/tool"
        binary.parent.mkdir()
        shutil.copyfile(shutil.which("true"), binary)
        # readelf remains real; only the guest dependencies are small fixture files.
        dynamic = RUNNER.checked_output(["readelf", "-d", str(binary)])
        headers = RUNNER.checked_output(["readelf", "-l", str(binary)])
        dependencies = list(LIBRARIES.dynamic_dependencies(dynamic))
        interpreters = list(LIBRARIES.program_interpreters(headers))
        self.assertTrue(dependencies)
        self.assertTrue(interpreters)
        for dependency in dependencies:
            (binary.parent / dependency).write_bytes(b"guest dependency")
        for interpreter in interpreters:
            guest = self.root / interpreter.lstrip("/")
            guest.parent.mkdir(parents=True, exist_ok=True)
            guest.write_bytes(b"guest interpreter")
        (self.root / "not-elf").write_text("ordinary file\n")
        (self.root / "guest-link").symlink_to("/bin/tool")
        LIBRARIES.check(self.root)
        (binary.parent / dependencies[0]).unlink()
        with self.assertRaisesRegex(SystemExit, "needs"):
            LIBRARIES.check(self.root)
        (binary.parent / dependencies[0]).write_bytes(b"restored dependency")
        (self.root / interpreters[0].lstrip("/")).unlink()
        with self.assertRaisesRegex(SystemExit, "needs interpreter"):
            LIBRARIES.check(self.root)

    def test_library_cli_and_malformed_readelf_lines(self):
        """Run the library command and ignore incomplete or irrelevant readelf fields."""
        self.assertEqual(list(LIBRARIES.dynamic_dependencies("(NEEDED) missing brackets\n")), [])
        self.assertEqual(list(LIBRARIES.program_interpreters("Requesting program interpreter: missing bracket")), [])
        with mock.patch.object(sys, "argv", ["check-native-libraries.py", str(self.root)]):
            runpy.run_path(str(SOURCE / "check-native-libraries.py"), run_name="__main__")
        with mock.patch.object(sys, "argv", ["check-native-libraries.py"]), self.assertRaises(SystemExit):
            runpy.run_path(str(SOURCE / "check-native-libraries.py"), run_name="__main__")

    def test_environment_provenance_binds_actual_artifacts_for_all_targets(self):
        """Record all package/CPU identities using actual hashed temporary build outputs."""
        native = ("usr/bin/jq", "usr/sbin/curl", "usr/sbin/dnsmasq", "usr/sbin/ip",
                  "usr/bin/flock", "usr/bin/timeout", "usr/bin/gawk", "usr/sbin/openssl",
                  "usr/bin/agh-dns-query", "bin/busybox")
        profiles = (("armv5", "arm-linux-gnueabi-", "armel", "-mfloat-abi=soft"),
                    ("armv7", "arm-linux-gnueabihf-", "armhf", "-mfloat-abi=hard"),
                    ("armv8", "aarch64-linux-gnu-", "arm64", "-march=armv8-a"))
        for architecture, compiler, debian, flags in profiles:
            target = self.root / architecture
            for path in native:
                artifact = target / "rootfs" / path
                artifact.parent.mkdir(parents=True, exist_ok=True)
                artifact.write_bytes(path.encode())
            release = target / "build-kernel/include/config/kernel.release"
            release.parent.mkdir(parents=True)
            release.write_text("6.1.157\n")
            (target / "kernel").write_bytes(b"native kernel")
            (target / "build-kernel/.config").write_bytes(b"kernel configuration")
            (target / "build-busybox").mkdir()
            (target / "build-busybox/.config").write_bytes(b"BusyBox configuration")
            if architecture == "armv5":
                (target / "dtb").write_bytes(b"older ARMv7 device tree")
            with mock.patch.object(ENVIRONMENT, "command_line", return_value="host tool version"):
                ENVIRONMENT.record(SOURCE, target, architecture, compiler, flags, debian)
            result = json.loads((target / "environment.json").read_text())
            self.assertEqual(result["target"], RUNNER.TARGETS[architecture])
            self.assertEqual(result["rootfs_content_digest"], ROOTFS.rootfs_content_digest(target / "rootfs"))
            self.assertEqual(result["kernel_sha256"], hashlib.sha256(b"native kernel").hexdigest())
            self.assertEqual("dtb_sha256" in result, architecture == "armv5")

    def test_environment_hashes_are_confined(self):
        """Reject substituted or out-of-root artifacts while hashing valid files."""
        artifact = self.root / "artifact"
        artifact.write_bytes(b"real artifact")
        self.assertEqual(ENVIRONMENT.sha256(artifact, self.root), hashlib.sha256(b"real artifact").hexdigest())
        (self.root / "link").symlink_to(artifact)
        for path in (self.root / "link", self.root / "missing", self.root, SOURCE / "environment.py"):
            with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                ENVIRONMENT.sha256(path, self.root)

    def test_environment_commands_and_invalid_profile(self):
        """Cover provenance CLI dispatch and validate compiler/package identities."""
        self.assertEqual(ENVIRONMENT.command_line(sys.executable, "--version").split()[0], "Python")
        with mock.patch.object(sys, "argv", ["environment.py", "source-digest", str(SOURCE)]), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            runpy.run_path(str(SOURCE / "environment.py"), run_name="__main__")
        self.assertEqual(output.getvalue().strip(), ENVIRONMENT.source_digest(SOURCE))
        with mock.patch.object(sys, "argv", ["environment.py"]), self.assertRaises(SystemExit):
            runpy.run_path(str(SOURCE / "environment.py"), run_name="__main__")
        with self.assertRaises((ValueError, SystemExit)):
            ENVIRONMENT.record(SOURCE, self.root, "armv5", "aarch64-linux-gnu-", "", "armel")


class HostRunnerValidation(unittest.TestCase):
    """Exercise archive and serial parsing using host fixtures, never ARM acceptance."""

    def test_serial_failure_regression_executes_in_process(self):
        """Reuse canonical real-child protocol regressions under the coverage tracer."""
        fixture = REPOSITORY / "tests/virtual-arm-runner-failure.sh"
        before, marker, after = fixture.read_text().partition("<<'PYTHON'\n")
        self.assertTrue(marker and "python3 -" in before)
        program, end, _ = after.partition("\nPYTHON\n")
        self.assertTrue(end)
        with mock.patch.object(sys, "argv", ["-", str(REPOSITORY)]):
            exec(compile(program, str(fixture), "exec"), {"__name__": "__main__"})

    def test_qemu_commands_keep_machine_cpu_and_container_boundaries(self):
        """Require old software-float CPU options and isolated fallback Docker arguments."""
        with tempfile.TemporaryDirectory(prefix="virtual-arm-command-") as temporary:
            root = Path(temporary)
            (root / "dtb").write_bytes(b"device tree")
            for architecture in RUNNER.MACHINES:
                with mock.patch.object(RUNNER.shutil, "which", return_value="/usr/bin/qemu"):
                    command = RUNNER.qemu_command(architecture, root, root / "initramfs", "token")
                self.assertIn(RUNNER.CPU_OPTIONS[architecture], command)
                self.assertIn("none", command)
                with mock.patch.object(RUNNER.shutil, "which", side_effect=[None, "/usr/bin/docker"]):
                    command = RUNNER.qemu_command(architecture, root, root / "initramfs", "token")
                self.assertEqual(command[:3], ["docker", "run", "--rm"])
                self.assertIn("--read-only", command)
                self.assertIn("ALL", command)
            with mock.patch.object(RUNNER.shutil, "which", return_value=None), self.assertRaises(ValueError):
                RUNNER.qemu_command("armv7", root, root / "initramfs", "token")

    def test_initramfs_packs_actual_files_links_and_rejects_special_entries(self):
        """Construct a real gzip/newc archive with controlled repository and guest inputs."""
        with tempfile.TemporaryDirectory(prefix="virtual-arm-image-") as temporary:
            root = Path(temporary)
            repository = root / "repo"
            cache = root / "cache"
            repository.mkdir()
            for runtime in RUNNER.RUNTIME_FILES:
                (repository / runtime).write_text("#!/bin/sh\n")
                (repository / (runtime + ".sha256sum")).write_text("fixture checksum\n")
            (repository / "tests").mkdir()
            (repository / "tests/example.sh").write_text("#!/bin/sh\n")
            (repository / "tests/fixtures").mkdir()
            (repository / "tests/fixtures/input").write_text("fixture data\n")
            (repository / "tools/virtual-arm").mkdir(parents=True)
            for script in ("guest-init.sh", "guest-runner.sh"):
                (repository / "tools/virtual-arm" / script).write_text("#!/bin/sh\n")
            (cache / "rootfs/bin").mkdir(parents=True)
            (cache / "rootfs/bin/busybox").write_bytes(b"guest busybox")
            (cache / "rootfs/bin/sh").symlink_to("busybox")
            destination = root / "initramfs.gz"
            rows = [["hooks", "example", "tests/example.sh"]]
            RUNNER.build_initramfs(repository, cache, destination, rows, "armv7", "safe=1\n", b"selection\n")
            with gzip.open(destination, "rb") as stream:
                archive = stream.read()
            self.assertTrue(archive.startswith(b"070701"))
            self.assertIn(b"repo/tests/fixtures/input\0", archive)
            self.assertIn(b"TRAILER!!!\0", archive)
            os.mkfifo(cache / "rootfs/unsupported")
            with self.assertRaises(ValueError):
                RUNNER.build_initramfs(repository, cache, destination, rows, "armv7", "", b"")
            with self.assertRaises(ValueError):
                RUNNER.build_initramfs(repository, root / "missing", destination, rows, "armv7", "", b"")


if __name__ == "__main__":
    unittest.main(verbosity=2)
