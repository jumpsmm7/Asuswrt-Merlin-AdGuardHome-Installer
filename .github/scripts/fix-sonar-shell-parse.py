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
count = text.count(old)
if count != 1:
    raise SystemExit(f"AdGuardHome.sh: expected one status marker expression, found {count}")
path.write_text(text.replace(old, new, 1))
