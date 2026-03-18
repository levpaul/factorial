"""Entry point for the Factorial AI Advisor UDP bridge.

Usage:
    cd tools/
    python -m bridge                           # curated mode, default port, logging enabled
    python -m bridge --prompt-mode full         # send full raw JSON to Claude
    python -m bridge --model claude-sonnet-4-20250514  # pick a specific model
    python -m bridge --no-log                   # disable request/response logging
    python -m bridge --log-dir /path/to/logs    # custom log directory
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from bridge.client import DEFAULT_MODEL, ask_claude
from bridge.response import make_error_response, parse_response

# Maximum UDP datagram we'll accept (1 MiB — same as the example bridge).
MAX_DATAGRAM = 1024 * 1024

# Default log directory (relative to tools/)
DEFAULT_LOG_DIR = Path("logs")


def _generate_log_prefix() -> str:
    """Generate a timestamp prefix for log files."""
    return datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")


def _save_log(
    directory: Path,
    prefix: str,
    suffix: str,
    data: dict[str, Any],
) -> Path:
    """Write a JSON log file and return the path."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{prefix}_{suffix}.json"
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


def handle_request(
    payload: dict[str, Any],
    *,
    model: str,
    prompt_mode: str,
    log_dir: Path | None,
) -> dict[str, Any]:
    """Process a single advisor request and return a response dict."""
    log_prefix = _generate_log_prefix() if log_dir else None

    # Save incoming request
    if log_dir and log_prefix:
        _save_log(log_dir, log_prefix, "request", payload)

    snapshot = payload.get("snapshot", {})
    local_report = payload.get("local_report", {})

    if not snapshot:
        response = make_error_response("The request did not contain a snapshot.")
        if log_dir and log_prefix:
            _save_log(log_dir, log_prefix, "response", response)
        return response

    start = time.monotonic()
    try:
        raw_text = ask_claude(
            snapshot,
            local_report,
            model=model,
            prompt_mode=prompt_mode,
        )
    except Exception as exc:
        error_msg = f"Anthropic API call failed: {exc}"
        print(f"  ERROR: {error_msg}", file=sys.stderr)
        response = make_error_response(error_msg)
        if log_dir and log_prefix:
            _save_log(log_dir, log_prefix, "response", {
                **response,
                "_meta": {
                    "error": True,
                    "model": model,
                    "prompt_mode": prompt_mode,
                }
            })
        return response

    elapsed = time.monotonic() - start
    response = parse_response(raw_text)

    # Save response with metadata
    if log_dir and log_prefix:
        _save_log(log_dir, log_prefix, "response", {
            **response,
            "_meta": {
                "model": model,
                "prompt_mode": prompt_mode,
                "elapsed_seconds": round(elapsed, 2),
                "raw_text_length": len(raw_text),
            }
        })

    return response


def serve(
    port: int,
    model: str,
    prompt_mode: str,
    log_dir: Path | None,
) -> None:
    """Run the UDP server loop forever."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", port))
    print(f"Factorial AI Advisor bridge listening on udp://127.0.0.1:{port}")
    print(f"  Model: {model}")
    print(f"  Prompt mode: {prompt_mode}")
    if log_dir:
        print(f"  Logging to: {log_dir.resolve()}")
    else:
        print("  Logging: disabled")
    print()

    while True:
        data, address = sock.recvfrom(MAX_DATAGRAM)
        addr_str = f"{address[0]}:{address[1]}"
        print(f"[{datetime.now(tz=timezone.utc).isoformat()}] Request from {addr_str}")

        # Parse incoming JSON.
        try:
            payload = json.loads(data.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"  Bad payload: {exc}", file=sys.stderr)
            response = make_error_response(f"Could not decode request: {exc}")
            sock.sendto(json.dumps(response).encode("utf-8"), address)
            continue

        if not isinstance(payload, dict):
            response = make_error_response("Request payload is not a JSON object.")
            sock.sendto(json.dumps(response).encode("utf-8"), address)
            continue

        start = time.monotonic()
        response = handle_request(
            payload,
            model=model,
            prompt_mode=prompt_mode,
            log_dir=log_dir,
        )
        elapsed = time.monotonic() - start
        print(f"  Responded in {elapsed:.1f}s")

        sock.sendto(json.dumps(response).encode("utf-8"), address)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Factorial AI Advisor — Anthropic Claude UDP bridge.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=34198,
        help="UDP port to listen on (default: 34198).",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=DEFAULT_MODEL,
        help=f"Anthropic model to use (default: {DEFAULT_MODEL}).",
    )
    parser.add_argument(
        "--prompt-mode",
        choices=["curated", "full"],
        default="curated",
        help="How to format the snapshot for the model (default: curated).",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=DEFAULT_LOG_DIR,
        help=f"Directory for request/response logs (default: {DEFAULT_LOG_DIR}).",
    )
    parser.add_argument(
        "--no-log",
        action="store_true",
        default=False,
        help="Disable request/response logging.",
    )
    args = parser.parse_args()

    log_dir = None if args.no_log else args.log_dir

    try:
        serve(
            port=args.port,
            model=args.model,
            prompt_mode=args.prompt_mode,
            log_dir=log_dir,
        )
    except KeyboardInterrupt:
        print("\nShutting down.")
        sys.exit(0)


if __name__ == "__main__":
    main()
