"""Loopback-only Chargewire OAuth contract fixtures for the actual M HTTP client.

Port 31338 answers like a current Hardcharger server. Port 31339 answers like one
released before the protocol was renamed (PreRenameCompat.pqm): no discovery
document at /chargewire, the protocol under the earlier root.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading

CURRENT = {'port': 31338, 'root': '/chargewire', 'protocol': 'chargewire'}
PRE_RENAME = {'port': 31339, 'root': '/warp', 'protocol': 'warp-sql'}


def handler(server):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def reply(self, status, body):
            content = json.dumps(body).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        def do_GET(self):
            if self.path == server['root']:
                self.reply(200, {'protocol': server['protocol'], 'protocol_versions': ['1']})
            else:
                self.reply(200 if self.path == '/health' else 404, {})

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            with Path('test-results/oauth-requests.jsonl').open('a') as stream:
                stream.write(json.dumps({'port': server['port'], 'path': self.path, 'body': body}) + '\n')
            flows = server['root'] + '/v1/auth/oauth/flows'
            if self.path == flows and body == {'return_to': '/?powerbi_signin_complete=1'}:
                self.reply(201, {'flow_id':'test-flow', 'poll_secret':'test-poll-secret',
                                'authorize_url':'https://idp.example.test/authorize?flow=test-flow',
                                'poll_interval_s':1})
            elif self.path == flows + '/test-flow' and body == {'poll_secret':'test-poll-secret'}:
                self.reply(200, {'state':'complete', 'access_token':'test-access-token',
                                'token_type':'Bearer', 'expires_in':3600})
            else:
                self.reply(404 if not self.path.startswith(server['root'] + '/') else 400,
                           {'error':'OAuth request does not match the Chargewire contract'})

    return Handler


servers = [ThreadingHTTPServer(('127.0.0.1', s['port']), handler(s)) for s in (CURRENT, PRE_RENAME)]
for extra in servers[1:]:
    threading.Thread(target=extra.serve_forever, daemon=True).start()
servers[0].serve_forever()
