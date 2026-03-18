# Factorial AI Advisor

A Factorio 2.0 mod that provides intelligent gameplay advice based on real-time analysis of your factory.

## What It Does

The advisor reads your game state and surfaces five kinds of guidance:

1. **Focus Priorities** - What to work on next based on your progression stage
2. **Resource Bottlenecks** - Identifies your biggest production constraints (iron, copper, steel, oil, power)
3. **Pattern Recommendations** - Suggests better factory designs and layout improvements
4. **Predictive Warnings** - Alerts you to upcoming issues (ore depletion, biter pressure, brownouts)
5. **Anti-Pattern Detection** - Flags inefficient setups you should improve

The mod tracks:
- Researched technologies
- Entity counts (assemblers, furnaces, drills, labs, etc.)
- One-minute production/consumption rates
- Surface resource totals
- Pollution and enemy evolution

## Architecture

The mod has two layers:

**Internal Advisor (Rule-Based)**
- Fast, always available, no external dependency
- Deterministic analysis of factory state
- Trustworthy advice based on game signals

**External Advisor (AI/Model-Based)**
- Sends snapshot JSON to a localhost UDP bridge
- External process can invoke any AI/LLM
- Response displayed alongside internal advice

## Installation

1. Clone or download this repository
2. Copy/symlink to your Factorio mods directory as `factorial`:
   - **Windows**: `%appdata%\Factorio\mods\`
   - **macOS**: `~/Library/Application Support/factorio/mods/`
   - **Linux**: `~/.factorio/mods/`
3. Enable the mod in Factorio

## Usage

### Opening the Advisor

- Press **Control+Shift+A** (or **Shift+F**)
- Or use console command: `/advisor`

### Buttons

| Button | Action |
|--------|--------|
| Refresh | Re-analyze factory and update recommendations |
| Export | Save snapshot and report JSON to `script-output/factorial/` |
| Ask External | Send factory data to external UDP bridge for AI analysis |
| Show Internal | Toggle internal advisor recommendations (hidden by default) |
| Clear | Clear all displayed information |

### Console Commands

| Command | Description |
|---------|-------------|
| `/advisor` | Toggle advisor window |
| `/advisor-refresh` | Refresh analysis |
| `/advisor-export` | Export snapshot to script-output |
| `/advisor-send` | Send snapshot to UDP bridge |

### Mod Settings

Settings → Mod Settings → Global:

| Setting | Default | Description |
|---------|---------|-------------|
| Enable UDP Bridge | false | Enable sending data to external AI |
| UDP Send Port | 34198 | Port for sending UDP data |
| UDP Receive Port | 34199 | Port for receiving UDP responses |
| Auto-Poll UDP | true | Automatically check for responses |
| Dev Mode | false | Enable selectable/copyable text in advisor window |

## External AI Integration

To use an external AI advisor:

1. Enable "Enable UDP Bridge" in mod settings
2. Start Factorio with UDP enabled:
   ```
   factorio --enable-lua-udp=34199
   ```
3. Run your UDP bridge server (default port 34198)
4. Click "Ask External" or use `/advisor-send`

Example bridge: `python3 tools/udp_bridge_example.py --port 34198`

### Snapshot Payload

The JSON payload includes:
- Factory metadata (tick, surface, player info)
- Entity counts (assemblers, furnaces, drills, etc.)
- Production rates (items, fluids per minute)
- Resource totals per surface
- Technology progression
- Environmental data (pollution, evolution)

## Files

| File | Purpose |
|------|---------|
| `control.lua` | Event handlers and commands |
| `data.lua` | Custom input definitions |
| `settings.lua` | Mod settings configuration |
| `scripts/advisor.lua` | Internal advisor logic |
| `scripts/external.lua` | UDP bridge integration |
| `scripts/gui.lua` | UI rendering |
| `locale/en/locale.cfg` | English translations |
| `tools/udp_bridge_example.py` | Example UDP bridge server |
| `docs/architecture.md` | Detailed architecture docs |

## Development

### Restarting Factorio (macOS)

```bash
kill -9 $(pgrep -x factorio); sleep 2; open -a Factorio
```

Note: The process name is `factorio` (lowercase), but the app name for `open` is `Factorio` (capitalized).

## Accuracy Notes

The advisor uses heuristic signals that are cheap to read:
- Entity counts
- Tech gates
- Resource totals
- Rate deltas
- Environmental pressure

It doesn't inspect belt layouts, inserter wiring, or local geometry. This makes it a reliable base layer for deterministic advice while leaving strategic analysis to optional external AI.

## License

MIT License