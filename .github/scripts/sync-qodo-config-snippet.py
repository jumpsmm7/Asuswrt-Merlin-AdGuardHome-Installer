from pathlib import Path

canonical_path = Path('.agents/skills/qodo-get-rules/config-parsing.sh')
skill_path = Path('.agents/skills/qodo-get-rules/SKILL.md')
canonical = canonical_path.read_text()
skill = skill_path.read_text()
marker = 'Example config parsing:\n\n```bash\n'
start = skill.find(marker)
if start < 0:
    raise SystemExit('SKILL.md: config parsing example marker not found')
start += len(marker)
end = skill.find('```\n', start)
if end < 0:
    raise SystemExit('SKILL.md: config parsing example closing fence not found')
skill_path.write_text(skill[:start] + canonical + skill[end:])
