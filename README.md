# claudzai

A wrapper script that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with [Z.AI](https://z.ai) as the backend provider, mapping Z.AI's GLM models to Claude's Opus/Sonnet/Haiku tiers.

**Why?** Z.AI offers the same Claude Code experience at lower cost and with higher rate limits. This wrapper lets you use it as a drop-in replacement, including spawning teammates for parallel work.

## What it does

`claude-zai` is a thin shell wrapper around the official `claude` CLI that:

- Points the Anthropic SDK at Z.AI's API (`https://api.z.ai/api/anthropic`)
- Maps GLM models to Claude model tiers so existing prompts and tooling work unchanged
- Isolates all configuration under `~/.glm` instead of `~/.claude`

## Model mapping

| Claude tier    | Z.AI model    |
|----------------|---------------|
| Opus           | GLM-5.1       |
| Sonnet         | GLM-5         |
| Haiku          | GLM-5-Turbo   |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed (`claude` in `$PATH`)
- A `ZAI_API_KEY` environment variable set with your Z.AI API key

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/claudzai/main/install.sh | sh
```

The installer will walk you through:

1. Setting your `ZAI_API_KEY` (saved to `~/.bashrc` or `~/.zshrc`)
2. Downloading `claude-zai` to `~/.local/bin`
3. Copying the recommended `settings.json` to `~/.glm/`
4. Installing the teammate skill via `npx`

All Claude Code flags and arguments are passed through to `claude` unchanged.

## Configuration directory: `~/.glm`

This wrapper sets `CLAUDE_CONFIG_DIR` to `~/.glm`, which means **all** Claude Code state lives there instead of the default `~/.claude`:

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

**This is important:** any configuration you'd normally put in `~/.claude` goes in `~/.glm` instead. For example:

- **Settings** — edit `~/.glm/settings.json` (or use `/config` inside the session — it writes to the same place)
- **Status line** — set the `statusLine` key in `~/.glm/settings.json`
- **Per-project settings** — go under `~/.glm/projects/`
- **Memory files** — stored under `~/.glm/projects/<project>/memory/`

The in-app UI (settings panels, `/config`, etc.) works the same — it just reads and writes to `~/.glm` behind the scenes.

## Status line

The included `settings.json` already configures [cc-statusline](https://github.com/nathabonfim59/cc-statusline) — a fast, themeable status line that shows context usage, cost, timing, git state, and diff stats. It also helps when using teammates: a `tmux capture-pane` snapshot reveals the teammate's context fill level and whether it has uncommitted changes.

Just install it:

```bash
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/cc-statusline/main/install.sh | sh
```

See the [cc-statusline repo](https://github.com/nathabonfim59/cc-statusline) for theming, custom layouts, and other options.

## Teammate skill

The [`skills/claude-zai-teammate/`](skills/claude-zai-teammate/) directory contains a Claude Code skill that spawns `claude-zai` instances as interactive teammates in tmux. This recreates the built-in teammate feature but using Z.AI's API instead, so you get the same multi-agent workflow at lower cost.

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
npx skills add https://github.com/nathabonfim59/claudzai
```

It will prompt you to select the skill and which agents to install it to.

**Option 2: clone the repo**

```bash
git clone https://github.com/nathabonfim59/claudzai.git
```

Then copy `skills/claude-zai-teammate/` into your project's `.claude/skills/`.

Once installed, Claude Code will pick it up automatically and can spawn teammates when asked to delegate work.

## Why a separate config dir?

Keeping `~/.glm` separate from `~/.claude` means your real Claude Code setup and your Z.AI setup don't interfere with each other. You can run either one independently with its own history, sessions, and settings.

This also means **memories are not shared** between the two. Anything you saved via `/remember` or the memory system in your regular Claude Code setup won't be visible inside `claude-zai`, and vice versa.

If you want to share memories (or other state) between the two, you can symlink specific folders. For example, to share project memories:

```bash
ln -s ~/.claude/projects ~/.glm/projects
```

## License

MIT
