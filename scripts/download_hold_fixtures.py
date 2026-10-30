#!/usr/bin/env python3
"""Download local-only Commons evaluation photos and generate their attribution file."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
fixtures = json.loads((ROOT / 'scripts/hold_highlight_fixtures.json').read_text())
folder = ROOT / 'build/fixtures'
folder.mkdir(parents=True, exist_ok=True)
for fixture in fixtures:
    target = folder / fixture['filename']
    if not target.exists():
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '-A',
                        'ClimbingAppFixtures/1.0 (local image quality evaluation)', fixture['url'],
                        '-o', str(target)], check=True)
lines = ['# Local evaluation photograph sources', '', 'Photos are not bundled or committed. Derived evaluation images retain the source license.', '']
for f in fixtures:
    lines += [f"- **{f['filename']}** — [{f['author']}]({f['source']}), {f['license']}", f"  Download: {f['url']}"]
(folder / 'SOURCES.md').write_text('\n'.join(lines) + '\n')
print(folder)
