#!/usr/bin/env python3
"""Create the bounded, code-only image descriptor signed by the release workflow."""
import json
import os
from pathlib import Path
import re

source = os.environ['GITHUB_SHA']
if not re.fullmatch(r'[0-9a-f]{40}', source):
    raise SystemExit('Invalid source revision')
images = {}
for component in ['backend', 'frontend', 'pocketbase']:
    digest = os.environ[component.upper() + '_DIGEST']
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise SystemExit('Invalid ' + component + ' image digest')
    images[component] = 'ghcr.io/mikelockz/boulder-casual-bike-router-' + component + '@' + digest
Path('release.json').write_text(json.dumps({
    'format': 1, 'repository': 'MikeLockz/boulder-casual-bike-router',
    'workflow': '.github/workflows/release.yml', 'source': source, 'images': images
}, indent=2) + '\n')
