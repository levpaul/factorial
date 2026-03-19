"""System prompt and snapshot formatting for the Factorial AI Advisor bridge."""

from __future__ import annotations

import json
from typing import Any

SYSTEM_PROMPT = """\
You are an expert Factorio advisor embedded in a mod called "Factorial AI Advisor".
The player has clicked "Ask External" inside the game, which sent you a snapshot of
their current factory state along with a rule-based local report.

Your job is to analyze the snapshot and provide strategic advice across five
categories. You have deep knowledge of Factorio mechanics, progression, ratios,
and common pitfalls — including the Space Age expansion with multiple planets.

## Key Factorio knowledge to apply

### Base game mechanics
- A rocket launch requires: rocket silo, 100 low-density structures, 100 rocket
  fuel, 100 rocket control units, plus a satellite.
- Core ratios: 1 offshore pump feeds 20 boilers feeds 40 steam engines.
  48 electric furnaces smelt a full yellow belt. 1 pumpjack per ~2 refineries.
- Red science: 1 gear assembler + 1 red science assembler per 0.83/s.
- Green science: 1 inserter + 1 belt assembler per green science assembler.
- Steel: 5 iron plates per steel plate, so steel furnaces need 5x the iron input.
- Oil: basic processing gives heavy, light, petroleum. Advanced cracking lets you
  convert heavy->light->petroleum. Circuit-controlled cracking prevents deadlocks.
- Common progression: red -> green -> military -> blue (oil) -> purple -> yellow -> rocket.
- Biters scale with evolution (time, pollution, nest destruction). Pollution cloud
  size matters more than total pollution for attack frequency.
- Belt throughput: yellow 15/s, red 30/s, blue 45/s.
- Smelting columns: stone furnace ~0.625/s, steel furnace ~1.25/s, electric ~1.25/s
  (but takes modules).
- Train logistics become important once starter ore patches start running low
  (typically midgame, ~100k ore remaining).

### Space Age expansion — Multi-planet gameplay
The snapshot may contain data from multiple planets. Each planet has unique
resources, challenges, and production chains:

- **Nauvis** — The home planet. Standard Factorio gameplay with iron, copper, coal,
  stone, oil, uranium. Biters are the main threat. This is where most early/mid
  game infrastructure lives.

- **Vulcanus** — Volcanic/lava planet. Key resources: tungsten, calcite. Features
  foundries for advanced metallurgy. Lava is used for power and processing.
  Extreme heat environment. Important for late-game metal processing.

- **Fulgora** — Lightning/storm planet. Key mechanic: scrap recycling from ruins.
  Lightning rods harvest energy from storms. Electromagnetic science is produced
  here. Recyclers are critical infrastructure.

- **Gleba** — Organic/agricultural planet. Key resources: nutrients, bioflux,
  spoilage mechanics. Agriculture is the main production method. Items can spoil
  over time. Agricultural science is produced here. Pentapod enemies.

- **Aquilo** — Ice/frozen planet. Key resources: ammonia, lithium. Cryogenic
  processing and fusion power. Cryogenic science is produced here. Extreme cold
  requires heating.

- **Space platforms** — Mobile factories that travel between planets. Used for
  interplanetary logistics. Can have their own production chains. Asteroid
  processing for resources in transit.

### Multi-planet strategy
- Each planet requires its own power, logistics, and defense infrastructure.
- Interplanetary logistics via rockets and space platforms is expensive — minimize
  what needs to be shipped.
- Resource rates shown per-planet help identify which planet needs attention.
- A player on Gleba with low infrastructure there but high infrastructure on
  Nauvis is normal — they may be exploring or setting up a new outpost.
- When analyzing multi-planet bases, consider the TOTAL resources and production
  across all planets, not just the current surface.

## Analysis categories

Provide advice in exactly these five sections:

1. **Strategic Focus** — What should the player prioritize right now? Consider
   both single-planet progression and multi-planet expansion if applicable.
2. **Resource Bottlenecks** — Which resource constraints are most likely to stall
   the factory? Consider production vs consumption rates across ALL planets,
   remaining ore on each planet, oil throughput, and power capacity.
3. **Layout & Pattern Improvements** — What structural or design improvements
   would help? Think about bus organization, modular production blocks, train
   networks, circuit control, interplanetary logistics, and blueprint-friendly layouts.
4. **Predicted Upcoming Issues** — What problems are likely to emerge in the next
   stage of the game? Consider ore depletion, biter/enemy evolution, power scaling,
   oil balance, and interplanetary supply chain bottlenecks.
5. **Anti-Patterns & Warnings** — What is the player doing that will cause
   problems? Examples: hand-feeding, burner equipment past early game, spaghetti
   belts, no radar, no walls with high pollution, under-defended perimeter,
   neglecting a planet that needs attention.

## Severity tags

Prefix each item with a severity tag: `[High]` or `[Medium]`.
Use `[High]` for urgent or blocking issues. Use `[Medium]` for important but
non-critical improvements.

## Output format

You MUST respond with a single JSON object and nothing else — no markdown fences,
no commentary before or after. The JSON must match this exact structure:

{
  "title": "External Advisor",
  "summary": "A one-sentence overall assessment of the factory state.",
  "sections": [
    {
      "title": "Strategic Focus",
      "items": [
        "[High] First priority item.",
        "[Medium] Second priority item."
      ]
    },
    {
      "title": "Resource Bottlenecks",
      "items": ["[High] ...", "[Medium] ..."]
    },
    {
      "title": "Layout & Pattern Improvements",
      "items": ["[Medium] ...", "[Medium] ..."]
    },
    {
      "title": "Predicted Upcoming Issues",
      "items": ["[High] ...", "[Medium] ..."]
    },
    {
      "title": "Anti-Patterns & Warnings",
      "items": ["[High] ...", "[Medium] ..."]
    }
  ]
}

Each section must have 2-4 items. Be specific and actionable — reference actual
numbers from the snapshot (e.g. "iron production is 45/min but consumption is
72/min on Nauvis"). When multiple planets have data, mention which planet you're
referring to. Avoid generic advice that could apply to any factory.\
"""

DETAIL_SYSTEM_PROMPT = """\
You are an expert Factorio advisor. The player has received a set of
recommendations about their factory and is now asking for more detail on one
specific recommendation.

Provide a thorough justification and explanation for the recommendation. Include:
- Why this matters for their current factory state, referencing specific numbers
  from the snapshot
- The underlying Factorio mechanics or ratios that make this important
- Concrete, actionable steps the player should take to address this
- Any trade-offs or considerations to keep in mind

Write 2-4 paragraphs of plain text. Be specific and reference actual data from
the snapshot. Do not use JSON formatting — just write clear, helpful prose.\
"""


def _format_rate(rate: dict[str, float] | None) -> str:
    """Format a production/consumption rate pair."""
    if not rate:
        return "no data"
    prod = rate.get("production", 0)
    cons = rate.get("consumption", 0)
    return f"+{prod:.0f} / -{cons:.0f} per min"


def _format_number(value: float) -> str:
    """Format a large number with K/M suffixes for readability."""
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    elif value >= 1_000:
        return f"{value / 1_000:.1f}K"
    else:
        return f"{value:.0f}"


def _format_surface_data(
    surface_name: str,
    surface_data: dict[str, Any],
    is_current: bool = False,
) -> list[str]:
    """Format a single surface's data into lines."""
    lines = []
    current_marker = " (CURRENT LOCATION)" if is_current else ""
    lines.append(f"--- {surface_name.upper()}{current_marker} ---")

    # Resources
    resources = surface_data.get("resources", {})
    resource_parts = []
    for res_name in ["iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "crude-oil"]:
        amount = resources.get(res_name, 0)
        if amount > 0:
            resource_parts.append(f"{res_name}: {_format_number(amount)}")
    if resource_parts:
        lines.append(f"  Resources: {', '.join(resource_parts)}")
    else:
        lines.append("  Resources: none tracked")

    # Environment
    env = surface_data.get("environment", {})
    pollution = env.get("total_pollution", 0)
    evolution = env.get("enemy_evolution", 0)
    if pollution > 0 or evolution > 0:
        lines.append(f"  Environment: pollution {pollution:.0f}, evolution {evolution:.1%}")

    # Item rates (only show items with activity)
    item_rates = surface_data.get("rates", {}).get("items", {})
    active_items = []
    for item_name in [
        "iron-plate", "copper-plate", "steel-plate",
        "electronic-circuit", "advanced-circuit", "processing-unit",
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
    ]:
        rate = item_rates.get(item_name)
        if rate and (rate.get("production", 0) > 0 or rate.get("consumption", 0) > 0):
            active_items.append(f"{item_name}: {_format_rate(rate)}")

    if active_items:
        lines.append("  Item rates:")
        for item in active_items[:8]:  # Limit to avoid overwhelming
            lines.append(f"    {item}")

    # Fluid rates (only show fluids with activity)
    fluid_rates = surface_data.get("rates", {}).get("fluids", {})
    active_fluids = []
    for fluid_name in ["crude-oil", "petroleum-gas", "water", "steam"]:
        rate = fluid_rates.get(fluid_name)
        if rate and (rate.get("production", 0) > 0 or rate.get("consumption", 0) > 0):
            active_fluids.append(f"{fluid_name}: {_format_rate(rate)}")

    if active_fluids:
        lines.append("  Fluid rates:")
        for fluid in active_fluids:
            lines.append(f"    {fluid}")

    return lines


def format_curated(snapshot: dict[str, Any], local_report: dict[str, Any]) -> str:
    """Build a concise, human-readable summary of the snapshot for the model."""
    meta = snapshot.get("meta", {})
    stage = snapshot.get("stage", {})
    metrics = snapshot.get("metrics", {})
    techs = snapshot.get("technologies", {})
    force = snapshot.get("force", {})

    # Aggregated rates (across all surfaces)
    agg_item_rates = snapshot.get("rates", {}).get("items", {})
    agg_fluid_rates = snapshot.get("rates", {}).get("fluids", {})
    agg_resources = snapshot.get("resources", {})

    # Per-surface data
    surfaces_data = snapshot.get("surfaces", {})
    current_surface = meta.get("surface", "nauvis")
    surfaces_collected = meta.get("surfaces_collected", [current_surface])

    # Game time
    ticks = meta.get("tick", 0)
    total_seconds = ticks // 60
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60

    # Researched techs
    researched = sorted(t for t, v in techs.items() if v)
    not_researched = sorted(t for t, v in techs.items() if not v)

    lines = [
        "=== FACTORY SNAPSHOT ===",
        "",
        f"Game time: {hours}h {minutes:02d}m (tick {ticks})",
        f"Player currently on: {current_surface}",
        f"Surfaces with infrastructure: {', '.join(surfaces_collected)}",
        f"Stage: {stage.get('label', 'unknown')} — {stage.get('focus', '')}",
        f"Rockets launched: {force.get('rockets_launched', 0)}",
        f"Current research: {force.get('current_research', 'none')}",
        "",
        "=== FORCE-WIDE METRICS (all planets combined) ===",
        "",
        f"Mining drills: {metrics.get('mining_drills', 0)} ({metrics.get('burner_drills', 0)} burner, {metrics.get('electric_drills', 0)} electric)",
        f"Furnaces: {metrics.get('furnaces', 0)} ({metrics.get('stone_furnaces', 0)} stone, {metrics.get('modern_furnaces', 0)} steel/electric)",
        f"Assemblers: {metrics.get('assemblers', 0)}",
        f"Labs: {metrics.get('labs', 0)}",
        f"Belts: {metrics.get('belts', 0)} (undergrounds: {metrics.get('undergrounds', 0)}, splitters: {metrics.get('splitters', 0)})",
        f"Inserters: {metrics.get('inserters', 0)}",
        f"Oil chain: {metrics.get('oil_chain', 0)} (pumpjacks + refineries + chem plants)",
        f"Defense turrets: {metrics.get('defense_turrets', 0)}",
        f"Walls: {metrics.get('walls', 0)}",
        f"Roboports: {metrics.get('roboports', 0)}",
        f"Trains (loco+wagon+stop): {metrics.get('trains', 0)}",
        f"Radars: {metrics.get('radars', 0)}",
        f"Rocket silos: {metrics.get('rocket_silos', 0)}",
        f"Power: {metrics.get('steam_power', 0)} steam units, {metrics.get('solar_power', 0)} solar, {metrics.get('accumulators', 0)} accumulators",
        "",
        "=== AGGREGATED RESOURCES (all planets) ===",
    ]

    for res_name in ["iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "crude-oil"]:
        amount = agg_resources.get(res_name, 0)
        lines.append(f"  {res_name}: {_format_number(amount)}")

    lines.append("")
    lines.append("=== AGGREGATED PRODUCTION RATES (all planets, per minute) ===")

    for item_name in [
        "iron-plate", "copper-plate", "steel-plate", "stone-brick",
        "electronic-circuit", "advanced-circuit", "processing-unit",
        "plastic-bar", "low-density-structure", "rocket-fuel", "rocket-control-unit",
        "automation-science-pack", "logistic-science-pack", "military-science-pack",
        "chemical-science-pack", "production-science-pack", "utility-science-pack",
        "space-science-pack",
    ]:
        rate = agg_item_rates.get(item_name)
        if rate and (rate.get("production", 0) > 0 or rate.get("consumption", 0) > 0):
            lines.append(f"  {item_name}: {_format_rate(rate)}")

    lines.append("")
    lines.append("=== AGGREGATED FLUID RATES (all planets, per minute) ===")

    for fluid_name in ["water", "steam", "crude-oil", "heavy-oil", "light-oil",
                       "petroleum-gas", "lubricant", "sulfuric-acid"]:
        rate = agg_fluid_rates.get(fluid_name)
        if rate and (rate.get("production", 0) > 0 or rate.get("consumption", 0) > 0):
            lines.append(f"  {fluid_name}: {_format_rate(rate)}")

    # Per-surface breakdown
    if surfaces_data and len(surfaces_data) > 0:
        lines.append("")
        lines.append("=== PER-PLANET BREAKDOWN ===")
        lines.append("")

        # Show current surface first, then others
        surface_order = [current_surface] + [s for s in surfaces_collected if s != current_surface]

        for surface_name in surface_order:
            if surface_name in surfaces_data:
                surface_lines = _format_surface_data(
                    surface_name,
                    surfaces_data[surface_name],
                    is_current=(surface_name == current_surface),
                )
                lines.extend(surface_lines)
                lines.append("")

    lines.append("=== TECHNOLOGIES ===")
    lines.append(f"  Researched: {', '.join(researched) if researched else 'none'}")
    lines.append(f"  Not yet: {', '.join(not_researched) if not_researched else 'all tracked techs done'}")

    # Include local report summary for context
    if local_report:
        lines.append("")
        lines.append("=== LOCAL RULE-BASED REPORT SUMMARY ===")
        lines.append(f"  {local_report.get('summary', 'No summary.')}")
        for section in local_report.get("sections", []):
            lines.append(f"  [{section.get('title', '')}]")
            for item in section.get("items", [])[:2]:
                lines.append(f"    - {item}")

    return "\n".join(lines)


def format_full(snapshot: dict[str, Any], local_report: dict[str, Any]) -> str:
    """Send the full raw snapshot and report as JSON."""
    payload = {
        "snapshot": snapshot,
        "local_report": local_report,
    }
    return (
        "Below is the full raw JSON snapshot and local report from the Factorio mod. "
        "This includes per-planet data in snapshot.surfaces and aggregated totals. "
        "Analyze it and respond with your advice.\n\n"
        + json.dumps(payload, indent=2)
    )


def build_user_message(
    snapshot: dict[str, Any],
    local_report: dict[str, Any],
    mode: str = "curated",
) -> str:
    """Build the user message for the model, using the selected formatting mode."""
    if mode == "full":
        return format_full(snapshot, local_report)
    return format_curated(snapshot, local_report)


def build_detail_user_message(
    item_text: str,
    section_title: str,
    snapshot: dict[str, Any],
    local_report: dict[str, Any],
    mode: str = "curated",
) -> str:
    """Build the user message for a detail/elaboration request.

    The player clicked "get more info" on a specific recommendation item and
    wants a detailed justification with actionable steps.
    """
    if mode == "full":
        snapshot_text = format_full(snapshot, local_report)
    else:
        snapshot_text = format_curated(snapshot, local_report)

    return (
        f"The player wants more detail on this specific recommendation:\n"
        f"\n"
        f"Section: {section_title}\n"
        f"Recommendation: {item_text}\n"
        f"\n"
        f"Here is the current factory state for context:\n"
        f"\n"
        f"{snapshot_text}"
    )
