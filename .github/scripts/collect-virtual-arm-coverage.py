#!/usr/bin/env python3
"""Measure actual host Python and native DNS execution for SonarQube Cloud."""

import gzip
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET

import coverage


REPOSITORY = Path(__file__).resolve().parents[2]
REPORTS = REPOSITORY / ".coverage-reports"
TESTS = ("virtual-arm-host-tools.py", "virtual-arm-evidence.py", "virtual-arm-dns-query.py")


def regression_suite():
    """Load the same stdlib regressions used by canonical repository checks."""
    suite = unittest.TestSuite()
    for filename in TESTS:
        specification = importlib.util.spec_from_file_location(
            "coverage_test_" + filename.replace("-", "_"), REPOSITORY / "tests" / filename)
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(module))
    return suite


def write_native_report(directory):
    """Translate gcov's real line/branch counters into Sonar's generic XML format."""
    notes = list(directory.glob("*.gcno"))
    if len(notes) != 1 or not list(directory.glob("*.gcda")):
        raise RuntimeError("Native DNS coverage requires one instrumented build and execution data")
    subprocess.run(["gcov", "--json-format", "--branch-probabilities", "--branch-counts", str(notes[0])],
                   cwd=directory, check=True, timeout=30)
    inputs = list(directory.glob("*.gcov.json.gz"))
    if len(inputs) != 1:
        raise RuntimeError("gcov did not produce exactly one native DNS execution report")
    with gzip.open(inputs[0], "rt", encoding="utf-8") as stream:
        payload = json.load(stream)
    expected = REPOSITORY / "tools/virtual-arm/dns-query.c"
    files = [record for record in payload["files"] if Path(record["file"]).resolve() == expected]
    if len(files) != 1 or not files[0]["lines"]:
        raise RuntimeError("gcov execution report does not identify the candidate DNS source")
    document = ET.Element("coverage", version="1")
    source = ET.SubElement(document, "file", path=expected.relative_to(REPOSITORY).as_posix())
    covered_lines = covered_branches = total_branches = 0
    for line in files[0]["lines"]:
        covered = line["count"] > 0
        attributes = {"lineNumber": str(line["line_number"]), "covered": str(covered).lower()}
        branches = line.get("branches", [])
        covered_count = sum(branch["count"] > 0 for branch in branches)
        if branches:
            attributes.update(branchesToCover=str(len(branches)), coveredBranches=str(covered_count))
        ET.SubElement(source, "lineToCover", attributes)
        covered_lines += covered
        total_branches += len(branches)
        covered_branches += covered_count
    if not total_branches or not covered_lines or not covered_branches:
        raise RuntimeError("Native DNS report must contain measured line and branch execution")
    ET.indent(document)
    ET.ElementTree(document).write(REPORTS / "native-dns.xml", encoding="utf-8", xml_declaration=True)
    print(f"Native DNS measured coverage: lines={covered_lines}/{len(files[0]['lines'])} "
          f"branches={covered_branches}/{total_branches}")


def main():
    """Run real regressions before producing fresh, candidate-bound coverage reports."""
    os.chdir(REPOSITORY)
    if REPORTS.is_symlink():
        raise RuntimeError("Coverage report directory must not be a symlink")
    REPORTS.mkdir(exist_ok=True)
    for name in ("python.xml", "native-dns.xml", "python.json", ".coverage"):
        (REPORTS / name).unlink(missing_ok=True)
    native = REPORTS / "native"
    if native.exists():
        shutil.rmtree(native)
    native.mkdir()
    os.environ["AGH_DNS_COVERAGE_DIR"] = str(native)
    measured = coverage.Coverage(data_file=str(REPORTS / ".coverage"),
                                 source=["tools/virtual-arm"], branch=True, config_file=False)
    measured.set_option("run:relative_files", True)
    measured.start()
    try:
        result = unittest.TextTestRunner(verbosity=2).run(regression_suite())
    finally:
        measured.stop()
        measured.save()
    if not result.wasSuccessful():
        raise SystemExit("Coverage regressions failed; no successful coverage reports were published")
    measured.xml_report(outfile=str(REPORTS / "python.xml"))
    measured.json_report(outfile=str(REPORTS / "python.json"))
    measured.report(show_missing=True)
    write_native_report(native)


if __name__ == "__main__":
    main()
