#!/usr/bin/env python3
"""Exercise shared-agent policy rejection in isolated, read-only repositories."""

import contextlib
import copy
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPOSITORY = Path(__file__).resolve().parents[1]
CHECKER = REPOSITORY / "tools/check-agent-integrations.py"
SPEC = importlib.util.spec_from_file_location("agent_integration_checker", CHECKER)
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)
BASELINE = json.loads((REPOSITORY / GATE.MANIFEST).read_text(encoding="utf-8"))


class IntegrationPolicy(unittest.TestCase):
    """Verify accepted policy and prevent silent provider or path drift."""

    def setUp(self):
        """Copy only declared text assets into a disposable repository."""
        self.temporary = tempfile.TemporaryDirectory(prefix="agent-integration-policy-")
        self.root = Path(self.temporary.name) / "repository"
        self.root.mkdir()
        self.manifest = self.root / GATE.MANIFEST
        self.data = copy.deepcopy(BASELINE)
        assets = {"AGENTS.md", self.data["guide"]}
        assets.update(record["path"] for record in self.data["agents"])
        assets.update(record["path"] for record in self.data["skills"])
        for relative in assets:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPOSITORY / relative, destination)
        self.checker = self.root / "tools/check-agent-integrations.py"
        self.checker.parent.mkdir()
        shutil.copyfile(CHECKER, self.checker)
        self.write_manifest()
        self.outside = Path(self.temporary.name) / "outside"
        self.outside.mkdir()
        (self.outside / "secret").write_text("Must never be read by the registry checker.\n", encoding="utf-8")

    def tearDown(self):
        """Remove the isolated repository after each policy scenario."""
        self.temporary.cleanup()

    def write_manifest(self):
        """Publish the test's current declaration, never the real registry."""
        self.manifest.write_text(json.dumps(self.data) + "\n", encoding="utf-8")

    def snapshot(self):
        """Record content, permissions, and links without following symlinks."""
        result = {}
        base = Path(self.temporary.name)
        for directory, directories, files in os.walk(base, followlinks=False):
            for name in directories + files:
                path = Path(directory) / name
                relative = path.relative_to(base).as_posix()
                mode = path.lstat().st_mode
                if path.is_symlink():
                    result[relative] = ("symlink", mode, os.readlink(path))
                elif path.is_file():
                    result[relative] = ("file", mode, path.read_bytes())
                else:
                    result[relative] = ("nonregular", mode)
        return result

    def assert_rejected(self, message):
        """Require observable rejection and unchanged fixture contents."""
        before = self.snapshot()
        with self.assertRaisesRegex((ValueError, OSError), message):
            GATE.validate_repository(self.root)
        self.assertEqual(self.snapshot(), before)

    def assert_passes(self):
        """Require all declared records to pass without writing anything."""
        before = self.snapshot()
        result = GATE.validate_repository(self.root)
        self.assertEqual(result, (len(self.data["agents"]), len(self.data["skills"]), len(self.data["integrations"])))
        self.assertEqual(self.snapshot(), before)

    def run_cli(self, arguments=()):
        """Execute the real checker in the fixture's own trusted checkout."""
        before = self.snapshot()
        result = subprocess.run([sys.executable, str(self.checker), *arguments],
                                capture_output=True, text=True, timeout=10, check=False)
        self.assertEqual(self.snapshot(), before)
        return result

    def assert_cli_rejected(self):
        """Check the actual CLI's exit status, error stream, and read-only state."""
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.startswith("FAIL agent integrations:"), result.stderr)

    def test_current_registered_assets_pass(self):
        """All real checked-in adapters and local skills satisfy the contract."""
        self.assert_passes()

    def test_cli_success_and_default_root(self):
        """Imported and copied-script entrypoints validate their own checkout."""
        stdout, stderr = io.StringIO(), io.StringIO()
        before = self.snapshot()
        with mock.patch.object(GATE, "DEFAULT_ROOT", self.root):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(GATE.main([]), 0)
        self.assertEqual(stderr.getvalue(), "")
        self.assertEqual(len(stdout.getvalue().splitlines()), 1)
        self.assertTrue(all(line.startswith("PASS agent integrations:") for line in stdout.getvalue().splitlines()))
        self.assertEqual(self.snapshot(), before)
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertTrue(result.stdout.startswith("PASS agent integrations:"), result.stdout)

    def test_cli_cannot_select_external_root(self):
        """An agent-provided root argument cannot expand the CLI read boundary."""
        result = self.run_cli(["--root", str(self.outside)])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("unrecognized arguments: --root", result.stderr)

    def test_long_scalar_uses_bounded_cli_validation(self):
        """Long whitespace runs cannot amplify metadata parsing through regex search."""
        skill = self.data["skills"][0]
        description = "Read" + " " * 100000 + "shared policy. # explanatory comment"
        text = f"---\nname: {skill['name']}\ndescription: {description}\n---\nAGENTS.md\n"
        (self.root / skill["path"]).write_text(text, encoding="utf-8")
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertTrue(result.stdout.startswith("PASS agent integrations:"), result.stdout)

    def test_cli_reports_validation_failure(self):
        """Importable CLI returns one rather than exposing a traceback."""
        self.data["version"] = False
        self.write_manifest()
        stdout, stderr = io.StringIO(), io.StringIO()
        before = self.snapshot()
        with mock.patch.object(GATE, "DEFAULT_ROOT", self.root):
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(GATE.main([]), 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("FAIL agent integrations: unsupported registry version", stderr.getvalue())
        self.assertEqual(self.snapshot(), before)

    def test_malformed_json_cli(self):
        """Malformed and nonstandard JSON cannot be mistaken for a registry."""
        for text in ("{", '{"version":1,"version":1}', '{"version":NaN}', '{"version":Infinity}',
                     '{"version":-Infinity}', "[]", "null"):
            with self.subTest(text=text):
                self.manifest.write_text(text, encoding="utf-8")
                self.assert_cli_rejected()

    def test_nested_duplicate_json_key_cli(self):
        """A duplicate nested mode cannot silently override activation status."""
        text = json.dumps(BASELINE).replace('"mode":', '"mode":"excluded","mode":', 1)
        self.manifest.write_text(text, encoding="utf-8")
        self.assert_cli_rejected()

    def test_top_level_contract(self):
        """Missing fields, wrong types, and policy redirection fail closed."""
        cases = [
            ("version", True, "unsupported registry version"),
            ("version", 1.0, "unsupported registry version"),
            ("version", 2, "unsupported registry version"),
            ("canonical_policy", "OTHER.md", "canonical policy must be AGENTS.md"),
            ("guide", "elsewhere.md", "integration guide must be"),
            ("agents", {}, "agents must be a nonempty array"),
            ("agents", [], "agents must be a nonempty array"),
            ("skills", {}, "skills must be a nonempty array"),
            ("skills", [], "skills must be a nonempty array"),
            ("integrations", {}, "integrations must be a nonempty array"),
            ("integrations", [], "integrations must be a nonempty array"),
        ]
        for field, value, message in cases:
            with self.subTest(field=field, value=value):
                self.data = copy.deepcopy(BASELINE)
                self.data[field] = value
                self.write_manifest()
                self.assert_rejected(message)
        self.data = copy.deepcopy(BASELINE)
        del self.data["version"]
        self.write_manifest()
        self.assert_rejected("unexpected fields in manifest")
        self.data = copy.deepcopy(BASELINE)
        self.data["verison"] = 1
        self.write_manifest()
        self.assert_rejected("unexpected fields in manifest")

    def test_record_shapes(self):
        """Each collection rejects scalar records and misspelled fields."""
        for collection, label in (("agents", "agent"), ("skills", "skill"), ("integrations", "integration")):
            for malformed in (None, {}, {"unexpected": "field"}):
                with self.subTest(collection=collection, malformed=malformed):
                    self.data = copy.deepcopy(BASELINE)
                    self.data[collection][0] = malformed
                    self.write_manifest()
                    self.assert_rejected(f"{label} must be an object|unexpected fields in {label}")

    def test_required_agents_cannot_disappear(self):
        """Silently removing any active provider adapter is a failing change."""
        for identifier in GATE.REQUIRED_AGENTS:
            with self.subTest(identifier=identifier):
                self.data = copy.deepcopy(BASELINE)
                self.data["agents"] = [record for record in self.data["agents"] if record["id"] != identifier]
                self.write_manifest()
                self.assert_rejected("canonical agent|missing or altered required agent")

    def test_agent_ids_paths_and_kinds_are_unique(self):
        """Duplicate registrations and altered required agent contracts fail."""
        cases = [
            ("id", "", "agent ID must be a nonempty string"),
            ("id", "Bad_Name", "invalid agent ID"),
            ("id", BASELINE["agents"][1]["id"], "duplicate agent ID"),
            ("path", BASELINE["agents"][1]["path"], "duplicate agent path"),
            ("kind", "unverified", "invalid agent kind"),
            ("kind", [], "invalid agent kind"),
            ("kind", "pointer", "exactly one canonical agent"),
        ]
        for field, value, message in cases:
            with self.subTest(field=field, value=value):
                self.data = copy.deepcopy(BASELINE)
                self.data["agents"][0][field] = value
                self.write_manifest()
                self.assert_rejected(message)
        self.data = copy.deepcopy(BASELINE)
        self.data["agents"][1]["kind"] = "canonical"
        self.write_manifest()
        self.assert_rejected("exactly one canonical agent")
        self.data["agents"][1]["kind"] = "pointer"
        self.write_manifest()
        self.assert_rejected("missing or altered required agent: amazonq")

    def test_additional_agents_must_share_policy(self):
        """Future adapters are permitted but cannot introduce a stale mirror."""
        path = self.root / "NEW-AGENT.md"
        path.write_text("Read AGENTS.md and docs/agent-integrations.md.\n", encoding="utf-8")
        self.data["agents"].append({"id": "future-agent", "path": path.name, "kind": "pointer"})
        self.write_manifest()
        self.assert_passes()
        self.data["agents"][-1]["kind"] = "mirror"
        self.write_manifest()
        self.assert_rejected("mirrored policy must be byte-identical")
        path.write_bytes((self.root / "AGENTS.md").read_bytes())
        self.assert_passes()

    def test_required_agent_path_is_fixed(self):
        """Redirecting an existing adapter to a lookalike file is rejected."""
        path = self.root / "different-agent.md"
        path.write_bytes((self.root / "CLAUDE.md").read_bytes())
        agent = next(record for record in self.data["agents"] if record["id"] == "claude")
        agent["path"] = path.name
        self.write_manifest()
        self.assert_rejected("missing or altered required agent: claude")

    def test_agent_policy_and_guide_links(self):
        """Every adapter must explicitly direct agents to both shared documents."""
        target = self.root / "CLAUDE.md"
        for content in ("Read AGENTS.md.\n", "Read docs/agent-integrations.md.\n"):
            with self.subTest(content=content):
                target.write_text(content, encoding="utf-8")
                self.assert_rejected("agent claude must link the shared policy and guide")

    def test_mirror_drift_and_empty_guide(self):
        """Mirrors cannot drift and the integration guide must contain text."""
        mirror = self.root / ".amazonq/rules/AGENTS.md"
        original = mirror.read_bytes()
        mirror.write_bytes(original + b"\nDrift.\n")
        self.assert_rejected("mirrored policy must be byte-identical")
        mirror.write_bytes(original)
        (self.root / GATE.GUIDE).write_text(" \n", encoding="utf-8")
        self.assert_rejected("integration guide must be a nonempty string")

    def test_paths_reject_traversal_and_ambiguity_cli(self):
        """The command rejects absolute, traversing, or ambiguous file paths."""
        for value in ("../outside/secret", "/etc/passwd", "CLAUDE.md/../AGENTS.md", "./CLAUDE.md",
                      "docs//agent-integrations.md", "CLAUDE.md/", "C:\\secret", "docs\\file", "bad\x00file", ""):
            with self.subTest(path=value):
                self.data = copy.deepcopy(BASELINE)
                self.data["agents"][0]["path"] = value
                self.write_manifest()
                self.assert_cli_rejected()

    def test_nonstring_registration_path(self):
        """An array path is rejected before attempting filesystem access."""
        self.data["agents"][0]["path"] = []
        self.write_manifest()
        self.assert_rejected("registration path must be a nonempty string")

    def test_missing_assets(self):
        """Missing manifest, guide, adapter, and skill files each fail closed."""
        for relative in (GATE.MANIFEST, GATE.GUIDE, "CLAUDE.md", self.data["skills"][0]["path"]):
            with self.subTest(path=relative):
                path = self.root / relative
                original = path.read_bytes()
                path.unlink()
                self.assert_rejected("No such file")
                path.write_bytes(original)

    def test_invalid_utf8(self):
        """Invalid text in a declaration or registered adapter causes failure."""
        for relative in (GATE.MANIFEST, "CLAUDE.md"):
            with self.subTest(path=relative):
                path = self.root / relative
                original = path.read_bytes()
                path.write_bytes(b"\xff")
                self.assert_rejected("utf-8")
                path.write_bytes(original)

    def test_symlinked_manifest_cli(self):
        """A linked registry cannot redirect the checker to an external file."""
        outside = self.outside / "registry.json"
        outside.write_bytes(self.manifest.read_bytes())
        self.manifest.unlink()
        self.manifest.symlink_to(outside)
        self.assert_cli_rejected()

    def test_symlink_final_and_parent_do_not_read_outside(self):
        """No-follow descriptors reject external links before reading bytes."""
        linked = self.root / "linked"
        linked.symlink_to(self.outside, target_is_directory=True)
        final = self.root / "linked-file"
        final.symlink_to(self.outside / "secret")
        for relative in ("linked/secret", "linked-file"):
            with self.subTest(path=relative):
                with mock.patch.object(GATE.os, "fdopen", wraps=os.fdopen) as opened:
                    with self.assertRaises(OSError):
                        GATE.read_file(self.root, relative)
                    opened.assert_not_called()

    def test_symlinked_adapter_and_parent_cli(self):
        """Both registered final symlinks and linked parent directories fail."""
        adapter = self.root / "CLAUDE.md"
        adapter.unlink()
        adapter.symlink_to(self.outside / "secret")
        self.assert_cli_rejected()
        adapter.unlink()
        shutil.copyfile(REPOSITORY / "CLAUDE.md", adapter)
        directory = self.root / ".amazonq/rules"
        shutil.rmtree(directory)
        directory.symlink_to(self.outside, target_is_directory=True)
        self.assert_cli_rejected()

    def test_symlinked_root_and_missing_root(self):
        """A linked root or nonexistent checkout cannot bypass safe reads."""
        link = Path(self.temporary.name) / "root-link"
        link.symlink_to(self.root, target_is_directory=True)
        for root in (link, self.root / "absent"):
            with self.subTest(root=root):
                with self.assertRaises(OSError):
                    GATE.validate_repository(root)

    def test_directory_and_fifo_assets_rejected_without_blocking(self):
        """Nonregular registered files fail rather than hanging on a FIFO."""
        adapter = self.root / "CLAUDE.md"
        adapter.unlink()
        adapter.mkdir()
        self.assert_rejected("nonregular registration file")
        adapter.rmdir()
        os.mkfifo(adapter)
        self.assert_cli_rejected()

    def test_skill_names_paths_and_policy(self):
        """Skills have unique names, canonical local paths, and shared policy."""
        cases = [
            ("name", "", "skill name must be a nonempty string"),
            ("name", "Bad_Skill", "invalid skill name"),
            ("name", BASELINE["skills"][1]["name"], "unexpected skill path|duplicate skill name"),
            ("path", BASELINE["skills"][1]["path"], "unexpected skill path|duplicate skill path"),
            ("path", "docs/agent-integrations.md", "unexpected skill path"),
        ]
        for field, value, message in cases:
            with self.subTest(field=field, value=value):
                self.data = copy.deepcopy(BASELINE)
                self.data["skills"][0][field] = value
                self.write_manifest()
                self.assert_rejected(message)
        self.data = copy.deepcopy(BASELINE)
        self.data["skills"].append(copy.deepcopy(self.data["skills"][0]))
        self.write_manifest()
        self.assert_rejected("duplicate skill name")
        self.data = copy.deepcopy(BASELINE)
        self.write_manifest()
        skill = self.data["skills"][0]
        text = f"---\nname: {skill['name']}\ndescription: Test skill.\n---\nNo shared policy link.\n"
        (self.root / skill["path"]).write_text(text, encoding="utf-8")
        self.assert_rejected("must link AGENTS.md")

    def test_qodo_skills_cannot_disappear(self):
        """Existing Qodo skills remain registered even if files are removed."""
        for name in GATE.REQUIRED_SKILLS:
            with self.subTest(name=name):
                self.data = copy.deepcopy(BASELINE)
                self.data["skills"] = [record for record in self.data["skills"] if record["name"] != name]
                self.write_manifest()
                self.assert_rejected("existing Qodo skills must remain registered")

    def test_frontmatter_rejections(self):
        """Invalid, missing, duplicate, empty, or mismatched metadata fails."""
        skill = self.data["skills"][0]
        name = skill["name"]
        invalid = [
            ("", "start with YAML frontmatter"),
            ("---\n", "frontmatter is not closed"),
            ("---\ndescription: valid\n---\n", "name and description are required"),
            (f"---\nname: {name}\n---\n", "name and description are required"),
            (f"---\nname: wrong-skill\ndescription: valid\n---\n", "frontmatter name mismatch"),
            (f'---\nname: " {name} "\ndescription: valid\n---\n', "frontmatter name mismatch"),
            (f"---\nname: '{name} '\ndescription: valid\n---\n", "frontmatter name mismatch"),
            (f"---\nname: >-\n  {name}\ndescription: valid\n---\n", "name must be a single-line scalar"),
            (f"---\nname: {name}\nname: {name}\ndescription: valid\n---\n", "duplicate skill frontmatter key"),
            (f"---\nname: {name}\ndescription: valid\ndescription: again\n---\n", "duplicate skill frontmatter key"),
        ]
        for description in ("", "''", '""', "null", "~", "|", ">-", "'", '"unclosed'):
            invalid.append((f"---\nname: {name}\ndescription: {description}\n---\n",
                            "nonempty string|nonstring frontmatter scalar|unclosed frontmatter scalar"))
        for header, message in invalid:
            with self.subTest(header=header):
                (self.root / skill["path"]).write_text(header + "AGENTS.md\n", encoding="utf-8")
                self.assert_rejected(message)

    def test_frontmatter_rejects_yaml_nonstrings_and_invalid_scalars(self):
        """Skill metadata cannot claim arrays, booleans, or malformed YAML as strings."""
        skill = self.data["skills"][0]
        for value in ("[]", "{}", "true", "FALSE", "yes", "Off", "# comment", "[unterminated",
                      "{unterminated", "&alias", "*alias", "!tag", "%invalid", "@invalid", "`invalid",
                      "12", "-1.5", "+2", "0xFA", "0o77", ".NaN", ".inf", "2026-10-11", "A: B", "mapping:",
                      "- item", "? key", "true # note", "12 # note", "null # note", "2026-10-11T12:00:00Z",
                      "2026-10-11 12:00:00", "?", "-",
                      "'unescaped'quote'", '"\\n"', '"invalid\\q"'):
            with self.subTest(value=value):
                text = f"---\nname: {skill['name']}\ndescription: {value}\n---\nAGENTS.md\n"
                (self.root / skill["path"]).write_text(text, encoding="utf-8")
                self.assert_rejected("frontmatter|nonempty string|Invalid")

    def test_frontmatter_decodes_supported_quoted_strings(self):
        """YAML single-quote escapes and JSON-compatible double quotes retain text."""
        skill = self.data["skills"][0]
        for value in ("'Router''s safe instructions.'", '"Read \\"AGENTS.md\\" first."', "Safe instructions. # note"):
            with self.subTest(value=value):
                text = f"---\nname: {skill['name']}\ndescription: {value}\n---\nAGENTS.md\n"
                (self.root / skill["path"]).write_text(text, encoding="utf-8")
                self.assert_passes()

    def test_frontmatter_scalar_and_block_descriptions(self):
        """Existing YAML scalars and meaningful block descriptions are accepted."""
        skill = self.data["skills"][0]
        for quote in ("'", '"'):
            for description in ("Valid description.", "|", ">", "|-", ">-", "|+", ">+"):
                with self.subTest(quote=quote, description=description):
                    block = "\n  Uses shared policy.\n\n  Keeps router compatibility.\n" if description != "Valid description." else ""
                    text = (f"---\nname: {quote}{skill['name']}{quote}\ndescription: {description}\n{block}"
                            "triggers:\n  - router\n---\nAGENTS.md\n")
                    (self.root / skill["path"]).write_text(text, encoding="utf-8")
                    self.assert_passes()

    def test_optional_frontmatter_rejects_malformed_or_unsupported_fields(self):
        """Optional metadata cannot hide malformed YAML from skill discovery."""
        skill = self.data["skills"][0]
        invalid = (
            "allowed-tools:Bash\n",
            "allowed-tools: [unterminated\n", "allowed-tools: []\n", "allowed-tools: {}\n",
            "allowed-tools: true\n", "allowed-tools: null\n", "allowed-tools: ''\n",
            'allowed-tools: "unterminated\n', "allowed-tools: |\n  Bash\n",
            "allowed-tools:\n  - Bash\n", "allowed-tools: Bash\nallowed-tools: Read\n",
            "triggers: [unterminated\n", "triggers: []\n", 'triggers: "router"\n', "triggers:\n",
            "triggers:\n  - []\n", "triggers:\n  - {}\n", "triggers:\n  - true\n", "triggers:\n  - null\n",
            'triggers:\n  - "unterminated\n', "triggers:\n  - \n", "triggers:\n  - |\n    router\n",
            "triggers:\n - router\n", "triggers:\n    - router\n", "triggers:\n\t- router\n",
            "triggers:\n- router\n", "triggers:\n  - router\n    - nested\n",
            "triggers:\n  - router\n  extra\n", "triggers:\n  - router\ntriggers:\n  - again\n",
            "allowed_tool: Bash\n", "unknown: [unterminated\n", "broken optional field\n",
            "  allowed-tools: Bash\n", "  orphan continuation\n",
        )
        for optional in invalid:
            with self.subTest(optional=optional):
                text = (f"---\nname: {skill['name']}\ndescription: Valid description.\n"
                        f"{optional}---\nAGENTS.md\n")
                (self.root / skill["path"]).write_text(text, encoding="utf-8")
                self.assert_rejected("frontmatter|skill allowed-tools|skill triggers|skill trigger")

    def test_optional_frontmatter_preserves_supported_qodo_profile(self):
        """Optional string fields, trigger lists, and comments remain supported."""
        skill = self.data["skills"][0]
        valid = (
            'allowed-tools: "Bash"\n', "allowed-tools: 'Bash Read'\n",
            "triggers:\n  - router.?change\n", 'triggers:\n  - "router.?change"\n',
            '# Header comment.\n\nallowed-tools: "Bash"\ntriggers:\n  # List comment.\n\n  - router#fragment\n  - "router # quoted"\n',
        )
        for optional in valid:
            with self.subTest(optional=optional):
                text = (f"---\nname: {skill['name']}\ndescription: Valid description.\n"
                        f"{optional}---\nAGENTS.md\n")
                (self.root / skill["path"]).write_text(text, encoding="utf-8")
                self.assert_passes()

    def test_block_description_indentation_is_validated(self):
        """Block descriptions cannot conceal malformed indentation or header lines."""
        skill = self.data["skills"][0]
        for body in (" Valid.\n", "\tValid.\n", "  \tValid.\n", "    First.\n  Bad dedent.\n"):
            with self.subTest(body=body):
                text = f"---\nname: {skill['name']}\ndescription: >\n{body}---\nAGENTS.md\n"
                (self.root / skill["path"]).write_text(text, encoding="utf-8")
                self.assert_rejected("frontmatter block indentation")
        text = (f"---\nname: {skill['name']}\ndescription: >\n\n  First.\n    Nested text.\n"
                "  Last.\n\nallowed-tools: Bash\n---\nAGENTS.md\n")
        (self.root / skill["path"]).write_text(text, encoding="utf-8")
        self.assert_passes()

    def test_unregistered_skill_is_rejected(self):
        """A new skill cannot bypass registry review by remaining undeclared."""
        path = self.root / ".agents/skills/unregistered/SKILL.md"
        path.parent.mkdir()
        path.write_text("---\nname: unregistered\ndescription: Valid.\n---\nAGENTS.md\n", encoding="utf-8")
        self.assert_rejected("discovered skills and registry do not match")

    def test_inventory_ignores_files_and_empty_directories(self):
        """Non-skill inventory entries do not become phantom registrations."""
        inventory = self.root / ".agents/skills"
        (inventory / "README.md").write_text("Skill inventory.\n", encoding="utf-8")
        (inventory / "not-a-skill").mkdir()
        self.assert_passes()

    def test_symlinked_skill_inventory_rejected(self):
        """Discovery rejects linked unregistered directories without following them."""
        path = self.root / ".agents/skills/linked-skill"
        path.symlink_to(self.outside, target_is_directory=True)
        self.assert_rejected("symlink in skill inventory")

    def test_registered_skill_symlinks_rejected(self):
        """Neither a registered SKILL.md nor its directory may be a symlink."""
        skill = self.root / self.data["skills"][0]["path"]
        original = skill.read_bytes()
        skill.unlink()
        skill.symlink_to(self.outside / "secret")
        self.assert_rejected("Too many levels of symbolic links")
        skill.unlink()
        skill.write_bytes(original)
        directory = skill.parent
        shutil.rmtree(directory)
        directory.symlink_to(self.outside, target_is_directory=True)
        self.assert_rejected("Not a directory")

    def test_integration_identity_and_metadata(self):
        """Provider identities, status, provenance, and notes are explicit."""
        cases = [
            ("id", "", "integration ID must be a nonempty string"),
            ("id", "Bad_Plugin", "invalid integration ID"),
            ("name", "", "integration name must be a nonempty string"),
            ("name", 1, "integration name must be a nonempty string"),
            ("notes", " ", "integration notes must be a nonempty string"),
            ("source", None, "integration source must be a nonempty string"),
            ("mode", "active", "invalid integration mode"),
            ("mode", [], "invalid integration mode"),
            ("skills", {}, "integration skills must be an array"),
        ]
        for field, value, message in cases:
            with self.subTest(field=field, value=value):
                self.data = copy.deepcopy(BASELINE)
                self.data["integrations"][0][field] = value
                self.write_manifest()
                self.assert_rejected(message)
        for field in ("id", "name"):
            with self.subTest(duplicate=field):
                self.data = copy.deepcopy(BASELINE)
                self.data["integrations"][1][field] = self.data["integrations"][0][field]
                self.write_manifest()
                self.assert_rejected(f"duplicate integration {field if field == 'name' else 'ID'}")

    def test_skill_references_and_inactive_modes(self):
        """Only implemented, registered capabilities can claim active skills."""
        known = self.data["skills"][0]["name"]
        cases = [
            ("existing", ["missing-skill"], "unknown skill reference"),
            ("existing", [known, known], "duplicate skill reference"),
            ("existing", [None], "skill reference must be a nonempty string"),
            ("existing", ["Bad_Skill"], "invalid skill reference"),
            ("repository-skill", [], "repository-skill integration needs a skill"),
        ]
        cases.extend((mode, [known], "inactive integration cannot claim active skills") for mode in GATE.INACTIVE_MODES)
        for mode, references, message in cases:
            with self.subTest(mode=mode, references=references):
                self.data = copy.deepcopy(BASELINE)
                self.data["integrations"][0]["mode"] = mode
                self.data["integrations"][0]["skills"] = references
                self.write_manifest()
                self.assert_rejected(message)

    def test_existing_integration_without_skill(self):
        """Existing hosted reviewers can be registered without a local skill."""
        self.data["integrations"][0]["mode"] = "existing"
        self.data["integrations"][0]["skills"] = []
        self.write_manifest()
        self.assert_passes()

    def test_requested_provider_inventory_cannot_silently_shrink(self):
        """Removing any of the original 27 requested provider records fails closed."""
        self.assertEqual(len(GATE.REQUIRED_INTEGRATIONS), 27)
        for provider in GATE.REQUIRED_INTEGRATIONS:
            with self.subTest(provider=provider):
                self.data = copy.deepcopy(BASELINE)
                self.data["integrations"] = [record for record in self.data["integrations"] if record["id"] != provider]
                self.write_manifest()
                self.assert_rejected(f"missing requested integrations: {provider}")

    def test_provider_inventory_can_add_a_future_explicitly_scoped_record(self):
        """The protected original inventory permits reviewed future additions."""
        self.data["integrations"].append({
            "id": "future-provider", "name": "Future provider", "mode": "unverified", "skills": [],
            "notes": "No activation or supported capability is claimed.", "source": "operator-defined",
        })
        self.write_manifest()
        self.assert_passes()


if __name__ == "__main__":
    unittest.main()
