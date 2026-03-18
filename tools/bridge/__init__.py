"""Factorial AI Advisor — external bridge package.

Receives game snapshots from the Factorio mod over UDP, sends them to the
Anthropic Claude API for analysis, and returns structured advice back to the
game.

Usage:
    python -m bridge --port 34198 --prompt-mode curated
"""
