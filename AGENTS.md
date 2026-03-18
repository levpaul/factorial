# Development Notes

## Git Commits

After every code edit that restarts Factorio, make a git commit with a summary of the changes. This is mandatory for all code changes in this repository.

## Restarting Factorio on macOS

Factorio runs as a Steam app. To restart it:

```bash
# Find the process
ps aux | grep -i factorio | grep -v grep

# Kill by PID (replace XXXXX withactual PID)
kill -9 XXXXX

# Wait a moment then reopen
sleep 2; open -a Factorio
```

Or as a one-liner (finds PID automatically):
```bash
kill -9 $(pgrep -x factorio); sleep 2; open -a Factorio
```

Note: The process name is `factorio` (lowercase), but the app name for `open` is `Factorio` (capitalized).