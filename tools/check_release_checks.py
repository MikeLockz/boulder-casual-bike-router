#!/usr/bin/env python3
"""Require successful checks at the exact source SHA before publishing a release."""
import json
import os
import re
import time
import urllib.request

sha = os.environ['GITHUB_SHA']
if not re.fullmatch(r'[0-9a-f]{40}', sha) or os.environ['GITHUB_REF'] != 'refs/heads/main':
    raise SystemExit('Releases must use an exact main-branch source revision')
required = {'service-access-policy', 'application-tests', 'image-build', 'ios-auth-tests'}
deadline = time.monotonic() + 900
while time.monotonic() < deadline:
    request = urllib.request.Request(
        f'https://api.github.com/repos/MikeLockz/boulder-casual-bike-router/commits/{sha}/check-runs?per_page=100',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
    with urllib.request.urlopen(request, timeout=20) as response:
        checks = json.load(response)['check_runs']
    latest = {}
    for check in checks:
        if check['name'] in required and check.get('app', {}).get('slug') == 'github-actions':
            if check['id'] > latest.get(check['name'], {}).get('id', 0):
                latest[check['name']] = check
    failed = [name for name, check in latest.items()
              if check['status'] == 'completed' and check['conclusion'] != 'success']
    if failed:
        raise SystemExit('Required checks failed: ' + ', '.join(sorted(failed)))
    if required <= latest.keys() and all(latest[name]['conclusion'] == 'success' for name in required):
        print('All required checks passed at source ' + sha)
        break
    time.sleep(15)
else:
    raise SystemExit('Required checks were missing/pending after 15 minutes')
