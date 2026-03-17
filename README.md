# Factorial AI Advisor

This repository now contains a playable starter Factorio 2.0 mod that adds an in-game advisor. The advisor reads a slice of the current game state, applies a rule-based analysis, and surfaces five kinds of guidance:

1. What to focus on next to reach a rocket launch.
2. Which resource bottleneck is most likely holding the base back.
3. New layout and control patterns worth applying.
4. Upcoming issues such as ore depletion, oil pressure, brownouts, or biter risk.
5. Serious anti-patterns that make the base feel overly manual or fragile.

## What the mod does today

- Adds a hotkey: `Control + Shift + A`
- Adds chat commands:
  - `/advisor`
  - `/advisor-refresh`
  - `/advisor-export`
  - `/advisor-send`
- Builds a runtime snapshot from:
  - researched technologies
  - entity counts for core factory structures
  - one-minute production and consumption rates
  - current-surface resource totals
  - pollution and enemy evolution
- Renders the advice in a simple in-game GUI
- Exports snapshots and local reports to `script-output/factorial/player-<n>/...`
- Optionally sends snapshot JSON to a localhost UDP bridge

## Why the architecture is split

The mod itself is best at deterministic inspection:

- What entities exist
- What tech is researched
- Which resources are flowing
- How much pollution and evolution are building

That makes a rule engine a strong first layer. It is fast, always available, and gives trustworthy, inspectable advice even with no external service.

For the richer "AI companion" layer, the best pattern is:

1. The mod exports a compact structured snapshot.
2. A local bridge process turns that snapshot into a prompt.
3. A model returns a higher-level narrative or strategy review.
4. The bridge sends the response back to the mod over localhost UDP.

That keeps the game-facing code simple and deterministic while still letting you swap in a better agent later.

## Files

- [control.lua](/Users/levilovelock/repos/factorial/control.lua)
- [scripts/advisor.lua](/Users/levilovelock/repos/factorial/scripts/advisor.lua)
- [scripts/external.lua](/Users/levilovelock/repos/factorial/scripts/external.lua)
- [scripts/gui.lua](/Users/levilovelock/repos/factorial/scripts/gui.lua)
- [docs/architecture.md](/Users/levilovelock/repos/factorial/docs/architecture.md)
- [tools/udp_bridge_example.py](/Users/levilovelock/repos/factorial/tools/udp_bridge_example.py)

## Usage

Copy or symlink this repository into your Factorio mods folder so the folder name stays `factorial`, then launch the game and open a save.

Open the advisor with:

```text
Control + Shift + A
```

Or:

```text
/advisor
```

To export a request payload:

```text
/advisor-export
```

To test the optional localhost bridge:

1. Start Factorio with `--enable-lua-udp`
2. Turn on the runtime setting `factorial-enable-udp-bridge`
3. Run the example bridge in this repo
4. Use `/advisor-send` or the `Ask External` button

## Notes on accuracy

The current advisor is intentionally heuristic-heavy. It does not inspect exact belt layouts, inserter wiring, or local defensive geometry yet. Instead it works from robust signals that are cheap to read every time:

- counts
- tech gates
- resource totals
- rate deltas
- environmental pressure

That makes it a good base layer, and a good source payload for a later model-based reviewer.
