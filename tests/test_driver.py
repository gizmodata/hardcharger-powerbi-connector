"""Native transport/authentication and the inherited SQL dialect smoke script.

Replaces the legacy ODBC SQLTables diagnostic with ADBC catalog discovery.
Run against the fixture server started by scripts/Test-Connector.ps1.
"""
import os
from pathlib import Path
import unittest
import urllib.request
import json
from adbc_driver_manager import dbapi

DRIVER = str(Path('installer/bin/libadbc_driver_hardcharger.dll').resolve())
URI = 'hardcharger://localhost:31337?tls=false'

def connect(**options):
    return dbapi.connect(driver=DRIVER, entrypoint='AdbcDriverHardchargerInit',
                         db_kwargs={'uri': URI, **options})

class NativeDriverTests(unittest.TestCase):
    def test_password_catalogs_and_sql_dialect(self):
        with connect(username='hardcharger_user', password=os.environ['HARDCHARGER_ADMIN_PASSWORD']) as cx:
            catalogs = cx.adbc_get_objects(depth='catalogs').read_all().to_pylist()
            self.assertTrue({'memory', 'other'} <= {c['catalog_name'] for c in catalogs})
            with cx.cursor() as cur:
                sql = '\n'.join(line.split('--')[0] for line in Path('tests/duckdb-folding.sql').read_text().splitlines())
                # The inherited script creates a temporary fixture then evaluates
                # one UNION query. Run both on this actual Hardcharger session.
                for statement in sql.split(';'):
                    if statement.strip():
                        cur.execute(statement)
                        if cur.description:
                            rows = cur.fetchall()
                            self.assertGreater(len(rows), 20)
                            self.assertEqual(dict(rows)['PosOf_found'], '6')

    def test_oauth_http_contract(self):
        requests = [json.loads(line) for line in Path('test-results/oauth-requests.jsonl').read_text().splitlines()]
        self.assertTrue(any(r['path'] == '/warp/v1/auth/oauth/flows' and r['body'] == {'return_to':'/?powerbi_signin_complete=1'} for r in requests))
        self.assertTrue(any(r['path'] == '/warp/v1/auth/oauth/flows/test-flow' and r['body'] == {'poll_secret':'test-poll-secret'} for r in requests))

    def test_bearer_token(self):
        body = json.dumps({'grant_type':'password', 'username':'hardcharger_user',
                           'password':os.environ['HARDCHARGER_ADMIN_PASSWORD']}).encode()
        request = urllib.request.Request('http://localhost:31337/warp/v1/auth/token', data=body,
                                         headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request) as response:
            token = json.load(response)['access_token']
        with connect(**{'adbc.warp.auth.access_token':token}) as cx, cx.cursor() as cur:
            cur.execute('SELECT 42')
            self.assertEqual(cur.fetchone(), (42,))

    def test_invalid_password_rejected(self):
        with self.assertRaises(Exception):
            connect(username='hardcharger_user', password='incorrect')

    def test_tls_never_silently_downgrades(self):
        with self.assertRaises(Exception):
            dbapi.connect(driver=DRIVER, entrypoint='AdbcDriverHardchargerInit',
                          db_kwargs={'uri':'hardcharger://localhost:31337',
                                     'username':'hardcharger_user', 'password':os.environ['HARDCHARGER_ADMIN_PASSWORD']})

if __name__ == '__main__':
    unittest.main(verbosity=2)
