#!/usr/bin/env python3
"""Minimal localhost UDP bridge for the Factorial AI Advisor mod.

This script does not call a model API yet. It exists to prove the round-trip:
Factorio -> localhost UDP -> bridge -> Factorio.

Replace build_response() with a real model call when you are ready.
"""

from __future__ import annotations

import argparse
import json
import socket
from pathlib import Path
from typing import Any


def build_response(request_payload: dict[str, Any]) -> dict[str, Any]:
    snapshot = request_payload.get("snapshot", {})
    local_report = request_payload.get("local_report", {})
    stage = snapshot.get("stage", {}).get("label", "unknown stage")
    summary = local_report.get("summary", "No local summary was provided.")

    return {
        "source": "udp-bridge-example",
        "title": "External Advisor",
        "summary": f"Received a snapshot for {stage}. Replace the bridge logic with a real model call.",
        "sections": [
            {
                "title": "Bridge Status",
                "items": [
                    "The UDP round-trip is working.",
                    "The latest request was saved locally for inspection.",
                ],
            },
            {
                "title": "Local Summary",
                "items": [summary],
            },
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Listen for Factorial AI Advisor UDP payloads.")
    parser.add_argument("--port", type=int, default=34198, help="UDP port to listen on.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("tmp/latest_request.json"),
        help="Where to write the latest incoming request JSON.",
    )
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", args.port))

    print(f"Listening on udp://127.0.0.1:{args.port}")

    while True:
        data, address = sock.recvfrom(1024 * 1024)
        try:
            payload = json.loads(data.decode("utf-8"))
        except json.JSONDecodeError:
            payload = {"raw": data.decode("utf-8", errors="replace")}

        args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        response = build_response(payload if isinstance(payload, dict) else {"payload": payload})
        sock.sendto(json.dumps(response).encode("utf-8"), address)
        print(f"Processed request from {address[0]}:{address[1]}")


if __name__ == "__main__":
    main()
