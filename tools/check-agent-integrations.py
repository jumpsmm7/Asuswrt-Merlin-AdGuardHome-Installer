#!/usr/bin/env python3
"""Check the shared agent registry without executing providers or changing files."""

import argparse
import json
import os
import re
import stat
import sys
from pathlib import Path
from urllib.parse import urlsplit

try:
    import tomllib
except ModuleNotFoundError:
    tomllib = None


DEFAULT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ".agents/integrations.json"
GUIDE = "docs/agent-integrations.md"
POLICY = "AGENTS.md"
MCP_SOURCE = ".mcp.json"
MCP_ASSETS = (MCP_SOURCE, ".codex/config.toml", ".amazonq/mcp.json", ".cursor/mcp.json", ".kiro/settings/mcp.json",
              ".agents/mcp-templates/vscode.json")
REQUIRED_MCP_SERVERS = {"context7", "firecrawl", "lovable"}
LOVABLE_CURSOR_AUTH = {"CLIENT_ID": "6d465f583e1e4ce5801b1616f735670c"}
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


def read_json(root, relative):
    """Read strict JSON through the same no-follow repository boundary."""
    return json.loads(read_text(root, relative), object_pairs_hook=unique_object, parse_constant=reject_constant)


def validate_mcp_url(value, label):
    """Require a literal HTTPS endpoint without embedded credentials or fragments."""
    value = nonempty_string(value, label)
    value.encode("utf-8")
    require("\\" not in value and not any(character.isspace() or ord(character) < 32 or ord(character) == 127 for character in value),
            f"invalid {label}")
    parsed = urlsplit(value)
    require(parsed.scheme == "https" and bool(parsed.hostname) and parsed.port != 0,
            f"{label} must be an HTTPS endpoint")
    require(parsed.username is None and parsed.password is None and not parsed.fragment,
            f"{label} cannot contain credentials or a fragment")
    return value


def mcp_servers(config, key, path):
    """Reject wrappers and server IDs outside the declared client format."""
    fields(config, (key,), path)
    servers = config[key]
    require(isinstance(servers, dict) and bool(servers), f"{path} {key} must be a nonempty object")
    for name in servers:
        identifier(name, "MCP server ID")
    return servers


def validate_mcp_mirror(servers, canonical, path, kind):
    """Compare complete inventory while preserving each client's native shape."""
    require(set(servers) == set(canonical), f"MCP server inventory mismatch: {path}")
    for name, server in servers.items():
        label = f"{path} server {name}"
        expected = {"url"}
        if kind == "codex":
            expected.add("enabled")
        elif kind != "kiro":
            expected.add("type")
        if kind == "cursor" and name == "lovable":
            expected.add("auth")
        fields(server, expected, label)
        require(server["url"] == canonical[name]["url"], f"MCP URL mismatch: {label}")
        if "type" in expected:
            require(server["type"] == "http", f"MCP transport must be http: {label}")
        if "enabled" in expected:
            require(server["enabled"] is True, f"MCP server must be enabled: {label}")
        if "auth" in expected:
            require(server["auth"] == LOVABLE_CURSOR_AUTH, f"unsupported MCP OAuth configuration: {label}")


def validate_mcp(root):
    """Verify the shared remote catalog and all repository MCP client mirrors."""
    canonical = mcp_servers(read_json(root, MCP_SOURCE), "mcpServers", MCP_SOURCE)
    require(REQUIRED_MCP_SERVERS <= set(canonical), "missing required MCP servers")
    for name, server in canonical.items():
        label = f"{MCP_SOURCE} server {name}"
        fields(server, ("type", "url"), label)
        require(server["type"] == "http", f"MCP transport must be http: {label}")
        validate_mcp_url(server["url"], f"MCP URL: {label}")
    require(tomllib is not None, "MCP configuration validation requires Python 3.11 or newer")
    codex_path = ".codex/config.toml"
    codex = mcp_servers(tomllib.loads(read_text(root, codex_path)), "mcp_servers", codex_path)
    validate_mcp_mirror(codex, canonical, codex_path, "codex")
    for path, kind in ((".amazonq/mcp.json", "amazonq"), (".cursor/mcp.json", "cursor"),
                       (".kiro/settings/mcp.json", "kiro"), (".agents/mcp-templates/vscode.json", "vscode")):
        key = "servers" if kind == "vscode" else "mcpServers"
        servers = mcp_servers(read_json(root, path), key, path)
        validate_mcp_mirror(servers, canonical, path, kind)
    return len(canonical)


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
        if character == "#" and index > 0 and value[index - 1] in " \t":
            return value[:index].rstrip(" \t")
    return value.rstrip(" \t")


def decoded_string(value):
    """Require quoted decoded strings to contain portable Unicode scalar values."""
    value.encode("utf-8")
    return value


def space_indented_content(line, label):
    """Check ASCII-space layout before deciding whether a line is ignorable."""
    content = line.lstrip(" ")
    require(not content or not content[0].isspace(), f"invalid {label} indentation")
    return content


def frontmatter_value(value):
    """Read a supported single-line string without a general YAML dependency."""
    if value.startswith(("'", '"')):
        require(len(value) >= 2 and value[-1] == value[0], "unclosed frontmatter scalar")
        if value[0] == '"':
            return decoded_string(json.loads(value))
        inner = value[1:-1]
        require("'" not in inner.replace("''", ""), "invalid single-quoted frontmatter scalar")
        return decoded_string(inner.replace("''", "'"))
    value = strip_plain_comment(value)
    require(value.lower() not in ("null", "~", "true", "false", "yes", "no", "on", "off"),
            "nonstring frontmatter scalar")
    require(not value.startswith(tuple(",[]{}#&*!|>%@`:")), "unsupported plain frontmatter scalar")
    require(re.match(r"[-?](?:[ \t]|$)", value) is None, "unsupported plain frontmatter scalar")
    require(re.fullmatch(r"[+-]?(?:\d[\d_.a-fxo:+-]*|\.\d+(?:e[+-]?\d+)?|\.inf|\.nan)", value, re.ASCII | re.IGNORECASE) is None,
            "nonstring numeric frontmatter scalar")
    require(re.match(r"\d{4}-\d{2}-\d{2}(?:$|[Tt ])", value, re.ASCII) is None,
            "nonstring timestamp frontmatter scalar")
    require(re.search(r":(?:[ \t]|$)", value) is None, "unsupported plain frontmatter mapping")
    return value.strip(" \t")


def block_description(lines, index):
    """Consume a description block with consistent space indentation."""
    body = []
    minimum = None
    while index < len(lines):
        line = lines[index]
        if not line.strip(" "):
            index += 1
            continue
        if not line[0].isspace():
            break
        indentation = len(line) - len(line.lstrip(" "))
        require(indentation >= 2 and "\t" not in line[:indentation + 1], "invalid frontmatter block indentation")
        if minimum is None:
            minimum = indentation
        require(indentation >= minimum, "inconsistent frontmatter block indentation")
        body.append(line.strip(" \t"))
        index += 1
    return " ".join(body), index


def trigger_list(lines, index):
    """Consume only the two-space string-list syntax used by existing Qodo skills."""
    triggers = []
    while index < len(lines):
        line = lines[index]
        content = space_indented_content(line, "frontmatter trigger list")
        if not content or content.startswith("#"):
            index += 1
            continue
        if line == content:
            break
        require(line.startswith("  - "), "invalid frontmatter trigger list indentation")
        value = frontmatter_value(line[4:].lstrip(" \t"))
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
        content = space_indented_content(line, "frontmatter field")
        if not content or content.startswith("#"):
            index += 1
            continue
        require(line == content, "unexpected frontmatter field indentation")
        key, separator, value = line.partition(":")
        require(separator and key in FRONTMATTER_FIELDS, f"unsupported skill frontmatter field: {key}")
        require(not value or value[0] in " \t", "frontmatter field requires ASCII whitespace after colon")
        require(key not in metadata, f"duplicate skill frontmatter key: {key}")
        metadata[key], index = header_value(key, value.lstrip(" \t"), header, index)
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
    manifest = read_json(root, MANIFEST)
    fields(manifest, ("version", "canonical_policy", "guide", "agents", "skills", "integrations"), "manifest")
    require(type(manifest["version"]) is int and manifest["version"] == 1, "unsupported registry version")
    require(manifest["canonical_policy"] == POLICY, "canonical policy must be AGENTS.md")
    require(manifest["guide"] == GUIDE, f"integration guide must be {GUIDE}")
    nonempty_string(read_text(root, GUIDE), "integration guide")
    agent_count = validate_agents(root, manifest["agents"])
    skill_names = validate_skills(root, manifest["skills"])
    integration_count = validate_integrations(manifest["integrations"], skill_names)
    validate_mcp(root)
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
