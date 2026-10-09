#!/usr/bin/env python3
"""Select ARM feature contracts and verify exact-candidate execution evidence."""

import argparse
import csv
import hashlib
import importlib.util
import json
import re
import stat
import sys
import tempfile
from datetime import datetime
from pathlib import Path


ARCHITECTURES = ("armv5", "armv7", "armv8")
ENVIRONMENTS = {
    "armv5": ("vexpress-a9", "cortex-a9"),
    "armv7": ("virt", "cortex-a15"),
    "armv8": ("virt", "cortex-a53"),
}
# Product archive labels and guest CPU identities are deliberately separate.
# armv5 is the software-float compatibility archive used by the older
# RT-AC68U-class ARMv7 Cortex-A9 target; it is not an ARMv5 CPU guest.
CPU_OPTIONS = {
    "armv5": "cortex-a9,vfp=off,neon=off",
    "armv7": "cortex-a15",
    "armv8": "cortex-a53",
}
COMPILER_TARGETS = {
    "armv5": "arm-linux-gnueabi-",
    "armv7": "arm-linux-gnueabihf-",
    "armv8": "aarch64-linux-gnu-",
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
GUEST_MACHINES = {architecture: target["guest_uname"] for architecture, target in TARGETS.items()}
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
IDENTIFIER = re.compile(r"[a-z0-9][a-z0-9_-]*\Z")
MANIFEST_FIELDS = ("feature", "scenario", "test", "evidence_class", "assertions", "exclusions")
ACCEPTANCE_SCOPE = "Only the selected manifest assertions at this tested content digest"


def require(condition, message):
    """Reject an unsupported, incomplete, or inconsistent acceptance record."""
    if not condition:
        raise ValueError(message)


def file_sha256(path):
    """Hash a file without loading architecture archives into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unique_object(pairs):
    """Reject duplicate JSON keys instead of accepting a rewritten assertion."""
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    """Read a JSON object using the evidence's strict duplicate-key policy."""
    require(path.is_file() and not path.is_symlink(), f"missing or nonregular JSON artifact: {path}")
    with path.open(encoding="utf-8") as handle:
        result = json.load(handle, object_pairs_hook=unique_object)
    require(isinstance(result, dict), f"expected a JSON object: {path}")
    return result


def load_manifest(path, repository):
    """Load nonempty, unique contracts whose tests are regular repository files."""
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        require(tuple(reader.fieldnames or ()) == MANIFEST_FIELDS, "unexpected feature manifest columns")
        rows = list(reader)
    require(rows, "empty feature manifest")
    scenarios = set()
    tests = set()
    for row in rows:
        require(None not in row and all(row.get(key) for key in MANIFEST_FIELDS), "incomplete manifest row")
        require(IDENTIFIER.fullmatch(row["feature"]) and IDENTIFIER.fullmatch(row["scenario"]), "invalid feature/scenario ID")
        require(row["scenario"] not in scenarios, f"duplicate scenario: {row['scenario']}")
        require(row["test"] not in tests, f"duplicate test: {row['test']}")
        require(row["evidence_class"] in ("fixture", "native"), "unsupported evidence class")
        test = Path(row["test"])
        require(test.parts and test.parts[0] == "tests" and ".." not in test.parts, "test must be under tests/")
        require(not test.is_absolute(), "absolute test path")
        target = repository / test
        require(target.is_file() and not target.is_symlink(), f"missing or nonregular scenario test: {test}")
        require(target.resolve().is_relative_to(repository.resolve()), "test escapes repository")
        scenarios.add(row["scenario"])
        tests.add(row["test"])
    return rows


def selection(value, supported, label):
    """Require an explicit nonempty selection without unknown or duplicate IDs."""
    if value == "all":
        return list(supported)
    selected = value.split(",")
    require(all(selected) and all(item == item.strip() for item in selected), f"empty or malformed {label} selection")
    require(len(selected) == len(set(selected)), f"duplicate {label} selection")
    require(set(selected) <= set(supported), f"unknown {label}: {','.join(sorted(set(selected) - set(supported)))}")
    return selected


def selection_text(rows):
    """Return the exact three-column execution list used by the guest runner."""
    return "".join(f"{row['feature']}\t{row['scenario']}\t{row['test']}\n" for row in rows)


def tested_directory_paths(root):
    """Enumerate executable directory inputs without bytecode or documentation."""
    for path in root.rglob("*"):
        if "__pycache__" in path.parts or path.suffix in (".pyc", ".md"):
            continue
        if path.is_file() or path.is_symlink():
            yield path


def tested_paths(repository):
    """Enumerate executable inputs and policy documents used by scenarios."""
    paths = []
    for path in repository.iterdir():
        if path.is_file() and (path.name in ("installer", "AdGuardHome.sh", "S99AdGuardHome", "rc.func.AdGuardHome", "README.md")
                               or path.name.endswith((".sha256sum", ".md5sum", ".pkg.tar.bz2"))):
            paths.append(path)
    for directory in ("tests", "tools", "armv5", "armv7", "armv8"):
        root = repository / directory
        require(root.is_dir(), f"missing tested input directory: {directory}")
        paths.extend(tested_directory_paths(root))
    workflow = repository / ".github/workflows/virtual-arm-feature-tests.yml"
    if workflow.is_file():
        paths.append(workflow)
    return sorted(set(paths), key=lambda path: path.relative_to(repository).as_posix())


def content_digest(repository):
    """Bind file names, executable modes and bytes, independent of Git metadata."""
    digest = hashlib.sha256()
    for path in tested_paths(repository):
        name = path.relative_to(repository).as_posix()
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            identity = "link:" + path.readlink().as_posix()
        else:
            require(stat.S_ISREG(metadata.st_mode), f"nonregular tested input: {name}")
            identity = f"file:{metadata.st_mode & 0o111:o}:{file_sha256(path)}"
        digest.update(f"{name}\0{identity}\n".encode("utf-8"))
    require(digest.digest() != hashlib.sha256().digest(), "empty tested content")
    return digest.hexdigest()


def timestamp(value, label):
    """Require recorded timestamps with an explicit timezone."""
    require(isinstance(value, str), f"missing {label}")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None, f"timezone missing from {label}")
    return parsed


def hash_field(value, label):
    """Require a lowercase SHA-256 identity field."""
    require(isinstance(value, str) and SHA256.fullmatch(value), f"invalid SHA-256: {label}")
    return value


def build_source_digest(repository):
    """Use the builder's cache identity for saved-artifact validation too."""
    source = repository / "tools/virtual-arm"
    # Selected repository content is hashed, never imported as executable code.
    specification = importlib.util.spec_from_file_location(
        "arm_build_environment", Path(__file__).with_name("environment.py"))
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module.source_digest(source)


def checked_artifact(directory, name, digest, label):
    """Require a regular hashed artifact contained in its evidence directory."""
    require(isinstance(name, str) and name, f"missing {label} artifact")
    relative = Path(name)
    require(not relative.is_absolute() and ".." not in relative.parts, f"{label} escapes evidence directory")
    artifact = directory / relative
    require(artifact.is_file() and not artifact.is_symlink()
            and artifact.resolve().is_relative_to(directory.resolve()), f"missing or nonregular {label} artifact")
    require(hash_field(digest, label) == file_sha256(artifact), f"{label} digest mismatch")
    return artifact


def check_serial(report, report_path, rows):
    """Bind report success to the saved ordered boot and completion records."""
    execution = report["execution"]
    serial = checked_artifact(report_path.parent, execution.get("serial_log"),
                              execution.get("serial_log_sha256"), "serial log")
    token = report["guest_boot"]["token"]
    records = []
    with serial.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            fields = line.rstrip("\r\n").split("\t")
            if fields[:2] == ["AGH_VM", token]:
                records.append(fields)
    boot = report["guest_boot"]
    expected = [["AGH_VM", token, "BOOT", report["architecture"], boot["machine"],
                 boot["kernel_release"], "v" + boot["busybox_version"], report["environment_digest"],
                 boot["cpu_features"], ""]]
    results = {result["scenario"]: result for result in report["results"]}
    for row in rows:
        result = results[row["scenario"]]
        expected.append(["AGH_VM", token, "START", row["feature"], row["scenario"], ""])
        expected.append(["AGH_VM", token, "END", row["feature"], row["scenario"],
                         str(result["exit_status"]), str(result["elapsed_seconds"]), ""])
    expected.append(["AGH_VM", token, "DONE", "0", ""])
    require(records == expected, "serial boot/scenario/completion records differ from report")


def check_native_provenance(environment, architecture, source_digest):
    """Require current builder and complete kernel, shell and package identities."""
    for component in ("kernel", "busybox"):
        require(isinstance(environment.get(component), dict), f"missing native {component} identity")
        for field in ("sha256", "source_sha256", "config_sha256"):
            hash_field(environment[component].get(field), f"{component}.{field}")
    if architecture == "armv5":
        hash_field(environment.get("dtb_sha256"), "armv5 device tree")
    else:
        require("dtb_sha256" not in environment, "unexpected device tree metadata for this ARM target")
    for field in ("rootfs_manifest_sha256", "source_manifest_sha256"):
        hash_field(environment.get(field), field)
    require(environment["source_manifest_sha256"] == source_digest, "stale native build source/configuration fingerprint")
    require(isinstance(environment.get("native_packages"), list) and environment["native_packages"], "missing native tool inventory")
    package_architecture = TARGETS[architecture]["debian_architecture"]
    for package in environment["native_packages"]:
        require(isinstance(package, dict) and package.get("name") and package.get("version") and package.get("architecture") in (package_architecture, "all"), "invalid native package identity")
        hash_field(package.get("deb_sha256"), "native package source")


def check_compiler(environment, architecture):
    """Require the selected native compiler and legacy software-float contract."""
    compiler = environment.get("compiler")
    require(isinstance(compiler, dict) and compiler.get("target") and compiler.get("flags"), "missing native compiler/CPU ABI identity")
    require(compiler["target"] == COMPILER_TARGETS[architecture], "native compiler target does not match package ABI")
    flags = compiler["flags"]
    require(isinstance(flags, str), "invalid native compiler flags")
    if architecture == "armv5":
        require("-mfloat-abi=soft" in flags and "-mfloat-abi=hard" not in flags and "-mfpu=" not in flags,
                "armv5 compatibility target is not software-float/no-FPU")
    elif architecture == "armv7":
        require("-mfloat-abi=hard" in flags and "-mfpu=" in flags,
                "armv7 target is not the declared hard-float CPU environment")


def check_guest_boot(report, environment, architecture, environment_hash):
    """Match the recorded guest boot to the hashed native build and CPU target."""
    boot = report.get("guest_boot", {})
    require(isinstance(boot, dict) and boot.get("status") == "pass", "guest boot was not verified")
    require(boot.get("reported_architecture") == architecture, "booted guest architecture mismatch")
    require(boot.get("machine") == GUEST_MACHINES[architecture], "booted guest CPU architecture mismatch")
    require(boot.get("busybox_version") == "1.25.1", "booted shell is not native BusyBox 1.25.1")
    require(boot.get("kernel_release") == environment.get("kernel_release", environment["kernel"].get("version")), "booted guest kernel mismatch")
    require(boot.get("environment_digest") == environment_hash, "booted environment identity mismatch")
    cpu_features = boot.get("cpu_features")
    require(isinstance(cpu_features, str) and cpu_features, "missing native guest CPU feature record")
    if architecture == "armv5":
        require(not re.search(r"(?i)(^|\s)(?:vfp\S*|neon)(?=$|\s)", cpu_features),
                "armv5 RT-AC68U guest exposes VFP or NEON")
    require(isinstance(boot.get("token"), str) and len(boot["token"]) >= 16, "missing boot/run identity token")


def check_execution(report):
    """Require isolated native execution with strictly positive integer bounds."""
    execution = report.get("execution", {})
    require(isinstance(execution, dict) and execution.get("engine") == "qemu-system-tcg", "unexpected execution engine")
    require(execution.get("network") == "none" and execution.get("source_read_only") is True, "guest isolation contract not verified")
    for field in ("boot_timeout_seconds", "scenario_timeout_seconds"):
        value = execution.get(field)
        require(type(value) is int and value > 0, f"missing positive execution bound: {field}")


def check_environment(report, report_path, architecture, source_digest):
    """Verify the declared native full-system environment and boot identity."""
    environment = report.get("environment")
    require(isinstance(environment, dict), "missing native environment")
    require(environment.get("schema_version") == 1 and environment.get("architecture") == architecture, "environment architecture/schema mismatch")
    require(environment.get("execution_class") == "qemu-full-system-tcg", "host or user-mode execution is not ARM feature acceptance")
    machine, cpu = ENVIRONMENTS[architecture]
    require((environment.get("machine"), environment.get("cpu")) == (machine, cpu), "unexpected ARM machine/CPU")
    require(environment.get("cpu_options") == CPU_OPTIONS[architecture], "unexpected ARM CPU feature options")
    require(environment.get("target") == TARGETS[architecture], "package ABI and CPU target metadata mismatch")
    require(environment.get("busybox", {}).get("version") == "1.25.1", "native BusyBox 1.25.1 evidence required")
    check_native_provenance(environment, architecture, source_digest)
    check_compiler(environment, architecture)
    environment_file = report_path.parent / "environment.json"
    require(environment_file.is_file() and not environment_file.is_symlink(), "missing regular environment.json artifact")
    require(environment_file.resolve().is_relative_to(report_path.parent.resolve()), "environment artifact escapes evidence directory")
    require(read_json(environment_file) == environment, "environment artifact differs from report")
    environment_hash = file_sha256(environment_file)
    require(report.get("environment_digest") == environment_hash, "environment digest mismatch")
    check_guest_boot(report, environment, architecture, environment_hash)
    check_execution(report)


def check_report(path, rows, features, architecture, expected_digest, repository, source_digest):
    """Validate one architecture's complete successful selected scenario set."""
    report = read_json(path)
    require(report.get("schema_version") == 1, "unsupported evidence schema")
    require(report.get("architecture") == architecture, "evidence architecture mismatch")
    require(report.get("content_digest") == expected_digest, "stale tested content digest")
    require(isinstance(report.get("commit_label"), str) and report["commit_label"], "missing provenance commit label")
    require(report.get("requested_features") == features, "selected feature scope mismatch")
    required_selection_digest = hashlib.sha256(selection_text(rows).encode("utf-8")).hexdigest()
    require(report.get("selection_digest") == required_selection_digest, "scenario selection digest mismatch")
    require(report.get("status") == "pass", "architecture execution failed or is incomplete")
    require(not report.get("error"), "architecture execution reports a provenance or runtime error")
    require(report.get("guest_complete") is True, "missing successful guest completion record")
    require(timestamp(report.get("finished_at"), "finished_at") >= timestamp(report.get("started_at"), "started_at"), "execution timestamps reversed")
    check_environment(report, path, architecture, source_digest)
    results = report.get("results")
    require(isinstance(results, list), "missing scenario results")
    expected = {row["scenario"]: row for row in rows}
    actual = {}
    for result in results:
        require(isinstance(result, dict), "invalid scenario result")
        scenario = result.get("scenario")
        require(scenario in expected, f"unknown scenario result: {scenario}")
        require(scenario not in actual, f"duplicate scenario result: {scenario}")
        actual[scenario] = result
        row = expected[scenario]
        for key in ("feature", "test", "evidence_class", "assertions"):
            require(result.get(key) == row[key], f"scenario contract mismatch: {scenario}.{key}")
        require(result.get("status") == "pass" and type(result.get("exit_status")) is int and result["exit_status"] == 0, f"scenario failed/skipped/timed out: {scenario}")
        elapsed = result.get("elapsed_seconds")
        require(type(elapsed) is int and elapsed >= 0, f"invalid scenario elapsed time: {scenario}")
        require(elapsed <= report["execution"]["scenario_timeout_seconds"], f"scenario exceeded recorded bound: {scenario}")
        require(result.get("source_sha256") == file_sha256(repository / row["test"]), f"stale test source: {scenario}")
        log_name = result.get("log")
        require(isinstance(log_name, str) and log_name, f"missing scenario log: {scenario}")
        log = Path(log_name)
        require(not log.is_absolute() and ".." not in log.parts, "scenario log escapes evidence directory")
        log = path.parent / log
        require(log.is_file() and not log.is_symlink() and log.resolve().is_relative_to(path.parent.resolve()), f"missing or nonregular scenario log: {scenario}")
        require(hash_field(result.get("log_sha256"), "scenario log") == file_sha256(log), f"scenario log digest mismatch: {scenario}")
    require(set(actual) == set(expected), f"missing scenarios: {','.join(sorted(set(expected) - set(actual)))}")
    check_serial(report, path, rows)
    return report


def prepare_summary(path):
    """Clear only an earlier owned decision and reject unsafe output leaves."""
    path = Path(path)
    require(path.suffix == ".json" and not any(ord(character) < 32 for character in path.name),
            "summary must be a JSON filename without control characters")
    # The parent is an explicit caller-selected output directory. Resolve it
    # once; untrusted evidence never supplies this directory or destination.
    destination = path.parent.resolve() / path.name
    require(not destination.is_symlink(), "summary must not be a symlink")
    if destination.exists():
        require(destination.is_file(), "summary must be a regular file")
        previous = read_json(destination)
        require(previous.get("schema_version") == 1 and previous.get("status") == "pass"
                and type(previous.get("unblocks")) is bool and previous.get("scope") == ACCEPTANCE_SCOPE,
                "refusing to overwrite a file that is not an ARM acceptance summary")
        # A rejected recheck must never leave a previous green decision behind.
        destination.unlink()
    return destination


def write_summary(destination, text):
    """Publish a decision atomically without following an output symlink."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination.parent,
                                     prefix=".arm-acceptance-", suffix=".json.tmp",
                                     delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(text)
            stream.close()
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


def main(argv=None):
    """Expose selection, content fingerprinting and fail-closed acceptance modes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", nargs="*")
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--features", default="all")
    parser.add_argument("--architectures", default="all")
    parser.add_argument("--select", action="store_true")
    parser.add_argument("--content-digest", action="store_true")
    parser.add_argument("--partial", action="store_true", help="validate execution artifacts without unblocking a feature")
    parser.add_argument("--summary", type=Path)
    arguments = parser.parse_args(argv)
    summary_destination = prepare_summary(arguments.summary) if arguments.summary else None
    repository = arguments.repository.resolve()
    if arguments.content_digest:
        require(not arguments.select and not arguments.evidence, "content-digest mode cannot validate evidence")
        print(content_digest(repository))
        return
    manifest = arguments.manifest or repository / "tools/virtual-arm/features.tsv"
    rows = load_manifest(manifest, repository)
    all_features = list(dict.fromkeys(row["feature"] for row in rows))
    features = selection(arguments.features, all_features, "feature")
    selected_rows = [row for row in rows if row["feature"] in features]
    if arguments.select:
        require(not arguments.evidence and not arguments.partial, "selection mode cannot validate evidence")
        sys.stdout.write(selection_text(selected_rows))
        return
    architectures = selection(arguments.architectures, ARCHITECTURES, "architecture")
    require(arguments.partial or set(architectures) == set(ARCHITECTURES), "feature acceptance requires armv5,armv7,armv8; --partial never unblocks")
    require(arguments.evidence, "no execution evidence supplied")
    paths = []
    for value in arguments.evidence:
        path = Path(value)
        paths.extend(sorted(path.rglob("evidence.json")) if path.is_dir() else [path])
    require(paths, "no evidence.json artifacts found")
    expected_digest = content_digest(repository)
    source_digest = build_source_digest(repository)
    reports = {}
    for path in paths:
        identity = read_json(path).get("architecture")
        require(identity in architectures, f"unexpected evidence architecture: {identity}")
        require(identity not in reports, f"duplicate evidence architecture: {identity}")
        reports[identity] = check_report(path, selected_rows, features, identity, expected_digest, repository, source_digest)
    require(set(reports) == set(architectures), f"missing architecture evidence: {','.join(sorted(set(architectures) - set(reports)))}")
    accepted = not arguments.partial
    summary = {
        "schema_version": 1,
        "status": "pass",
        "content_digest": expected_digest,
        "requested_features": features,
        "architectures": architectures,
        "scenarios_per_architecture": len(selected_rows),
        "unblocks": accepted,
        "unblocked_features": features if accepted else [],
        "scope": ACCEPTANCE_SCOPE,
        "excluded": sorted({row["exclusions"] for row in selected_rows}),
        "physical_release_acceptance": "unchanged",
        "commit_labels": sorted({report["commit_label"] for report in reports.values()}),
    }
    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if summary_destination:
        write_summary(summary_destination, text)
    sys.stdout.write(text)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(f"ARM feature acceptance rejected: {error}", file=sys.stderr)
        sys.exit(1)
