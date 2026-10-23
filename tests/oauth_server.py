"""Loopback-only Warp SQL OAuth contract fixture for the actual M HTTP client."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path

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
        self.reply(200 if self.path == '/health' else 404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with Path('test-results/oauth-requests.jsonl').open('a') as stream:
            stream.write(json.dumps({'path': self.path, 'body': body}) + '\n')
        if self.path == '/warp/v1/auth/oauth/flows' and body == {'return_to': '/?powerbi_signin_complete=1'}:
            self.reply(201, {'flow_id':'test-flow', 'poll_secret':'test-poll-secret',
                            'authorize_url':'https://idp.example.test/authorize?flow=test-flow',
                            'poll_interval_s':1})
        elif self.path == '/warp/v1/auth/oauth/flows/test-flow' and body == {'poll_secret':'test-poll-secret'}:
            self.reply(200, {'state':'complete', 'access_token':'test-access-token',
                            'token_type':'Bearer', 'expires_in':3600})
        else:
            self.reply(400, {'error':'OAuth request does not match the Warp SQL contract'})

ThreadingHTTPServer(('127.0.0.1',31338), Handler).serve_forever()
