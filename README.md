# claudzai

A wrapper script that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with [Z.AI](https://z.ai) as the backend provider, mapping Z.AI's GLM models to Claude's Opus/Sonnet/Haiku/Fable tiers.

**Why?** Z.AI offers the same Claude Code experience at lower cost and with higher rate limits. This wrapper lets you use it as a drop-in replacement, including spawning teammates for parallel work.

## What it does

`claude-zai` is a thin shell wrapper around the official `claude` CLI that:

- Points the Anthropic SDK at Z.AI's API (`https://api.z.ai/api/anthropic`)
- Maps GLM models to Claude model tiers so existing prompts and tooling work unchanged
- Isolates all configuration under `~/.glm` instead of `~/.claude`

## Model mapping

All tiers run on the GLM-5.3 family with a 1M-token context window, each with its own default thinking effort:

| Claude tier | Z.AI model       | Default effort | GLM thinking level |
|-------------|------------------|----------------|--------------------|
| Opus        | GLM-5.3 (1M)     | `high`         | high               |
| Sonnet      | GLM-5.3 (1M)     | `high`         | high               |
| Haiku       | GLM-5.3-Flash (1M) | `low`        | low                |
| Fable       | GLM-5.3 (1M)     | `xhigh`        | max                |

GLM-5.2 (1M) is still available as the older model. It appears in the `/model` picker as GLM-5.2.

### How effort control works

- GLM-5.3 supports three thinking levels: low, high, and max. Z.AI converts Claude Code's effort values to them: `low` becomes low, `medium` and `high` become high, `xhigh` and `max` become max. The wrapper sets `CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1` because Claude Code doesn't recognize GLM model IDs as effort-capable and would skip the parameter without it. Per-tier defaults are set in `modelSettings` in `settings.json`.
- Fable runs the same model as Opus and Sonnet but needs its own effort level, so it sends `xhigh` (Z.AI converts it to max). Claude Code strips the `[1m]` suffix before sending, because it is only a client-side context-window hint. `glm-5.3` and `glm-5.3[1m]` therefore reach Z.AI as the same model but stay distinct `modelSettings` keys. `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000` keeps the bare-ID tier on the 1M window.
- `/effort` still works in-session and overrides the tier default for the current model; confirming with <kbd>Enter</kbd> saves your choice back into `modelSettings`.

### Auto mode classifier checks

Auto mode's [no-charge classifier checks](https://code.claude.com/docs/en/auto-mode-classifier-billing) run on Anthropic's servers, so they can't work through Z.AI's gateway. claudzai sets `CLAUDE_CODE_AUTO_MODE_SERVER=0` to stop Claude Code from asking for them, which also suppresses the "this session isn't eligible" notice. Auto mode keeps working. Classifier checks run as regular model requests billed to your Z.AI usage, never to an Anthropic subscription, because every request, classifier checks included, routes through the Z.AI key.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed (`claude` in `$PATH`)
- A `ZAI_API_KEY` environment variable set with your Z.AI API key

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/claudzai/main/install.sh | bash
```

Re-running the same command updates an existing installation in place. It checks the latest release and only refreshes the wrapper and skill when a newer version is available. From inside a claudzai session, the `/claude-zai-update` command does the same thing.

The installer will walk you through:

1. Setting your `ZAI_API_KEY` (saved to `~/.bashrc` or `~/.zshrc`)
2. Downloading `claude-zai` to `~/.local/bin`
3. Copying the recommended `settings.json` to `~/.glm/`
4. Installing the teammate skill via `npx`

All Claude Code flags and arguments are passed through to `claude` unchanged.

## Versioning & updates

claudzai is versioned with `vX.Y.Z` [GitHub releases](https://github.com/nathabonfim59/claudzai/releases). The installed version is printed by:

```bash
claude-zai --version     # or: claude-zai -V
```

The updater compares your installed version against the latest release and only downloads when a newer version exists. If you're already current it prints `Already up to date` and does nothing. Two flags are available when piping the installer to bash:

```bash
# Just report installed vs. latest, then exit
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/claudzai/main/install.sh | bash -s -- --check

# Force a refresh even when already up to date
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/claudzai/main/install.sh | bash -s -- --force
```

If the latest version can't be determined (no release found yet, or a network error), the updater falls back to refreshing the files rather than blocking the update.

### Cutting a release (maintainers)

1. Bump `CLAUDE_ZAI_VERSION` in [`claude-zai`](claude-zai). It's the single source of truth.
2. Commit and push to `main`.
3. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.

A [GitHub Action](.github/workflows/release.yml) then verifies the tag matches the version, fails the run on mismatch, and publishes the release. Once published, `--check` and every updater run pick up the new version.

## Configuration directory: `~/.glm`

This wrapper sets `CLAUDE_CONFIG_DIR` to `~/.glm`, so all Claude Code state lives there instead of the default `~/.claude`:

```
~/.glm/
├── settings.json        # Global settings (model, status line, env vars, etc.)
├── .claude.json         # Internal state
├── history.jsonl        # Conversation history
├── projects/            # Per-project settings and memory
├── sessions/            # Session data
├── plans/               # Saved plans
└── ...
```

Any configuration you'd normally put in `~/.claude` goes in `~/.glm` instead. For example:

- **Settings** - edit `~/.glm/settings.json` (or use `/config` inside the session - it writes to the same place)
- **Status line** - set the `statusLine` key in `~/.glm/settings.json`
- **Per-project settings** - go under `~/.glm/projects/`
- **Memory files** - stored under `~/.glm/projects/<project>/memory/`

The in-app UI (settings panels, `/config`, etc.) works the same - it reads and writes to `~/.glm` instead.

## Status line

The included `settings.json` already configures [cc-statusline](https://github.com/nathabonfim59/cc-statusline) - a fast, themeable status line that shows context usage, cost, timing, git state, and diff stats. It also helps when using teammates. A `tmux capture-pane` snapshot shows how full the teammate's context is and whether it has uncommitted changes.

Just install it:

```bash
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/cc-statusline/main/install.sh | bash
```

See the [cc-statusline repo](https://github.com/nathabonfim59/cc-statusline) for theming, custom layouts, and other options.

## Teammate skill

The [`skills/claude-zai-teammate/`](skills/claude-zai-teammate/) directory contains a Claude Code skill that spawns `claude-zai` instances as interactive teammates in tmux. It recreates the built-in teammate feature on Z.AI's API, so you get the same multi-agent workflow at lower cost.

### How it works

- Spawns a new tmux window running `claude-zai --dangerously-skip-permissions`
- Communicates between the orchestrator and teammates via `tmux send-keys`
- Teammates message the orchestrator by typing into its pane
- You can watch and steer any teammate by attaching to the tmux session

### Prerequisites

- [tmux](https://github.com/tmux/tmux) installed and your main Claude Code session running inside it
- The skill files placed in your project's `.claude/skills/` directory

### Install the skill

**Option 1: via npx (recommended)**

```bash
npx skills add nathabonfim59/claudzai -a claude-code -g -y
```

**Option 2: clone the repo**

```bash
git clone https://github.com/nathabonfim59/claudzai.git
```

Then copy `skills/claude-zai-teammate/` into your project's `.claude/skills/`.

Once installed, Claude Code will pick it up automatically and can spawn teammates when asked to delegate work.

## Why a separate config dir?

Keeping `~/.glm` separate from `~/.claude` means your real Claude Code setup and your Z.AI setup don't interfere with each other. You can run either one independently with its own history, sessions, and settings.

This also means memories are not shared between the two. Anything you saved via `/remember` or the memory system in your regular Claude Code setup won't be visible inside `claude-zai`, and vice versa.

If you want to share memories (or other state) between the two, you can symlink specific folders. For example, to share project memories:

```bash
ln -s ~/.claude/projects ~/.glm/projects
```

## License

MIT
