# claudzai

A wrapper script that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with [Z.AI](https://z.ai) as the backend provider, mapping Z.AI's GLM models to Claude's Opus/Sonnet/Haiku tiers.

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

Set your API key in your shell config so it persists across sessions:

```bash
echo 'export ZAI_API_KEY="your-api-key-here"' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```bash
# Make the wrapper available (one-time)
chmod +x claude-zai
sudo ln -s "$(pwd)/claude-zai" /usr/local/bin/claude-zai

# Run it like you would run claude
claude-zai
claude-zai "explain this codebase"
claude-zai --dangerously-skip-permissions
```

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

## Why a separate config dir?

Keeping `~/.glm` separate from `~/.claude` means your real Claude Code setup and your Z.AI setup don't interfere with each other. You can run either one independently with its own history, sessions, and settings.

## License

MIT
