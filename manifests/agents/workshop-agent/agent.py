#!/usr/bin/env python3
"""Minimal A2A agent for the RHOAI workshop.

Exposes an Agent Card and JSON-RPC message/send. If MAAS_URL + API_KEY are set,
it forwards the user text to MaaS; otherwise it echoes a canned FAQ.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8080"))
MAAS_URL = os.environ.get("MAAS_URL", "").rstrip("/")
API_KEY = os.environ.get("MAAS_API_KEY", "")
MODEL_ID = os.environ.get("MODEL_ID", "publishers/llm/models/qwen3-06b")
PUBLIC_URL = os.environ.get(
    "AGENT_ENDPOINT",
    os.environ.get("PUBLIC_URL", f"http://0.0.0.0:{PORT}/"),
)

CARD = {
    "name": "workshop-faq",
    "description": "Workshop FAQ agent. Answers with MaaS Qwen when configured.",
    "url": PUBLIC_URL if PUBLIC_URL.endswith("/") else PUBLIC_URL + "/",
    "version": "0.1.0",
    "protocolVersion": "0.2.1",
    "capabilities": {"streaming": False},
    "defaultInputModes": ["text"],
    "defaultOutputModes": ["text"],
    "skills": [
        {
            "id": "faq",
            "name": "Workshop FAQ",
            "description": "OpenShift AI / MaaS workshop questions",
            "tags": ["workshop", "rhoai", "maas"],
        }
    ],
}

FALLBACK = (
    "Fake GPU is not CUDA. Qwen3-0.6B is served on CPU via llm-d and published in MaaS. "
    "Use /no_think and max_tokens <= 1024 in Playground."
)


def _complete(prompt: str) -> str:
    if not MAAS_URL or not API_KEY:
        return FALLBACK
    payload = {
        "model": MODEL_ID,
        "messages": [
            {
                "role": "system",
                "content": "You are a concise OpenShift AI workshop assistant. /no_think",
            },
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 128,
    }
    req = urllib.request.Request(
        f"{MAAS_URL}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        return data["choices"][0]["message"]["content"]
    except (urllib.error.URLError, KeyError, IndexError, json.JSONDecodeError) as exc:
        return f"{FALLBACK} (MaaS fallback: {exc})"


def _user_text(body: dict) -> str:
    params = body.get("params") or body
    message = params.get("message") or {}
    parts = message.get("parts") or []
    for part in parts:
        if part.get("kind") == "text" or "text" in part:
            return part.get("text") or ""
    if isinstance(params.get("input"), str):
        return params["input"]
    return json.dumps(body)[:500]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"agent: {fmt % args}")

    def _send(self, code: int, payload: dict) -> None:
        raw = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in (
            "/.well-known/agent.json",
            "/.well-known/agent-card.json",
            "/agent-card",
            "/.well-known/agent-card",
        ):
            self._send(200, CARD)
            return
        if path in ("/health", "/healthz", "/"):
            self._send(200, {"status": "ok", "name": CARD["name"]})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid json"})
            return
        text = _user_text(body)
        answer = _complete(text)
        rpc_id = body.get("id", 1)
        self._send(
            200,
            {
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "role": "agent",
                    "parts": [{"kind": "text", "text": answer}],
                },
            },
        )


if __name__ == "__main__":
    print(f"workshop-faq listening on 0.0.0.0:{PORT}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
