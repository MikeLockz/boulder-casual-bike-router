#!/usr/bin/env python3
"""Exercise production hooks in PocketBase against an isolated synthetic TLS IdP."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT=Path(__file__).resolve().parents[1]
PYTHON='python:3.11-slim@sha256:07d4824036af339fa1b6ef769cc99d9c10a141769538b52b3b597c84f7a7b535'


def docker(*args,check=True):
    result=subprocess.run(['docker',*args],cwd=ROOT,capture_output=True,text=True,timeout=120)
    if check and result.returncode:raise RuntimeError('Disposable Docker command failed (no container logs disclosed)')
    return result.stdout


def main():
    prefix='household-oidc-test-'+uuid.uuid4().hex[:8];network=prefix;volume=prefix+'-data';names=[]
    docker('network','create','--internal',network);docker('volume','create',volume)
    try:
        with tempfile.TemporaryDirectory(prefix=prefix) as temporary:
            stage=Path(temporary);stage.chmod(0o755);(stage/'hooks').mkdir()
            for path in (ROOT/'pb_hooks').glob('*.js'):shutil.copyfile(path,stage/'hooks'/path.name)
            shutil.copyfile(ROOT/'tools/fixtures/household.pb.js',stage/'hooks/fixture.pb.js')
            shutil.copyfile(ROOT/'tools/fixtures/oidc.py',stage/'oidc.py')
            (stage/'oidc.json').write_text(json.dumps({'client_id':'boulder-lockdev','client_secret':'fixture-confidential-client-secret-not-for-real-use'}))
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1',
                '-subj','/CN=authelia.lockdev.com','-addext','subjectAltName=DNS:authelia.lockdev.com',
                '-keyout',str(stage/'key.pem'),'-out',str(stage/'cert.pem')],capture_output=True,check=True,timeout=30)
            (stage/'key.pem').chmod(0o644) # Synthetic fixture key only, private host directory.
            image=prefix+':pocketbase';docker('build','-q','-f','Dockerfile.pocketbase','-t',image,'.')
            provider=prefix+'-provider';names.append(provider)
            docker('run','-d','--name',provider,'--network',network,'--network-alias','authelia.lockdev.com',
                '--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
                '--sysctl','net.ipv4.ip_unprivileged_port_start=0','--user','10001:10001',
                '-v',str(stage)+':/fixture:ro',PYTHON,'python','/fixture/oidc.py')
            pocketbase=prefix+'-pocketbase';names.append(pocketbase)
            def start(recovery):
                docker('run','-d','--name',pocketbase,'--network',network,'--network-alias','pocketbase','--read-only','--cap-drop','ALL',
                    '--security-opt','no-new-privileges:true','--tmpfs','/tmp:size=32m,mode=1777',
                    '-v',volume+':/pb_data','-v',str(stage/'hooks')+':/pb_hooks:ro',
                    '-v',str(stage/'oidc.json')+':/run/secrets/boulder-oidc.json:ro',
                    '-v',str(stage/'cert.pem')+':/run/secrets/fixture-ca.pem:ro',
                    '-e','SSL_CERT_FILE=/run/secrets/fixture-ca.pem','-e','BOULDER_TEST_FIXTURE=1',
                    '-e','BOULDER_HOUSEHOLD_OIDC=1','-e','BOULDER_HOUSEHOLD_PASSWORD_RECOVERY='+recovery,image)
                return 'http://pocketbase:8090'
            base=start('1')
            def request(path,body=None,token=None):
                # Execute the test client on the same internal-only network;
                # Docker intentionally does not publish internal-network ports.
                program = """import json,urllib.request,urllib.error,sys
base,path,body,token=json.loads(sys.argv[1])
headers={'Content-Type':'application/json'}
if token:headers['Authorization']=token
req=urllib.request.Request(base+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
try:
    with urllib.request.urlopen(req,timeout=5) as response:print(json.dumps([response.status,json.load(response)]))
except urllib.error.HTTPError as error:print(json.dumps([error.code,json.load(error)]))
"""
                return json.loads(docker('exec',provider,'python','-c',program,json.dumps([base,path,body,token])))
            def ready():
                deadline=time.monotonic()+30
                while True:
                    try:
                        if request('/api/health')[0]==200:return
                    except (OSError,ValueError,RuntimeError):pass
                    if time.monotonic()>deadline:raise RuntimeError('PocketBase fixture startup deadline')
                    time.sleep(.5)
            ready()
            def password(email):
                status,data=request('/api/collections/users/auth-with-password',{'identity':email,'password':'fixture-password-for-local-tests'})
                assert status==200,('fixture password',status);return data['token']
            def oauth(code,token=None,native=False):
                return request('/api/collections/users/auth-with-oauth2',{'provider':'oidc','code':code,'codeVerifier':'x'*64,
                    'redirectURL':'com.lockdev.boulder:/oauth2redirect' if native else 'https://boulder.lockdev.com/pb/api/oauth2-redirect'},token)
            assert oauth('existing')[0]==403,'Email fallback linked without consent'
            existing=password('existing@fixture.invalid')
            status,data=oauth('existing',existing);assert status==200 and data['record']['id']=='fixtureexisting',('controlled linking',status)
            assert request('/api/collections/users/auth-refresh',{},data['token'])[0]==200,'Admission metadata missing before token use'
            status,data=oauth('existing',native=True);assert status==200 and data['record']['id']=='fixtureexisting','Native redirect/server exchange failed'
            another=password('another@fixture.invalid')
            assert oauth('existing',another)[0]==403,'Linked identity switched authenticated profiles'
            status,data=oauth('new-email',another);assert status==200 and data['record']['id']=='fixtureanother1','Changed email created another profile'
            assert oauth('denied')[0]==403 and oauth('unverified')[0]==403
            failed=password('failed@fixture.invalid');status,data=oauth('storage-fail',failed)
            assert status>=400 and 'token' not in data,'Metadata save failure issued a token'
            request('/__fixture/expire',{'id':'fixtureexisting'})
            token=password('existing@fixture.invalid')
            assert request('/api/collections/users/auth-refresh',{},token)[0]==200,'Retained recovery stopped working after linking'
            docker('rm','-f',pocketbase);base=start('0');ready()
            status,methods=request('/api/collections/users/auth-methods');assert status==200 and not methods['password']['enabled']
            assert request('/api/collections/users/auth-refresh',{},token)[0]==401,'Acceptance did not revoke retained password sessions'
            assert oauth('existing')[0]==200,'Shared sign-in failed after closing password recovery'
            print('Real PocketBase: web/native exchange, controlled linking, denied claims, fail-closed metadata and recovery switch passed')
    finally:
        for name in reversed(names):docker('rm','-f',name,check=False)
        docker('network','rm',network,check=False);docker('volume','rm',volume,check=False)
        docker('image','rm',prefix+':pocketbase',check=False)


if __name__=='__main__':main()
