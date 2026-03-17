# Architecture

## Current shape

The mod is built in three layers:

1. Snapshot collection
2. Rule-based analysis
3. Presentation and optional external bridge

### Snapshot collection

The snapshot collector in [scripts/advisor.lua](/Users/levilovelock/repos/factorial/scripts/advisor.lua) pulls runtime information that is cheap and stable:

- researched technologies
- entity counts using `LuaForce::get_entity_count()`
- one-minute production and consumption rates using `LuaFlowStatistics::get_flow_count()`
- current surface resource totals using `LuaSurface::get_resource_counts()`
- pollution and enemy evolution

This gives a compact state vector that is useful both for rules and for a future agent prompt.

### Rule engine

The current rule engine produces the five advisor categories directly from the snapshot:

- next focus
- largest bottleneck
- new patterns
- upcoming issues
- anti-patterns

That rule layer is intentionally explainable. Each recommendation ties back to observed state such as:

- "burner miners still outnumber electric drills"
- "steel production is below demand"
- "enemy evolution is high but walls and turrets are light"

### UI

The UI is kept simple on purpose:

- refresh
- export
- ask external
- close

This keeps the first version reliable and easy to iterate on while the advice logic evolves.

## External agent path

Factorio mods should not own the full agent runtime. Instead:

1. The mod exports `latest_request.json` into `script-output`.
2. The mod can also send the same request over localhost UDP.
3. A sidecar bridge receives the JSON.
4. The bridge can call any model provider.
5. The bridge sends a compact response JSON back to Factorio.

That response should ideally look like this:

```json
{
  "title": "External Advisor",
  "summary": "Your base is entering blue science but copper and oil are both underbuilt.",
  "sections": [
    {
      "title": "Strategic Focus",
      "items": [
        "Secure a second copper patch.",
        "Split refinery products with proper cracking.",
        "Scale red circuits before adding more labs."
      ]
    }
  ]
}
```

## Recommended next steps

- Add richer per-surface and per-outpost analysis.
- Track recent changes over time instead of only reading the current state.
- Detect rail readiness and logistics maturity more explicitly.
- Add optional chart tags or alerts for urgent issues.
- Add a real model bridge once you decide which model/provider you want to target.
