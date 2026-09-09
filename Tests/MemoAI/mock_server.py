"""Loopback-only Chat Completions fixture; no real credentials or user data."""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    requests = 0

    def do_GET(self):
        payload = json.dumps(Handler.requests).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass

    def do_POST(self):
        Handler.requests += 1
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.headers['Authorization'] == 'Bearer test-only'
        assert body['model'] == 'test-model'
        assert body['messages'][0]['role'] == 'system'
        assert '时区' in body['messages'][0]['content']
        text = body['messages'][1]['content']
        if text == 'slow':
            time.sleep(0.7)
        if text == 'unauthorized':
            self.send_response(401)
            self.end_headers()
            return
        if text == 'redirect':
            self.send_response(302)
            self.send_header('Location', '/unexpected')
            self.end_headers()
            return
        result = dict(title='整理并发送首页设计稿', due_at=None,
                      time_evidence=None, needs_review=False, review_reason=None)
        if '2030' in text:
            result.update(due_at='2030-09-10T15:00:00+08:00', time_evidence='2030年9月10日15点')
        if text == '尽快交付':
            result.update(needs_review=True, review_reason='尽快没有明确时间，请确认。')
        content = 'invalid JSON' if text == 'malformed' else json.dumps(result, ensure_ascii=False)
        payload = json.dumps({'choices': [{'message': {'content': content}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
        except BrokenPipeError:
            pass


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(sys.argv[1], 'w') as file:
    file.write(str(server.server_port))
server.serve_forever()
