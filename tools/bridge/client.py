"""API client wrappers for the Factorial AI Advisor bridge.

Supports two backends:
  - Anthropic (Claude) via the anthropic Python package
  - LM Studio (or any OpenAI-compatible server) via the openai Python package
"""

from __future__ import annotations

import os
import sys

import anthropic
import openai

from bridge.prompt import SYSTEM_PROMPT, build_user_message

DEFAULT_MODEL = "claude-sonnet-4-20250514"
DEFAULT_MAX_TOKENS = 2048

DEFAULT_LMSTUDIO_URL = "http://192.168.1.53:1234"
# LM Studio doesn't require a real API key, but the openai client needs one.
LMSTUDIO_API_KEY = "lm-studio"


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


def ask_lmstudio(
    snapshot: dict,
    local_report: dict,
    *,
    base_url: str = DEFAULT_LMSTUDIO_URL,
    model: str = "",
    max_tokens: int = DEFAULT_MAX_TOKENS,
    prompt_mode: str = "curated",
) -> str:
    """Send the snapshot to a local LM Studio server and return the raw text response.

    Uses the OpenAI-compatible chat completions API that LM Studio exposes.
    If *model* is empty, LM Studio will use whichever model is currently loaded.

    Raises ``openai.APIError`` (or subclasses) on transient failures so the
    caller can decide how to handle them.
    """
    # Ensure the base URL ends with /v1 for the openai client
    api_base = base_url.rstrip("/")
    if not api_base.endswith("/v1"):
        api_base += "/v1"

    client = openai.OpenAI(
        base_url=api_base,
        api_key=LMSTUDIO_API_KEY,
    )

    user_message = build_user_message(snapshot, local_report, mode=prompt_mode)

    # Build kwargs — omit model if empty so LM Studio uses its loaded model
    kwargs: dict = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ],
        "max_tokens": max_tokens,
        "temperature": 0.3,
    }
    if model:
        kwargs["model"] = model
    else:
        # The openai client requires a model string; use a placeholder that
        # LM Studio will ignore in favour of the currently loaded model.
        kwargs["model"] = "local-model"

    response = client.chat.completions.create(**kwargs)

    # Extract the text from the first choice.
    if response.choices:
        message = response.choices[0].message
        if message and message.content:
            return message.content

    return ""
