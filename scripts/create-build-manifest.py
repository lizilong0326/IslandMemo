#!/usr/bin/env python3
"""Record source identity when a user explicitly requests a distributable app."""
import datetime
import hashlib
import json
import plistlib
import subprocess
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
paths = sorted([*root.glob('Sources/**/*.swift'), root / 'Package.swift', root / 'Package.resolved', root / 'Resources/Info.plist'])
digest = hashlib.sha256()
for path in paths:
    if path.is_file():
        digest.update(str(path.relative_to(root)).encode() + b'\0' + path.read_bytes() + b'\0')
manifest = {
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'builtAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'gitCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'workingTreeDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip()),
    'sourceSHA256': digest.hexdigest(), 'configuration': 'release',
    'validation': ['swift build -c release'], 'signing': 'local ad hoc',
    'note': 'Only the listed build check is recorded automatically; GUI and external services require separate validation.'
}
(app / 'Contents/Resources/build-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
