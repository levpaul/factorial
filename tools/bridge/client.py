"""Anthropic API client wrapper for the Factorial AI Advisor bridge."""

from __future__ import annotations

import os
import sys

import anthropic

from bridge.prompt import SYSTEM_PROMPT, build_user_message

DEFAULT_MODEL = "claude-sonnet-4-20250514"
DEFAULT_MAX_TOKENS = 2048


def get_api_key() -> str:
    """Read the Anthropic API key from the environment."""
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key:
        print(
            "ERROR: ANTHROPIC_API_KEY environment variable is not set.\n"
            "Export it before running the bridge:\n"
            "  export ANTHROPIC_API_KEY='sk-ant-...'\n",
            file=sys.stderr,
        )
        sys.exit(1)
    return key


def ask_claude(
    snapshot: dict,
    local_report: dict,
    *,
    model: str = DEFAULT_MODEL,
    max_tokens: int = DEFAULT_MAX_TOKENS,
    prompt_mode: str = "curated",
) -> str:
    """Send the snapshot to Claude and return the raw text response.

    Raises ``anthropic.APIError`` (or subclasses) on transient failures so the
    caller can decide how to handle them.
    """
    client = anthropic.Anthropic(api_key=get_api_key())

    user_message = build_user_message(snapshot, local_report, mode=prompt_mode)

    response = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        temperature=0.3,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )

    # Extract the text from the first content block.
    for block in response.content:
        if block.type == "text":
            return block.text

    return ""
