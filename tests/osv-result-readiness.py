#!/usr/bin/env python3
"""Prevent scanner failures from becoming empty successful OSV reporter output."""

import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / ".github/scripts/run-osv-scan.sh"
VALIDATOR = ROOT / ".github/scripts/check-osv-results.py"
EMPTY = {"results": None, "experimental_config": {"licenses": {"summary": False, "allowlist": None}}}
VULNERABLE = copy.deepcopy(EMPTY)
VULNERABLE["results"] = [{
    "source": {"path": "/source/requirements.txt", "type": "lockfile"},
    "packages": [{
        "package": {"name": "mcp", "version": "1.29.0", "ecosystem": "PyPI"},
        "vulnerabilities": [{"id": "GHSA-84m7-p3x7-pcfv", "modified": "2026-01-01T00:00:00Z"}],
        "groups": [{"ids": ["GHSA-84m7-p3x7-pcfv"], "aliases": None, "max_severity": "7.5"}],
    }],
}]


class ResultReadiness(unittest.TestCase):
    """Exercise production publication with scanner execution as the only modeled boundary."""

    def setUp(self):
        """Reserve an isolated checkout, runner directory, and deterministic Docker boundary."""
        self.temporary = tempfile.TemporaryDirectory(prefix="osv-readiness-")
        self.root = Path(self.temporary.name)
        self.runner = self.root / "runner"
        self.checkout = self.root / "checkout"
        self.bin = self.root / "bin"
        for directory in (self.runner, self.checkout, self.bin):
            directory.mkdir()
        self.output = self.root / "github-output"
        self.arguments = self.root / "docker-arguments.json"
        docker = self.bin / "docker"
        docker.write_text("""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
Path(os.environ['OSV_ARGUMENTS']).write_text(json.dumps(args))
if args[0] == 'pull':
    print('Image pull progress', file=sys.stderr)
    sys.exit(int(os.environ.get('OSV_PULL_EXIT', '0')))
output = None
for i, arg in enumerate(args):
    if arg == '--volume' and args[i + 1].endswith(':/osv-output'):
        output = Path(args[i + 1][:-len(':/osv-output')])
if output is None:
    sys.exit(125)
text = os.environ.get('OSV_RESULT')
if text is not None:
    (output / 'results.json').write_text(text)
sys.stdout.write(os.environ.get('OSV_STDOUT', ''))
sys.stderr.write(os.environ.get('OSV_STDERR', ''))
sys.exit(int(os.environ.get('OSV_EXIT', '0')))
""", encoding="utf-8")
        docker.chmod(0o700)
        move = self.bin / "mv"
        move.write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
import sys
mode = os.environ.get('OSV_MOVE_MODE')
if mode == 'failure':
    sys.exit(1)
if mode == 'late-symlink':
    Path(sys.argv[-1]).symlink_to(os.environ['OSV_FOREIGN_RESULT'])
os.execv(os.environ['OSV_REAL_MV'], ['mv', *sys.argv[1:]])
""", encoding="utf-8")
        move.chmod(0o700)
        self.environment = os.environ.copy()
        self.environment.update(PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
                                RUNNER_TEMP=str(self.runner), GITHUB_OUTPUT=str(self.output),
                                OSV_ARGUMENTS=str(self.arguments), OSV_REAL_MV=shutil.which("mv"))

    def tearDown(self):
        """Remove only the per-test owned fixture."""
        self.temporary.cleanup()

    def run_scan(self, payload=EMPTY, status=0, diagnostics="", name="new-results.json", scanner=SCANNER):
        """Run the real wrapper and validator, modeling scanner bytes, status, and diagnostics."""
        environment = self.environment.copy()
        environment.update(OSV_EXIT=str(status), OSV_STDERR=diagnostics)
        if payload is not None:
            environment["OSV_RESULT"] = json.dumps(payload) if not isinstance(payload, str) else payload
        return subprocess.run(["sh", str(scanner), name], cwd=self.checkout, env=environment,
                              capture_output=True, text=True, timeout=10)

    def assert_not_ready(self, result):
        """A failed scan must leave neither published results nor a successful readiness output."""
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.checkout / "new-results.json").exists())
        if self.output.is_file():
            self.assertNotIn("ready=true", self.output.read_text())
        self.assertFalse(list(self.checkout.glob(".new-results.json.*")))
        self.assertFalse(list(self.runner.glob("osv-scan.*/results.json")))

    def test_clean_and_zero_package_results(self):
        """Both nil and empty Go slices are legitimate clean scanner output."""
        for sources in (None, []):
            with self.subTest(results=sources):
                payload = copy.deepcopy(EMPTY)
                payload["results"] = sources
                result = self.run_scan(payload)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("ready=true", self.output.read_text())
                self.assertEqual(json.loads((self.checkout / "new-results.json").read_text()), payload)
        args = json.loads(self.arguments.read_text())
        self.assertIn("--pull=never", args)
        self.assertIn("--allow-no-lockfiles", args)
        self.assertIn("--verbosity=error", args)
        self.assertIn(f"{self.checkout}:/source:ro", args)
        self.assertFalse(any("docker.sock" in arg for arg in args))

    def test_vulnerability_status_remains_reportable(self):
        """Exit one is preserved for the reporter, including valid ignored-analysis groups."""
        for ignored in (False, True):
            with self.subTest(ignored=ignored):
                payload = copy.deepcopy(VULNERABLE)
                if ignored:
                    payload["results"][0]["packages"][0]["groups"][0]["experimental_analysis"] = {
                        "GHSA-84m7-p3x7-pcfv": {"called": False, "unimportant": True}}
                result = self.run_scan(payload, status=1)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("scanner_exit_code=1", self.output.read_text())
                self.assertIn("ready=true", self.output.read_text())
                self.assertEqual(json.loads((self.checkout / "new-results.json").read_text()), payload)

    def test_missing_result_cannot_reuse_stale_clean_file(self):
        """A prior tracked or untracked result cannot hide a scanner that wrote no output."""
        (self.checkout / "new-results.json").write_text(json.dumps(EMPTY))
        self.assert_not_ready(self.run_scan(None))

    def test_bad_json_never_becomes_ready(self):
        """Empty, truncated, foreign and incomplete data never reaches the permissive reporter."""
        payloads = ["", '{"results":', {}, {"error": "scan failed"}, [],
                    {"results": [], "experimental_config": {}},
                    {"results": "clean", "experimental_config": EMPTY["experimental_config"]},
                    {"results": [{}], "experimental_config": EMPTY["experimental_config"]}]
        for payload in payloads:
            with self.subTest(payload=payload):
                self.assert_not_ready(self.run_scan(payload))

    def test_operational_exit_codes_refuse_even_valid_json(self):
        """Complete-looking output cannot mask API, configuration, process or scanner errors."""
        for status in (2, 125, 126, 127, 128, 129, 130, 137):
            with self.subTest(status=status):
                self.assert_not_ready(self.run_scan(EMPTY, status=status))

    def test_partial_scan_diagnostics_refuse_even_vulnerability_exit(self):
        """Exit one takes precedence upstream, so error-level stderr independently blocks partial scans."""
        for status in (0, 1):
            with self.subTest(status=status):
                self.assert_not_ready(self.run_scan(VULNERABLE, status=status,
                                                    diagnostics="Failed to extract package sources\n"))
        logs = list(self.runner.glob("osv-scan.*/stderr.log"))
        self.assertEqual(len(logs), 2)
        self.assertTrue(all("Failed to extract" in path.read_text() for path in logs))

    def test_source_result_symlink_is_not_followed(self):
        """Refuse a foreign result link while preserving its target and link."""
        target = self.root / "foreign-result"
        target.write_text("foreign content")
        result_path = self.checkout / "new-results.json"
        result_path.symlink_to(target)
        result = self.run_scan(EMPTY)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(result_path.is_symlink())
        self.assertEqual(target.read_text(), "foreign content")
        self.assertFalse(self.arguments.exists())

    def test_reject_unknown_result_filename(self):
        """A caller cannot direct cleanup or publication to another path."""
        result = self.run_scan(name="../foreign-result")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.arguments.exists())

    def test_validator_accepts_only_the_fixed_local_result_name(self):
        """Direct validator calls cannot select a foreign path or bypass argument validation."""
        result_path = self.checkout / "results.json"
        result_path.write_text(json.dumps(EMPTY))
        foreign = self.root / "foreign-result.json"
        foreign.write_text(json.dumps(EMPTY))
        for arguments in ([], ["../foreign-result.json"], [str(foreign)],
                          ["results.json", "extra"], ["./results.json"]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, str(VALIDATOR), *arguments],
                                        cwd=self.checkout, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        result = subprocess.run([sys.executable, str(VALIDATOR), "results.json"],
                                cwd=self.checkout, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(foreign.read_text()), EMPTY)

    def test_validator_requires_a_regular_local_result(self):
        """The fixed filename still refuses missing files, directories and foreign links."""
        result_path = self.checkout / "results.json"
        foreign = self.root / "foreign-result.json"
        foreign.write_text(json.dumps(EMPTY))
        for kind in ("missing", "directory", "symlink"):
            with self.subTest(kind=kind):
                if kind == "directory":
                    result_path.mkdir()
                elif kind == "symlink":
                    result_path.symlink_to(foreign)
                result = subprocess.run([sys.executable, str(VALIDATOR), "results.json"],
                                        cwd=self.checkout, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                if result_path.is_dir():
                    result_path.rmdir()
                elif result_path.is_symlink():
                    result_path.unlink()
        self.assertEqual(json.loads(foreign.read_text()), EMPTY)

    def test_failed_atomic_publication_removes_owned_stage(self):
        """A publication failure leaves no result or staging file that a reporter could consume."""
        self.environment["OSV_MOVE_MODE"] = "failure"
        self.assert_not_ready(self.run_scan(EMPTY))

    def test_atomic_publication_does_not_follow_a_late_result_symlink(self):
        """The final rename replaces a raced result link while its foreign target remains intact."""
        target = self.root / "foreign-result"
        target.write_text("foreign content")
        self.environment.update(OSV_MOVE_MODE="late-symlink", OSV_FOREIGN_RESULT=str(target))
        result = self.run_scan(EMPTY)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(target.read_text(), "foreign content")
        self.assertFalse((self.checkout / "new-results.json").is_symlink())
        self.assertEqual(json.loads((self.checkout / "new-results.json").read_text()), EMPTY)

    def test_readiness_output_failure_removes_published_result(self):
        """A failed output write cannot leave a reportable result with unrecorded readiness."""
        self.output.mkdir()
        self.assert_not_ready(self.run_scan(EMPTY))

    def test_prepare_preserves_complete_tools_before_checkout(self):
        """The baseline may remove repository scripts; the private copies remain sufficient."""
        result = self.run_scan(name="prepare")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.output.read_text().strip()
        self.assertTrue(output.startswith("tool_directory="))
        directory = Path(output.split("=", 1)[1])
        self.assertEqual((directory / SCANNER.name).read_bytes(), SCANNER.read_bytes())
        self.assertEqual((directory / VALIDATOR.name).read_bytes(), VALIDATOR.read_bytes())
        self.output.unlink()
        result = self.run_scan(EMPTY, scanner=directory / SCANNER.name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ready=true", self.output.read_text())

    def test_failed_pull_does_not_publish_tools_or_readiness(self):
        """Image retrieval failure leaves no usable setup outputs or owned partial tool directory."""
        self.environment["OSV_PULL_EXIT"] = "1"
        result = self.run_scan(name="prepare")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.runner.glob("osv-tools.*")))

    def test_baseline_and_full_names_share_the_validation_contract(self):
        """Missing-file refusals cover the original baseline and full-scan pathways too."""
        for name in ("old-results.json", "results.json"):
            with self.subTest(name=name):
                result = self.run_scan(None, name=name)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.checkout / name).exists())
                if self.output.exists():
                    self.assertNotIn("ready=true", self.output.read_text())


if __name__ == "__main__":
    unittest.main()
