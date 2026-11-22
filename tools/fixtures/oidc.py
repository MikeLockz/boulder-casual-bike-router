"""Synthetic TLS provider: no household identities, real tokens or external network."""
import base64
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import ssl
import urllib.parse

SECRET='fixture-confidential-client-secret-not-for-real-use'
USERS={
    'existing':dict(sub='subject-existing',email='existing@fixture.invalid',email_verified=True,groups=['family']),
    'new-email':dict(sub='subject-another',email='changed@fixture.invalid',email_verified=True,groups=['kids']),
    'denied':dict(sub='subject-denied',email='denied@fixture.invalid',email_verified=True,groups=['unknown']),
    'unverified':dict(sub='subject-unverified',email='unverified@fixture.invalid',email_verified=False,groups=['family']),
    'storage-fail':dict(sub='storage-fail',email='failed@fixture.invalid',email_verified=True,groups=['admins']),
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass

    def reply(self,status,value):
        data=json.dumps(value).encode();self.send_response(status)
        self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)))
        self.end_headers();self.wfile.write(data)

    def do_POST(self):
        form=urllib.parse.parse_qs(self.rfile.read(int(self.headers.get('Content-Length','0'))).decode())
        expected='Basic '+base64.b64encode(('boulder-lockdev:'+SECRET).encode()).decode()
        valid=(self.path=='/api/oidc/token' and self.headers.get('Authorization')==expected and
               form.get('code_verifier')==['x'*64] and form.get('redirect_uri',[''])[0] in
               ['https://boulder.lockdev.com/pb/api/oauth2-redirect','com.lockdev.boulder:/oauth2redirect'])
        code=form.get('code',[''])[0]
        if not valid or code not in USERS:return self.reply(400,{'error':'invalid_grant'})
        self.reply(200,{'access_token':code,'token_type':'Bearer','expires_in':300})

    def do_GET(self):
        token=self.headers.get('Authorization','').removeprefix('Bearer ')
        if self.path!='/api/oidc/userinfo' or token not in USERS:return self.reply(401,{'error':'invalid_token'})
        self.reply(200,USERS[token])


server=HTTPServer(('0.0.0.0',443),Handler)
context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain('/fixture/cert.pem','/fixture/key.pem')
server.socket=context.wrap_socket(server.socket,server_side=True);server.serve_forever()
