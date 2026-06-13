---
description: Update claudzai to the latest version (re-runs the installer)
---

Update claudzai to the latest version by re-running the installer. It checks the installed version against the latest GitHub release and **only refreshes the `claude-zai` wrapper and teammate skill if a newer version is available** — when already current it reports `Already up to date` and changes nothing. Your settings and API key are preserved.

Run the installer using the Bash tool:

```bash
curl -fsSL https://raw.githubusercontent.com/nathabonfim59/claudzai/main/install.sh | bash
```

When it finishes, briefly summarize what was updated (or report that it was already up to date).

