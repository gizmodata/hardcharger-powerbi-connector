import re
import sys
from pathlib import Path
version = sys.argv[1]
if not re.fullmatch(r'v\d+\.\d+\.\d+', version):
    raise SystemExit('Release tag must be vX.Y.Z')
connector = Path('Hardcharger.pq').read_text()
if f'[Version = "{version[1:]}"]' not in connector:
    raise SystemExit('Tag and connector version differ')
match = re.search(r'^## \[' + re.escape(version) + r'\][^\n]*\n(.*?)(?=^## \[|\Z)',
                  Path('CHANGELOG.md').read_text(), re.M | re.S)
if not match or not match[1].strip():
    raise SystemExit('Missing release changelog')
print(match[1].strip())
