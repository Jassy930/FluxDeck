#!/usr/bin/env python3
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class MockOpenAIHandler(BaseHTTPRequestHandler):
    def _json_response(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self._json_response(404, {"error": {"message": "not found"}})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        data = json.loads(raw.decode("utf-8"))
        model = data.get("model", "unknown")
        content = "passthrough-ok" if data.get("x_passthrough") is not None else "pong"

        self._json_response(
            200,
            {
                "id": "chatcmpl_mock_001",
                "object": "chat.completion",
                "model": model,
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": content},
                        "finish_reason": "stop",
                    }
                ],
            },
        )

    def log_message(self, fmt: str, *args) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    server = HTTPServer((args.host, args.port), MockOpenAIHandler)
    print(f"mock_openai listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
