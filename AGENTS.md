# Development Notes

## Git Worktrees for Parallel Agent Execution

**IMPORTANT**: When implementing features or making code changes, ALWAYS use git worktrees to enable parallel agent execution. Multiple agents may be working on different features simultaneously, and worktrees prevent conflicts.

### Creating a Worktree

Before making any code changes, create a worktree:

```bash
# Create a worktree for your feature branch
git worktree add .worktrees/<feature-name> -b <feature-name>

# Example for a feature called "dropdown-ui":
git worktree add .worktrees/dropdown-ui -b dropdown-ui
```

### Working in a Worktree

1. Navigate to your worktree directory:
   ```bash
   cd .worktrees/<feature-name>
   ```

2. Make all code changes in this directory
3. Commit changes as usual
4. Push when ready:
   ```bash
   git push origin <feature-name>
   ```

### Cleaning Up Worktrees

After your changes are merged or no longer needed:

```bash
# Remove the worktree directory
git worktree remove .worktrees/<feature-name>

# Optionally delete the branch
git branch -d <feature-name>
```

### Worktree Naming Convention

- Use kebab-case for worktree names: `add-dropdown-ui`, `fix-scope-bug`, etc.
- Match the worktree name to the feature branch name
- Place all worktrees in `.worktrees/` directory

### Why Worktrees?

- Multiple agents can work on different features simultaneously
- Each agent has isolated working directory
- No risk of overwriting each other's changes
- Shared git history and refs

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

## Restarting the Bridge

The bridge (`python -m bridge`) must be killed and restarted every time Factorio is restarted. It runs from the `tools/` directory and listens on UDP port 34198.

```bash
# Kill the bridge
kill -9 $(pgrep -f 'python.*-m bridge')

# Restart it (from the tools/ directory)
cd /Users/levilovelock/repos/factorial/tools && python -m bridge &
```

**This is mandatory**: whenever you restart Factorio, always kill and restart the bridge as well.