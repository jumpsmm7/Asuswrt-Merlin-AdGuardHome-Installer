#!/usr/bin/env python3
"""Exercise acceptance rejection using synthetic evidence, never guest results."""

import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path


CHECKER = Path(__file__).resolve().parents[1] / "tools/virtual-arm/check-evidence.py"
SPEC = importlib.util.spec_from_file_location("virtual_arm_evidence", CHECKER)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class EvidenceRejection(unittest.TestCase):
    """Keep false-success rejection separate from actual ARM feature execution."""

    def setUp(self):
        """Create synthetic repository inputs and one report per architecture."""
        self.temporary = tempfile.TemporaryDirectory(prefix="arm-evidence-policy-")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "repository"
        for directory in ("tests", "tools/virtual-arm", "armv5", "armv7", "armv8"):
            (self.repository / directory).mkdir(parents=True)
        build_source = CHECKER.parent
        for path in build_source.rglob("*"):
            if path.is_file() and (path.parent == build_source and path.name in (
                    "Dockerfile", "build-environments.sh", "environment.py", "rootfs-manifest.py",
                    "check-native-libraries.py", "sources.sha256", "dns-query.c")
                    or path.parent.name in ("configs", "patches")):
                target = self.repository / "tools/virtual-arm" / path.relative_to(build_source)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        self.test = self.repository / "tests/scenario.sh"
        self.test.write_text("#!/bin/sh\nexit 0\n")
        (self.repository / "installer").write_text("#!/bin/sh\nprintf '%s\\n' test\n")
        self.manifest = self.repository / "tools/virtual-arm/features.tsv"
        self.manifest.write_text("\t".join(GATE.MANIFEST_FIELDS) + "\n" +
                                 "hooks\tscenario\ttests/scenario.sh\tfixture\tSynthetic assertion\tFirmware dispatch excluded\n")
        self.rows = GATE.load_manifest(self.manifest, self.repository)
        self.digest = GATE.content_digest(self.repository)
        self.source_digest = GATE.build_source_digest(self.repository)
        self.selection_digest = hashlib.sha256(GATE.selection_text(self.rows).encode()).hexdigest()
        self.paths = {}
        self.reports = {}
        for architecture in GATE.ARCHITECTURES:
            self.create_report(architecture)

    def tearDown(self):
        """Remove the temporary repository and generated evidence files."""
        self.temporary.cleanup()

    def create_report(self, architecture):
        """Build a passing synthetic report and its matching serial artifacts."""
        directory = self.root / "evidence" / architecture
        directory.mkdir(parents=True)
        target = GATE.TARGETS[architecture]
        compiler_flags = {
            "armv5": "-march=armv7-a -mfloat-abi=soft",
            "armv7": "-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard",
            "armv8": "-march=armv8-a",
        }[architecture]
        environment = {
            "schema_version": 1,
            "architecture": architecture,
            "execution_class": "qemu-full-system-tcg",
            "machine": GATE.ENVIRONMENTS[architecture][0],
            "cpu": GATE.ENVIRONMENTS[architecture][1],
            "cpu_options": GATE.CPU_OPTIONS[architecture],
            "target": target,
            "kernel": {"version": "6.1.157", "sha256": "a" * 64,
                       "source_sha256": "b" * 64, "config_sha256": "c" * 64},
            "busybox": {"version": "1.25.1", "sha256": "d" * 64,
                        "source_sha256": "e" * 64, "config_sha256": "f" * 64},
            "compiler": {"target": GATE.COMPILER_TARGETS[architecture], "flags": compiler_flags},
            "native_packages": [{"name": "synthetic", "version": "1", "architecture": "all", "deb_sha256": "1" * 64}],
            "rootfs_manifest_sha256": "2" * 64,
            "source_manifest_sha256": self.source_digest,
        }
        if architecture == "armv5":
            environment["dtb_sha256"] = "7" * 64
        environment_file = directory / "environment.json"
        environment_file.write_text(json.dumps(environment, sort_keys=True) + "\n")
        environment_digest = GATE.file_sha256(environment_file)
        log = directory / "scenario.log"
        log.write_text("Synthetic validator policy fixture; not real execution evidence.\n")
        self.reports[architecture] = {
            "schema_version": 1,
            "status": "pass",
            "guest_complete": True,
            "architecture": architecture,
            "content_digest": self.digest,
            "commit_label": "synthetic-evidence-policy-test",
            "requested_features": ["hooks"],
            "selection_digest": self.selection_digest,
            "environment": environment,
            "environment_digest": environment_digest,
            "guest_boot": {"status": "pass", "reported_architecture": architecture,
                           "machine": GATE.GUEST_MACHINES[architecture],
                           "busybox_version": "1.25.1", "kernel_release": "6.1.157",
                           "token": "synthetic-run-token", "environment_digest": environment_digest,
                           "cpu_features": "none"},
            "execution": {"engine": "qemu-system-tcg", "network": "none", "source_read_only": True,
                          "boot_timeout_seconds": 600, "scenario_timeout_seconds": 600},
            "started_at": "2026-10-08T10:00:00-04:00",
            "finished_at": "2026-10-08T10:00:01-04:00",
            "results": [{"feature": "hooks", "scenario": "scenario", "test": "tests/scenario.sh",
                         "evidence_class": "fixture", "assertions": "Synthetic assertion", "status": "pass",
                         "exit_status": 0, "elapsed_seconds": 1, "source_sha256": GATE.file_sha256(self.test),
                         "log": "scenario.log", "log_sha256": GATE.file_sha256(log)}],
        }
        report = self.reports[architecture]
        token = report["guest_boot"]["token"]
        serial = directory / "serial.log"
        records = [("BOOT", architecture, GATE.GUEST_MACHINES[architecture], "6.1.157", "v1.25.1", environment_digest, "none"),
                   ("START", "hooks", "scenario"), ("END", "hooks", "scenario", "0", "1"), ("DONE", "0")]
        serial.write_text("".join("\t".join(("AGH_VM", token, *record, "")) + "\n" for record in records))
        report["execution"].update(serial_log="serial.log", serial_log_sha256=GATE.file_sha256(serial))
        self.paths[architecture] = directory / "evidence.json"
        self.write_report(architecture)

    def write_report(self, architecture):
        """Persist the current synthetic report for one architecture."""
        self.paths[architecture].write_text(json.dumps(self.reports[architecture]) + "\n")

    def invoke(self, extra=(), architectures=None):
        """Run the evidence gate with optional arguments and architecture paths."""
        arguments = ["--repository", str(self.repository), "--features", "hooks"] + list(extra)
        for architecture in architectures or GATE.ARCHITECTURES:
            arguments.append(str(self.paths[architecture]))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = GATE.main(arguments) or 0
        return result, json.loads(output.getvalue())

    def assert_rejected(self, message, extra=(), architectures=None):
        """Assert that the evidence gate rejects the supplied synthetic inputs."""
        with self.assertRaisesRegex(ValueError, message):
            self.invoke(extra, architectures)

    def test_exact_complete_matrix_unblocks_selected_contract(self):
        """Accept a complete passing matrix and preserve physical release status."""
        status, summary = self.invoke()
        self.assertEqual(status, 0)
        self.assertTrue(summary["unblocks"])
        self.assertEqual(summary["unblocked_features"], ["hooks"])
        self.assertEqual(summary["physical_release_acceptance"], "unchanged")

    def test_partial_execution_never_unblocks(self):
        """Keep partial architecture execution from unblocking the feature."""
        status, summary = self.invoke(["--architectures", "armv5", "--partial"], ["armv5"])
        self.assertEqual(status, 0)
        self.assertFalse(summary["unblocks"])
        self.assertEqual(summary["unblocked_features"], [])
        self.assert_rejected("requires armv5,armv7,armv8", ["--architectures", "armv5"], ["armv5"])

    def test_unknown_empty_duplicate_selection_rejected(self):
        """Reject empty, duplicate, and unknown feature selections."""
        for selection in ("", "hooks,", "unknown", "hooks,hooks"):
            with self.subTest(selection=selection):
                self.assert_rejected("selection|unknown feature", ["--features", selection])

    def test_missing_architecture_and_scenario_rejected(self):
        """Reject reports missing an architecture or its required scenario."""
        self.assert_rejected("missing architecture", architectures=["armv5", "armv7"])
        self.reports["armv5"]["results"] = []
        self.write_report("armv5")
        self.assert_rejected("missing scenarios")

    def test_duplicate_architecture_rejected(self):
        """Reject duplicate architecture reports in the acceptance set."""
        with self.assertRaisesRegex(ValueError, "duplicate evidence architecture"):
            self.invoke(architectures=["armv5", "armv5", "armv7", "armv8"])

    def test_failure_skip_and_timeout_cannot_pass(self):
        """Reject failed, skipped, and timed-out scenario result combinations."""
        original = copy.deepcopy(self.reports["armv5"])
        for status, exit_status in (("skip", 0), ("timeout", 124), ("fail", 1), ("pass", 124)):
            self.reports["armv5"] = copy.deepcopy(original)
            result = self.reports["armv5"]["results"][0]
            result.update(status=status, exit_status=exit_status)
            self.write_report("armv5")
            with self.subTest(status=status, exit_status=exit_status):
                self.assert_rejected("failed/skipped/timed out")

    def test_stale_source_and_test_and_log_rejected(self):
        """Reject evidence whose tested source, test, or log digest is stale."""
        installer = self.repository / "installer"
        original = installer.read_bytes()
        installer.write_bytes(original + b"# runtime edit\n")
        self.assert_rejected("stale tested content")
        installer.write_bytes(original)
        self.reports["armv5"]["results"][0]["source_sha256"] = "0" * 64
        self.write_report("armv5")
        self.assert_rejected("stale test source")
        self.reports["armv5"]["results"][0]["source_sha256"] = GATE.file_sha256(self.test)
        self.write_report("armv5")
        (self.paths["armv5"].parent / "scenario.log").write_text("changed log\n")
        self.assert_rejected("log digest mismatch")

    def test_documentation_and_commit_labels_do_not_change_content(self):
        """Ignore documentation-only files and commit labels in content acceptance."""
        for directory in ("docs", ".tasks", ".git"):
            (self.repository / directory).mkdir()
            (self.repository / directory / "completion.md").write_text("completion text\n")
        self.assertEqual(GATE.content_digest(self.repository), self.digest)
        self.reports["armv5"]["commit_label"] = "later-documentation-commit"
        self.write_report("armv5")
        self.assertTrue(self.invoke()[1]["unblocks"])

    def test_archive_configuration_and_mode_changes_invalidate_evidence(self):
        """Reject changed architecture archives and executable-mode mutations."""
        archive = self.repository / "armv5/archive.tar.gz"
        archive.write_bytes(b"changed architecture artifact")
        self.assert_rejected("stale tested content")
        archive.unlink()
        self.test.chmod(0o755)
        self.assert_rejected("stale tested content")

    def test_host_user_mode_or_wrong_guest_rejected(self):
        """Reject user-mode evidence and guests reporting the wrong architecture."""
        self.reports["armv5"]["environment"]["execution_class"] = "qemu-user"
        self.write_report("armv5")
        self.assert_rejected("user-mode")
        self.reports["armv5"]["environment"]["execution_class"] = "qemu-full-system-tcg"
        self.reports["armv5"]["guest_boot"]["reported_architecture"] = "armv7"
        self.write_report("armv5")
        self.assert_rejected("booted guest architecture")

    def test_environment_modification_rejected(self):
        """Reject evidence when cached machine or CPU metadata changes."""
        self.reports["armv5"]["environment"]["cpu"] = "cortex-a15"
        self.write_report("armv5")
        self.assert_rejected("machine/CPU")

    def test_armv5_is_an_armv7_software_float_target(self):
        """Require the armv5 package contract to model an RT-AC68U-class ARMv7 target."""
        target = self.reports["armv5"]["environment"]["target"]
        self.assertEqual(target["router_model"], "ASUS RT-AC68U")
        self.assertEqual(target["cpu_architecture"], "armv7")
        self.assertEqual(target["float_abi"], "soft")
        self.assertEqual(target["fpu"], "none")
        self.assertEqual(self.reports["armv5"]["guest_boot"]["machine"], "armv7l")
        self.reports["armv5"]["environment"]["target"] = dict(target, cpu_architecture="armv5")
        self.write_report("armv5")
        self.assert_rejected("package ABI and CPU target metadata")

    def test_armv5_hardware_float_options_rejected(self):
        """Reject armv5 evidence that enables hardware floating-point execution."""
        environment = self.reports["armv5"]["environment"]
        environment["cpu_options"] = "cortex-a9"
        self.write_report("armv5")
        self.assert_rejected("CPU feature options")
        environment["cpu_options"] = GATE.CPU_OPTIONS["armv5"]
        environment["compiler"]["flags"] = "-march=armv7-a -mfloat-abi=hard -mfpu=vfpv3-d16"
        self.write_report("armv5")
        self.assert_rejected("software-float/no-FPU")

    def test_armv5_device_tree_provenance_is_required(self):
        """Require device-tree provenance for the vexpress armv5 compatibility guest."""
        environment = self.reports["armv5"]["environment"]
        environment.pop("dtb_sha256")
        self.write_report("armv5")
        self.assert_rejected("armv5 device tree")

    def test_other_targets_reject_device_tree_provenance(self):
        """Reject device-tree metadata attached to targets that do not use one."""
        environment = self.reports["armv7"]["environment"]
        environment["dtb_sha256"] = "7" * 64
        self.write_report("armv7")
        self.assert_rejected("unexpected device tree metadata")

    def test_guest_completion_and_serial_artifacts_required(self):
        """Require completed guest markers and an intact serial log artifact."""
        self.reports["armv5"]["guest_complete"] = False
        self.write_report("armv5")
        self.assert_rejected("guest completion")
        self.reports["armv5"]["guest_complete"] = True
        self.write_report("armv5")
        serial = self.paths["armv5"].parent / "serial.log"
        original = serial.read_text()
        serial.write_text(original.replace("DONE\t0", "DONE\t1"))
        self.assert_rejected("serial log digest")
        self.reports["armv5"]["execution"]["serial_log_sha256"] = GATE.file_sha256(serial)
        self.write_report("armv5")
        self.assert_rejected("serial boot/scenario/completion")
        serial.unlink()
        self.assert_rejected("serial log artifact")

    def test_current_build_source_fingerprint_required(self):
        """Reject evidence built from a stale native environment source fingerprint."""
        environment = self.reports["armv5"]["environment"]
        environment["source_manifest_sha256"] = "0" * 64
        path = self.paths["armv5"].parent / "environment.json"
        path.write_text(json.dumps(environment, sort_keys=True) + "\n")
        digest = GATE.file_sha256(path)
        self.reports["armv5"]["environment_digest"] = digest
        self.reports["armv5"]["guest_boot"]["environment_digest"] = digest
        self.write_report("armv5")
        self.assert_rejected("stale native build source")

    def test_provenance_error_cannot_leave_successful_status(self):
        """Reject a report that records a provenance or runtime error as successful."""
        self.reports["armv5"]["error"] = "Cached native root filesystem was modified"
        self.write_report("armv5")
        self.assert_rejected("provenance or runtime error")

    def test_scope_expansion_and_log_escape_rejected(self):
        """Reject expanded feature scope and log paths that escape the report directory."""
        self.reports["armv5"]["requested_features"] = ["hooks", "dns"]
        self.write_report("armv5")
        self.assert_rejected("feature scope")
        self.reports["armv5"]["requested_features"] = ["hooks"]
        self.reports["armv5"]["results"][0]["log"] = "../outside.log"
        self.write_report("armv5")
        self.assert_rejected("log escapes")

    def test_duplicate_json_keys_rejected(self):
        """Reject evidence JSON containing duplicate object keys."""
        self.paths["armv5"].write_text('{"architecture":"armv5","architecture":"armv7"}\n')
        self.assert_rejected("duplicate JSON key")

    def test_rejected_recheck_removes_previous_green_summary(self):
        """Remove a stale green summary when a later evidence recheck is rejected."""
        summary = self.root / "acceptance.json"
        self.invoke(["--summary", str(summary)])
        self.assertTrue(json.loads(summary.read_text())["unblocks"])
        self.reports["armv5"]["results"][0]["status"] = "fail"
        self.write_report("armv5")
        self.assert_rejected("failed/skipped/timed out", ["--summary", str(summary)])
        self.assertFalse(summary.exists())

    def test_summary_preserves_unrelated_files_and_symlink_targets(self):
        """Refuse unrelated or linked output leaves before changing host files."""
        sentinel = self.root / "sentinel.json"
        original = '{"private":"keep this file"}\n'
        sentinel.write_text(original)
        self.assert_rejected("not an ARM acceptance summary", ["--summary", str(sentinel)])
        self.assertEqual(sentinel.read_text(), original)
        link = self.root / "summary-link.json"
        link.symlink_to(sentinel)
        self.assert_rejected("must not be a symlink", ["--summary", str(link)])
        self.assertTrue(link.is_symlink())
        self.assertEqual(sentinel.read_text(), original)

    def test_summary_accepts_explicit_external_output_directory(self):
        """Allow a selected output outside the repository without losing scope."""
        summary = self.root / "external-output" / "nested" / "acceptance.json"
        status, expected = self.invoke(["--summary", str(summary)])
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(summary.read_text()), expected)
        self.assertEqual(list(summary.parent.glob(".arm-acceptance-*")), [])

    def test_selected_repository_helpers_are_hashed_never_executed(self):
        """Do not execute Python helpers from a caller-selected repository."""
        helper = self.repository / "tools/virtual-arm/environment.py"
        helper.write_text('raise RuntimeError("untrusted repository helper executed")\n')
        self.assertRegex(GATE.build_source_digest(self.repository), r"^[0-9a-f]{64}$")

    def test_builder_artifact_symlink_escape_is_rejected(self):
        """Reject linked builder input before hashing data outside its source root."""
        sentinel = self.root / "outside-source"
        sentinel.write_text("host-only sentinel\n")
        source = self.repository / "tools/virtual-arm"
        helper = source / "environment.py"
        helper.unlink()
        helper.symlink_to(sentinel)
        with self.assertRaisesRegex(ValueError, "nonregular build artifact"):
            GATE.build_source_digest(self.repository)

    def test_evidence_symlink_is_rejected_without_reading_target(self):
        """Reject discovered evidence symlinks rather than following host targets."""
        report = self.paths["armv5"]
        outside = self.root / "outside-evidence.json"
        outside.write_text("not JSON; must never be parsed\n")
        report.unlink()
        report.symlink_to(outside)
        self.assert_rejected("nonregular JSON artifact")


if __name__ == "__main__":
    unittest.main(verbosity=2)
