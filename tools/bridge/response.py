"""Parse Claude's response text into the JSON format expected by the Factorio mod.

The mod's ``external.receive_response`` in ``scripts/external.lua`` expects:

    {
        "source": "...",
        "title": "External Advisor",
        "summary": "One sentence overview.",
        "sections": [
            {"title": "Section Title", "items": ["[High] ...", "[Medium] ..."]}
        ]
    }
"""

from __future__ import annotations

import json
import re
from typing import Any

# Regex to extract a JSON object from markdown-fenced code blocks or bare JSON.
_JSON_BLOCK_RE = re.compile(
    r"```(?:json)?\s*\n?(.*?)\n?\s*```"  # fenced block
    r"|"
    r"(\{.*\})",                           # bare JSON (greedy, outermost braces)
    re.DOTALL,
)


def _extract_json_text(raw: str) -> str | None:
    """Try to pull a JSON object string out of *raw*.

    Handles:
    - Pure JSON (starts with ``{``)
    - JSON inside ```json ... ``` fences
    - JSON preceded/followed by stray commentary
    """
    stripped = raw.strip()

    # Fast path: raw text is already a JSON object.
    if stripped.startswith("{"):
        return stripped

    match = _JSON_BLOCK_RE.search(raw)
    if match:
        return (match.group(1) or match.group(2) or "").strip()

    return None


def _validate_sections(sections: Any) -> list[dict[str, Any]]:
    """Ensure *sections* is a list of ``{title, items}`` dicts."""
    if not isinstance(sections, list):
        return []

    valid: list[dict[str, Any]] = []
    for entry in sections:
        if not isinstance(entry, dict):
            continue
        title = str(entry.get("title", "Advice"))
        items = entry.get("items", [])
        if isinstance(items, str):
            items = [items]
        elif not isinstance(items, list):
            items = [str(items)]
        else:
            items = [str(i) for i in items]
        valid.append({"title": title, "items": items})

    return valid


def parse_response(raw_text: str) -> dict[str, Any]:
    """Parse Claude's raw text into the mod-compatible response dict.

    Always returns a well-formed dict — even if parsing fails it wraps the raw
    text as a single section so the player still sees something.
    """
    json_text = _extract_json_text(raw_text)

    if json_text:
        try:
            data = json.loads(json_text)
            if isinstance(data, dict):
                sections = _validate_sections(data.get("sections"))
                if sections:
                    return {
                        "source": "claude",
                        "title": str(data.get("title", "External Advisor")),
                        "summary": str(data.get("summary", "Analysis complete.")),
                        "sections": sections,
                    }
        except json.JSONDecodeError:
            pass

    # Fallback: return the entire response as a single section.
    return {
        "source": "claude",
        "title": "External Advisor",
        "summary": "Received a response but could not parse structured JSON.",
        "sections": [
            {
                "title": "Raw Response",
                "items": [raw_text[:2000] if len(raw_text) > 2000 else raw_text],
            }
        ],
    }


def make_error_response(error_message: str) -> dict[str, Any]:
    """Build a valid response dict that communicates an error to the player."""
    return {
        "source": "claude-bridge",
        "title": "External Advisor",
        "summary": "The external advisor encountered an error.",
        "sections": [
            {
                "title": "Error",
                "items": [f"[High] {error_message}"],
            }
        ],
    }
