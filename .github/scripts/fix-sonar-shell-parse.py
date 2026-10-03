"""Apply SonarQube shell parser compatibility fixes to AdGuardHome.sh.

This script transforms shell parameter expansion syntax that the SonarQube
shell parser cannot parse into equivalent conditional forms. The rewrite
preserves runtime behavior while enabling Sonar analysis to proceed.

The script replaces conditional parameter expansion with explicit conditionals
to work around parser limitations, ensuring the modified script remains
functionally identical to the original.
"""
from pathlib import Path

path = Path("AdGuardHome.sh")
text = path.read_text()
old = '\tprintf \'%s\\n\' "${state}${markers:+ (${markers})}"\n'
new = (
    '\tif [ -n "${markers}" ]; then\n'
    '\t\tprintf \'%s\\n\' "${state} (${markers})"\n'
    '\telse\n'
    '\t\tprintf \'%s\\n\' "${state}"\n'
    '\tfi\n'
)
old_count = text.count(old)
new_count = text.count(new)

if old_count == 1 and new_count == 0:
    path.write_text(text.replace(old, new, 1))
elif old_count == 0 and new_count == 1:
    print("AdGuardHome.sh: Sonar parser cleanup already applied")
else:
    raise SystemExit(
        "AdGuardHome.sh: unexpected status marker state "
        f"(old={old_count}, new={new_count})"
    )
