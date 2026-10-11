#!/usr/bin/env python3
"""Check the shared agent registry without executing providers or changing files."""

import argparse
import json
import os
import re
import stat
import sys
from pathlib import Path


DEFAULT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ".agents/integrations.json"
GUIDE = "docs/agent-integrations.md"
POLICY = "AGENTS.md"
REQUIRED_AGENTS = {
    "codex": (POLICY, "canonical"),
    "amazonq": (".amazonq/rules/AGENTS.md", "mirror"),
    "coderabbit": (".coderabbit.yaml", "policy"),
    "qodo": ("REVIEW.md", "pointer"),
    "claude": ("CLAUDE.md", "pointer"),
    "cursor": (".cursorrules", "pointer"),
    "copilot": (".github/copilot-instructions.md", "pointer"),
    "codex-review": (".github/prompts/codex-code-improvement.md", "pointer"),
}
REQUIRED_SKILLS = {"qodo-get-rules", "qodo-pr-resolver"}
REQUIRED_INTEGRATIONS = {
    "taskplanner", "lovable", "vibe-coding", "zuora-coding-agent", "opstruth", "unix-copilot",
    "engineering-suite", "zzzops", "codeassistant", "qodo", "groundwork", "andrej-karpathy-skills",
    "skillquiver", "get-fable", "skarn", "god-prompt", "chatgpt-osint", "gh-review-loop", "code-review",
    "coderabbit", "app-6a392799cb58819185f82dc01ac13dad", "awesome-maintainer-defense", "develoop",
    "pr-completion", "github", "project-memory-core", "ai-psychiatry",
}
DESCRIPTION = "description"
FRONTMATTER_FIELDS = {"name", DESCRIPTION, "allowed-tools", "triggers"}
BLOCK_SCALARS = {"|", ">", "|-", ">-", "|+", ">+"}
AGENT_KINDS = {"canonical", "mirror", "policy", "pointer"}
MODES = {"existing", "repository-skill", "external-optional", "unverified", "excluded"}
INACTIVE_MODES = {"external-optional", "unverified", "excluded"}
IDENTIFIER = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*\Z")


def require(condition, message):
    """Reject an incomplete or inconsistent registration."""
    if not condition:
        raise ValueError(message)


def nonempty_string(value, label):
    """Accept only a nonempty string, preserving the declared text."""
    require(isinstance(value, str) and bool(value.strip()), f"{label} must be a nonempty string")
    return value


def identifier(value, label):
    """Validate stable lowercase registration identifiers."""
    value = nonempty_string(value, label)
    require(IDENTIFIER.fullmatch(value) is not None, f"invalid {label}: {value}")
    return value


def fields(record, expected, label):
    """Reject missing and misspelled fields instead of ignoring them."""
    require(isinstance(record, dict), f"{label} must be an object")
    require(set(record) == set(expected), f"unexpected fields in {label}")


def unique_object(pairs):
    """Prevent duplicate JSON keys from silently rewriting declarations."""
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_constant(value):
    """Reject Python's nonstandard JSON NaN and Infinity extensions."""
    raise ValueError(f"invalid JSON constant: {value}")


def path_parts(value):
    """Require an unambiguous relative POSIX path with no traversal."""
    value = nonempty_string(value, "registration path")
    parts = value.split("/")
    require(not any(part in ("", ".", "..") for part in parts), f"invalid registration path: {value}")
    require("\\" not in value and ":" not in value, f"non-POSIX registration path: {value}")
    require(all(ord(character) >= 32 for character in value), "control character in registration path")
    return parts


def open_directory(root, parts):
    """Walk directory descriptors without following any registered symlink."""
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        return directory
    except BaseException:
        os.close(directory)
        raise


def read_file(root, relative):
    """Read a regular repository file through a no-follow descriptor chain."""
    parts = path_parts(relative)
    directory = open_directory(root, parts[:-1])
    try:
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    finally:
        os.close(directory)
    try:
        require(stat.S_ISREG(os.fstat(descriptor).st_mode), f"nonregular registration file: {relative}")
    except BaseException:
        os.close(descriptor)
        raise
    with os.fdopen(descriptor, "rb") as handle:
        return handle.read()


def read_text(root, relative):
    """Decode registration assets as UTF-8 without executing their contents."""
    return read_file(root, relative).decode("utf-8")


def records(value, label):
    """Require a populated array for each registry collection."""
    require(isinstance(value, list) and bool(value), f"{label} must be a nonempty array")
    return value


def claim(value, seen, label):
    """Reserve one unique identifier, name, or path within its collection."""
    require(value not in seen, f"duplicate {label}: {value}")
    seen.add(value)


def validate_agents(root, agents):
    """Keep all existing agents attached to the canonical policy and guide."""
    registered = {}
    identifiers = set()
    paths = set()
    canonical = []
    for agent in records(agents, "agents"):
        fields(agent, ("id", "path", "kind"), "agent")
        name = identifier(agent["id"], "agent ID")
        claim(name, identifiers, "agent ID")
        kind = agent["kind"]
        require(isinstance(kind, str) and kind in AGENT_KINDS, f"invalid agent kind: {kind}")
        path_parts(agent["path"])
        claim(agent["path"], paths, "agent path")
        text = read_text(root, agent["path"])
        require(POLICY in text and GUIDE in text, f"agent {name} must link the shared policy and guide")
        registered[name] = (agent["path"], kind)
        if kind == "canonical":
            canonical.append(name)
    require(canonical == ["codex"], "exactly one canonical agent, codex, is required")
    for name, expected in REQUIRED_AGENTS.items():
        require(registered.get(name) == expected, f"missing or altered required agent: {name}")
    canonical_policy = read_file(root, POLICY)
    for path, kind in registered.values():
        if kind == "mirror":
            require(canonical_policy == read_file(root, path), "mirrored policy must be byte-identical to AGENTS.md")
    return len(registered)


def strip_plain_comment(value):
    """Remove unquoted inline comments in one bounded pass over the scalar."""
    for index, character in enumerate(value):
        if character == "#" and index > 0 and value[index - 1].isspace():
            return value[:index].rstrip()
    return value.rstrip()


def frontmatter_value(value):
    """Read a supported single-line string without a general YAML dependency."""
    if value.startswith(("'", '"')):
        require(len(value) >= 2 and value[-1] == value[0], "unclosed frontmatter scalar")
        if value[0] == '"':
            return json.loads(value)
        inner = value[1:-1]
        require("'" not in inner.replace("''", ""), "invalid single-quoted frontmatter scalar")
        return inner.replace("''", "'")
    value = strip_plain_comment(value)
    require(value.lower() not in ("null", "~", "true", "false", "yes", "no", "on", "off"),
            "nonstring frontmatter scalar")
    require(not value.startswith(tuple("[]{}#&*!|>%@`:")), "unsupported plain frontmatter scalar")
    require(re.match(r"[-?](?:\s|$)", value) is None, "unsupported plain frontmatter scalar")
    require(re.fullmatch(r"[+-]?(?:\d[\d_.a-fxo:+-]*|\.\d+(?:e[+-]?\d+)?|\.inf|\.nan)", value, re.ASCII | re.IGNORECASE) is None,
            "nonstring numeric frontmatter scalar")
    require(re.match(r"\d{4}-\d{2}-\d{2}(?:$|[Tt ])", value, re.ASCII) is None,
            "nonstring timestamp frontmatter scalar")
    require(re.search(r":(?:\s|$)", value) is None, "unsupported plain frontmatter mapping")
    return value.strip()


def block_description(lines, index):
    """Consume a description block with consistent space indentation."""
    body = []
    minimum = None
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        if not line[0].isspace():
            break
        indentation = len(line) - len(line.lstrip(" "))
        require(indentation >= 2 and "\t" not in line[:indentation + 1], "invalid frontmatter block indentation")
        if minimum is None:
            minimum = indentation
        require(indentation >= minimum, "inconsistent frontmatter block indentation")
        body.append(line.strip())
        index += 1
    return " ".join(body), index


def trigger_list(lines, index):
    """Consume only the two-space string-list syntax used by existing Qodo skills."""
    triggers = []
    while index < len(lines):
        line = lines[index]
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        if not line[0].isspace():
            break
        require(line.startswith("  - "), "invalid frontmatter trigger list indentation")
        value = frontmatter_value(line[4:].lstrip())
        triggers.append(nonempty_string(value, "skill trigger"))
        index += 1
    require(bool(triggers), "skill triggers must be a nonempty string list")
    return triggers, index


def header_value(key, value, lines, index):
    """Validate one supported field and return the next unconsumed header line."""
    if key == "triggers":
        require(not value, "skill triggers require an indented string list")
        return trigger_list(lines, index + 1)
    if value in BLOCK_SCALARS:
        require(key == DESCRIPTION, f"skill {key} must be a single-line scalar")
        parsed, next_index = block_description(lines, index + 1)
    else:
        parsed, next_index = frontmatter_value(value), index + 1
    return nonempty_string(parsed, f"skill {key}"), next_index


def skill_frontmatter(text):
    """Validate the complete supported header, including optional Qodo fields."""
    lines = text.splitlines()
    require(bool(lines) and lines[0] == "---", "skill must start with YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        raise ValueError("skill frontmatter is not closed") from error
    metadata = {}
    header = lines[1:end]
    index = 0
    while index < len(header):
        line = header[index]
        if not line.strip() or line.lstrip().startswith("#"):
            index += 1
            continue
        require(not line[0].isspace(), "unexpected frontmatter field indentation")
        key, separator, value = line.partition(":")
        require(separator and key in FRONTMATTER_FIELDS, f"unsupported skill frontmatter field: {key}")
        require(not value or value[0].isspace(), "frontmatter field requires whitespace after colon")
        require(key not in metadata, f"duplicate skill frontmatter key: {key}")
        metadata[key], index = header_value(key, value.lstrip(), header, index)
    require({"name", DESCRIPTION} <= set(metadata), "skill name and description are required")
    return metadata


def discover_skills(root):
    """Inventory immediate skill directories without following linked paths."""
    directory = open_directory(root, [".agents", "skills"])
    discovered = set()
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                require(not entry.is_symlink(), f"symlink in skill inventory: {entry.name}")
                if not entry.is_dir(follow_symlinks=False):
                    continue
                relative = f".agents/skills/{entry.name}/SKILL.md"
                try:
                    read_file(root, relative)
                except FileNotFoundError:
                    continue
                discovered.add(relative)
    finally:
        os.close(directory)
    return discovered


def validate_skills(root, skills):
    """Verify all registered skills and preserve the existing Qodo adapters."""
    names = set()
    paths = set()
    for skill in records(skills, "skills"):
        fields(skill, ("name", "path"), "skill")
        name = identifier(skill["name"], "skill name")
        claim(name, names, "skill name")
        path_parts(skill["path"])
        claim(skill["path"], paths, "skill path")
        require(skill["path"] == f".agents/skills/{name}/SKILL.md", f"unexpected skill path: {skill['path']}")
        text = read_text(root, skill["path"])
        require(skill_frontmatter(text)["name"] == name, f"skill frontmatter name mismatch: {name}")
        require(POLICY in text, f"skill {name} must link AGENTS.md")
    require(REQUIRED_SKILLS <= names, "existing Qodo skills must remain registered")
    require(discover_skills(root) == paths, "discovered skills and registry do not match")
    return names


def validate_integrations(integrations, skill_names):
    """Check explicit provider status and references without implying activation."""
    identifiers = set()
    names = set()
    for integration in records(integrations, "integrations"):
        fields(integration, ("id", "name", "mode", "skills", "notes", "source"), "integration")
        provider = identifier(integration["id"], "integration ID")
        claim(provider, identifiers, "integration ID")
        name = nonempty_string(integration["name"], "integration name")
        claim(name, names, "integration name")
        nonempty_string(integration["notes"], "integration notes")
        nonempty_string(integration["source"], "integration source")
        mode = integration["mode"]
        require(isinstance(mode, str) and mode in MODES, f"invalid integration mode: {mode}")
        references = integration["skills"]
        require(isinstance(references, list), "integration skills must be an array")
        seen = set()
        for reference in references:
            identifier(reference, "skill reference")
            claim(reference, seen, "skill reference")
            require(reference in skill_names, f"unknown skill reference: {reference}")
        require(mode != "repository-skill" or bool(references), "repository-skill integration needs a skill")
        require(mode not in INACTIVE_MODES or not references, "inactive integration cannot claim active skills")
    missing = REQUIRED_INTEGRATIONS - identifiers
    require(not missing, f"missing requested integrations: {', '.join(sorted(missing))}")
    return len(identifiers)


def validate_repository(root):
    """Verify the complete registry, pointers, mirror, and local skill inventory."""
    manifest = json.loads(read_text(root, MANIFEST), object_pairs_hook=unique_object, parse_constant=reject_constant)
    fields(manifest, ("version", "canonical_policy", "guide", "agents", "skills", "integrations"), "manifest")
    require(type(manifest["version"]) is int and manifest["version"] == 1, "unsupported registry version")
    require(manifest["canonical_policy"] == POLICY, "canonical policy must be AGENTS.md")
    require(manifest["guide"] == GUIDE, f"integration guide must be {GUIDE}")
    nonempty_string(read_text(root, GUIDE), "integration guide")
    agent_count = validate_agents(root, manifest["agents"])
    skill_names = validate_skills(root, manifest["skills"])
    integration_count = validate_integrations(manifest["integrations"], skill_names)
    return agent_count, len(skill_names), integration_count


def main(argv=None):
    """Expose a read-only CI check with concise success and failure messages."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args(argv)
    try:
        agents, skills, integrations = validate_repository(DEFAULT_ROOT)
    except (ValueError, OSError) as error:
        print(f"FAIL agent integrations: {error}", file=sys.stderr)
        return 1
    print(f"PASS agent integrations: {agents} agent configurations, {skills} skills, {integrations} integration records")
    return 0


if __name__ == "__main__":
    sys.exit(main())
