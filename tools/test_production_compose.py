#!/usr/bin/env python3
"""Exercise production mount/permission/network/startup definitions on a clean CI VM."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request


def run(command, timeout=60):
    return subprocess.run(command, check=True, timeout=timeout)


def main():
    # These exact absolute locations are production's declared host boundary.
    # Never initialize or replace data on a real host or a reused developer VM.
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
        raise SystemExit('Disposable GitHub-hosted runner required')
    destination=Path('/srv/lockdev-apps/data/boulder')
    if destination.exists():
        raise SystemExit('Refusing an existing application data directory')
    run(['sudo','install','-d','-m','700','/etc/lockdev-apps/boulder'])
    run(['sudo','install','-d','-m','755',str(destination)])
    run(['sudo','install','-d','-o','10001','-g','10001','-m','750',str(destination/'graphs')])
    with tempfile.TemporaryDirectory(prefix='boulder-compose-check-') as temporary:
        root=Path(temporary)
        (root/'oidc.json').write_text(json.dumps({'client_id':'boulder-lockdev','client_secret':'disposable-not-a-real-provider-credential-00000000'}))
        run(['sudo','install','-m','600',str(root/'oidc.json'),'/etc/lockdev-apps/boulder/oidc.json'])
        for component,file in [('backend','Dockerfile.production'),('frontend','Dockerfile.frontend'),('pocketbase','Dockerfile.pocketbase')]:
            run(['docker','buildx','build','--load','-f',file,'-t','boulder-compose-check:'+component,'.'],300)
        environment=root/'release.env'
        environment.write_text('\n'.join('BOULDER_'+component.upper()+'_IMAGE=boulder-compose-check:'+component for component in ['backend','frontend','pocketbase'])+'\n')
        for network in ['lockdev-apps-ingress','lockdev-apps-metrics']:
            run(['docker','network','create','--internal',network])
        compose=['docker','compose','--env-file',str(environment),'-f','compose.production.yml']
        try:
            run(compose+['config','-q'])
            run(compose+['up','-d','--no-build','--wait','--wait-timeout','420'],450)
            for region in ['boulder','broomfield']:
                run(compose+['exec','-T','boulder-frontend','wget','-q','-O','/dev/null','http://127.0.0.1:8080/api/health?region='+region])
            frontend=subprocess.check_output(compose+['ps','-q','boulder-frontend'],text=True).strip()
            address=json.loads(subprocess.check_output(['docker','inspect',frontend]))[0]['NetworkSettings']['Networks']['lockdev-apps-ingress']['IPAddress']
            def status(path):
                try:
                    with urllib.request.urlopen('http://'+address+':8080'+path,timeout=5) as response:
                        return response.status
                except urllib.error.HTTPError as error:return error.code
            assert status('/pb/api/health')==200
            assert status('/pb/api/collections/users/auth-methods')==200
            query="import sqlite3,json; db=sqlite3.connect('file:/srv/lockdev-apps/data/boulder/pocketbase/data.db?mode=ro',uri=True); print(json.dumps([r[0] for r in db.execute(\"select id from _collections where name in ('navigation_routes','navigation_ticks','place_search_events','route_analytics_events','_superusers')\")]))"
            ids=json.loads(subprocess.check_output(['sudo','python3','-c',query]))
            for name in ['navigation_routes','navigation_ticks','place_search_events','route_analytics_events','_superusers',*ids]:
                assert status('/pb/api/collections/'+name+'/records')==404, 'Direct data collection exposed: '+name
            for path in ['/pb/_/','/pb/api/settings','/pb/api/collections','/pb/api/batch','/pb/api/backups','/pb/api/files/anything',
                         '/pb/api/collections/users/impersonate/fixtureexisting']:
                assert status(path)==404, 'Non-client PocketBase API exposed: '+path
        finally:
            # Avoid PocketBase logs: first-run administrative URLs contain tokens.
            run(compose+['ps','--all'])
            run(compose+['down','--timeout','20'],60)
            for network in ['lockdev-apps-ingress','lockdev-apps-metrics']:
                run(['docker','network','rm',network])


if __name__=='__main__':main()
