"""Entry point for the Factorial AI Advisor UDP bridge.

Usage:
    cd tools/
    python -m bridge                           # curated mode, default port, logging enabled
    python -m bridge --prompt-mode full         # send full raw JSON to Claude
    python -m bridge --model claude-sonnet-4-20250514  # pick a specific model
    python -m bridge --no-log                   # disable request/response logging
    python -m bridge --log-dir /path/to/logs    # custom log directory
    python -m bridge --lmstudio-model my-model  # override LM Studio model name

The bridge routes requests to the correct backend based on the "backend" field
in the incoming JSON payload:
  - "anthropic" (default) -> Anthropic Claude API
  - "lmstudio"            -> Local LM Studio (OpenAI-compatible) API

It also handles detail requests (kind="factorial-advisor-detail-request") which
ask the LLM to elaborate on a specific recommendation item.
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

from bridge.client import DEFAULT_LMSTUDIO_URL, DEFAULT_MODEL, ask_claude, ask_lmstudio
from bridge.prompt import DETAIL_SYSTEM_PROMPT, build_detail_user_message
from bridge.response import (
    make_detail_error_response,
    make_error_response,
    parse_detail_response,
    parse_response,
)

# Maximum UDP datagram we'll accept (64 KiB).
MAX_DATAGRAM = 65535

# Default log directory (relative to tools/)
DEFAULT_LOG_DIR = Path("logs")

# How long to wait for remaining chunks before giving up (seconds).
CHUNK_REASSEMBLY_TIMEOUT = 5.0


class ChunkAssembler:
    """Reassembles chunked UDP messages from Factorio.

    Protocol:
    - Small messages (<= 7KB) arrive as plain JSON — no chunking.
    - Large messages are split into chunks, each a JSON object:
      {"_chunked": true, "_msg_id": "...", "_part": N, "_total": N, "_data": "..."}
    - The ``_data`` field contains a fragment of the original JSON string.
    - Chunks may arrive out of order. Once all parts are received,
      the fragments are concatenated and parsed as the full payload.
    """

    def __init__(self) -> None:
        self._pending: dict[str, dict[str, Any]] = {}
        # { msg_id: { "parts": {part_num: data_str}, "total": int, "first_seen": float, "address": tuple } }

    def receive(self, raw_json: dict[str, Any], address: tuple) -> dict[str, Any] | None:
        """Process a received JSON object.

        Returns the fully reassembled payload dict if the message is
        complete, or None if we're still waiting for more chunks.
        """
        if not raw_json.get("_chunked"):
            # Not a chunked message — return as-is.
            return raw_json

        msg_id = raw_json["_msg_id"]
        part = raw_json["_part"]
        total = raw_json["_total"]
        data = raw_json["_data"]

        if msg_id not in self._pending:
            self._pending[msg_id] = {
                "parts": {},
                "total": total,
                "first_seen": time.monotonic(),
                "address": address,
            }

        self._pending[msg_id]["parts"][part] = data

        received = len(self._pending[msg_id]["parts"])
        print(f"  Chunk {part}/{total} for message {msg_id} ({received}/{total} received)")

        if received >= total:
            # All chunks received — reassemble.
            entry = self._pending.pop(msg_id)
            fragments = [entry["parts"][i] for i in sorted(entry["parts"])]
            full_json_str = "".join(fragments)
            try:
                return json.loads(full_json_str)
            except json.JSONDecodeError as exc:
                print(f"  ERROR: Failed to parse reassembled message: {exc}", file=sys.stderr)
                return None

        return None

    def expire_stale(self) -> None:
        """Remove any pending messages that have timed out."""
        now = time.monotonic()
        expired = [
            msg_id
            for msg_id, entry in self._pending.items()
            if now - entry["first_seen"] > CHUNK_REASSEMBLY_TIMEOUT
        ]
        for msg_id in expired:
            entry = self._pending.pop(msg_id)
            received = len(entry["parts"])
            total = entry["total"]
            print(
                f"  WARNING: Message {msg_id} timed out ({received}/{total} chunks received)",
                file=sys.stderr,
            )


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


def _call_backend(
    backend: str,
    snapshot: dict,
    local_report: dict,
    *,
    model: str,
    lmstudio_model: str,
    lmstudio_url: str,
    prompt_mode: str,
    system_prompt: str | None = None,
    user_message: str | None = None,
) -> tuple[str, str]:
    """Call the appropriate backend and return (raw_text, source).

    If *system_prompt* and *user_message* are provided, they override the
    defaults. This is used for detail requests.
    """
    if backend == "lmstudio":
        raw_text = ask_lmstudio(
            snapshot,
            local_report,
            base_url=lmstudio_url,
            model=lmstudio_model,
            prompt_mode=prompt_mode,
            system_prompt=system_prompt,
            user_message=user_message,
        )
        return raw_text, "lmstudio"
    else:
        raw_text = ask_claude(
            snapshot,
            local_report,
            model=model,
            prompt_mode=prompt_mode,
            system_prompt=system_prompt,
            user_message=user_message,
        )
        return raw_text, "claude"


def handle_detail_request(
    payload: dict[str, Any],
    *,
    model: str,
    prompt_mode: str,
    log_dir: Path | None,
    lmstudio_model: str,
) -> dict[str, Any]:
    """Process a detail ("get more info") request and return a detail response dict."""
    log_prefix = _generate_log_prefix() if log_dir else None
    backend = payload.get("backend", "anthropic")
    detail_key = payload.get("detail_key", "0_0")
    item_text = payload.get("item_text", "")
    section_title = payload.get("section_title", "")

    if log_dir and log_prefix:
        _save_log(log_dir, log_prefix, "detail_request", payload)

    if not item_text:
        response = make_detail_error_response("No item text provided.", detail_key)
        if log_dir and log_prefix:
            _save_log(log_dir, log_prefix, "detail_response", response)
        return response

    snapshot = payload.get("snapshot", {})
    local_report = payload.get("local_report", {})
    lmstudio_url = payload.get("lmstudio_url", DEFAULT_LMSTUDIO_URL)

    # Build the detail-specific prompt
    detail_user_message = build_detail_user_message(
        item_text, section_title, snapshot, local_report, mode=prompt_mode,
    )

    print(f"  Backend: {backend}")
    print(f"  Detail key: {detail_key}")
    print(f"  Item: {item_text[:80]}{'...' if len(item_text) > 80 else ''}")

    start = time.monotonic()
    try:
        raw_text, source = _call_backend(
            backend,
            snapshot,
            local_report,
            model=model,
            lmstudio_model=lmstudio_model,
            lmstudio_url=lmstudio_url,
            prompt_mode=prompt_mode,
            system_prompt=DETAIL_SYSTEM_PROMPT,
            user_message=detail_user_message,
        )
    except Exception as exc:
        error_msg = f"{backend} API call failed: {exc}"
        print(f"  ERROR: {error_msg}", file=sys.stderr)
        response = make_detail_error_response(error_msg, detail_key, backend)
        if log_dir and log_prefix:
            _save_log(log_dir, log_prefix, "detail_response", response)
        return response

    elapsed = time.monotonic() - start
    source_name = "lmstudio" if backend == "lmstudio" else "claude"
    response = parse_detail_response(raw_text, detail_key, source_name)

    if log_dir and log_prefix:
        _save_log(log_dir, log_prefix, "detail_response", {
            **response,
            "_meta": {
                "backend": backend,
                "model": model if backend == "anthropic" else lmstudio_model,
                "prompt_mode": prompt_mode,
                "elapsed_seconds": round(elapsed, 2),
                "raw_text_length": len(raw_text),
            }
        })

    return response


def handle_request(
    payload: dict[str, Any],
    *,
    model: str,
    prompt_mode: str,
    log_dir: Path | None,
    lmstudio_model: str,
) -> dict[str, Any]:
    """Process a single advisor request and return a response dict.

    Routes based on the ``kind`` field:
      - ``"factorial-advisor-detail-request"`` -> detail elaboration
      - ``"factorial-advisor-request"`` (or missing) -> full analysis

    And the ``backend`` field:
      - ``"anthropic"`` (default) -> Anthropic Claude API
      - ``"lmstudio"`` -> Local LM Studio (OpenAI-compatible) API
    """
    kind = payload.get("kind", "factorial-advisor-request")

    # Route detail requests to the dedicated handler
    if kind == "factorial-advisor-detail-request":
        return handle_detail_request(
            payload,
            model=model,
            prompt_mode=prompt_mode,
            log_dir=log_dir,
            lmstudio_model=lmstudio_model,
        )

    # Standard full analysis request
    log_prefix = _generate_log_prefix() if log_dir else None
    backend = payload.get("backend", "anthropic")

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

    lmstudio_url = payload.get("lmstudio_url", DEFAULT_LMSTUDIO_URL)

    print(f"  Backend: {backend}")
    if backend == "lmstudio":
        print(f"  LM Studio URL: {lmstudio_url}")
        if lmstudio_model:
            print(f"  LM Studio model: {lmstudio_model}")

    start = time.monotonic()
    try:
        raw_text, source = _call_backend(
            backend,
            snapshot,
            local_report,
            model=model,
            lmstudio_model=lmstudio_model,
            lmstudio_url=lmstudio_url,
            prompt_mode=prompt_mode,
        )
    except Exception as exc:
        error_msg = f"{backend} API call failed: {exc}"
        print(f"  ERROR: {error_msg}", file=sys.stderr)
        response = make_error_response(error_msg)
        if log_dir and log_prefix:
            _save_log(log_dir, log_prefix, "response", {
                **response,
                "_meta": {
                    "error": True,
                    "backend": backend,
                    "model": model if backend == "anthropic" else lmstudio_model,
                    "prompt_mode": prompt_mode,
                }
            })
        return response

    elapsed = time.monotonic() - start
    response = parse_response(raw_text)

    # Override the source to reflect which backend was used
    response["source"] = source

    # Save response with metadata
    if log_dir and log_prefix:
        _save_log(log_dir, log_prefix, "response", {
            **response,
            "_meta": {
                "backend": backend,
                "model": model if backend == "anthropic" else lmstudio_model,
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
    lmstudio_model: str,
) -> None:
    """Run the UDP server loop forever."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", port))
    print(f"Factorial AI Advisor bridge listening on udp://127.0.0.1:{port}")
    print(f"  Anthropic model: {model}")
    print(f"  LM Studio model: {lmstudio_model or '(use loaded model)'}")
    print(f"  Prompt mode: {prompt_mode}")
    print(f"  Chunked message reassembly: enabled (timeout {CHUNK_REASSEMBLY_TIMEOUT}s)")
    if log_dir:
        print(f"  Logging to: {log_dir.resolve()}")
    else:
        print("  Logging: disabled")
    print()

    assembler = ChunkAssembler()

    while True:
        data, address = sock.recvfrom(MAX_DATAGRAM)

        # Parse incoming JSON.
        try:
            raw_json = json.loads(data.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            print(f"  Bad payload from {address}: {exc}", file=sys.stderr)
            response = make_error_response(f"Could not decode request: {exc}")
            sock.sendto(json.dumps(response).encode("utf-8"), address)
            continue

        if not isinstance(raw_json, dict):
            response = make_error_response("Request payload is not a JSON object.")
            sock.sendto(json.dumps(response).encode("utf-8"), address)
            continue

        # Handle chunked reassembly.
        payload = assembler.receive(raw_json, address)
        assembler.expire_stale()

        if payload is None:
            # Still waiting for more chunks.
            continue

        addr_str = f"{address[0]}:{address[1]}"
        kind = payload.get("kind", "factorial-advisor-request")
        backend = payload.get("backend", "anthropic")
        print(f"[{datetime.now(tz=timezone.utc).isoformat()}] {kind} from {addr_str} (backend={backend})")

        start = time.monotonic()
        response = handle_request(
            payload,
            model=model,
            prompt_mode=prompt_mode,
            log_dir=log_dir,
            lmstudio_model=lmstudio_model,
        )
        elapsed = time.monotonic() - start
        print(f"  Responded in {elapsed:.1f}s")

        sock.sendto(json.dumps(response).encode("utf-8"), address)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Factorial AI Advisor — UDP bridge supporting Anthropic Claude and local LM Studio backends.",
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
        "--lmstudio-model",
        type=str,
        default="",
        help="LM Studio model name to request. If empty, uses whichever model is loaded in LM Studio.",
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
            lmstudio_model=args.lmstudio_model,
        )
    except KeyboardInterrupt:
        print("\nShutting down.")
        sys.exit(0)


if __name__ == "__main__":
    main()
