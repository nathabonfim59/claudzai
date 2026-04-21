---
name: claude-zai-teammate
description: Spawn `claude-zai` as an interactive teammate in a tmux window so the user can watch/steer it live, while Claude and claude-zai message each other via `tmux send-keys`. Use this whenever a user asks to delegate implementation to claude-zai, or whenever the memory rule "delegate implementation to claude-zai" applies and an interactive session is useful.
---

# claude-zai as an interactive tmux teammate

This is a lightweight replacement for the built-in teammate feature (TeamCreate / SendMessage), which only supports internal subagents. `claude-zai` is an external CLI — another Claude Code instance — so we coordinate via tmux instead.

## Architecture

- **My pane**: where the user is talking to me (read from `$TMUX_PANE`, e.g. `%29`). Full pane target is `$TMUX_PANE` itself — tmux accepts bare pane IDs as targets.
- **Teammate pane**: a new tmux window in the same session running `claude-zai` interactively.
- **Me → teammate**: `tmux send-keys -t <teammate-pane> -l "<msg>" && tmux send-keys -t <teammate-pane> Enter`
- **Teammate → me**: `tmux send-keys -t <my-pane> -l "<msg>" && tmux send-keys -t <my-pane> Enter` — lands as a normal user-prompt turn for me.
- **User → both**: `tmux attach` to the session; `Ctrl-b <n>` to switch windows; type in either.

## Spawning the teammate

1. Verify I'm in tmux: require `$TMUX` and `$TMUX_PANE` to be set. If not, fall back to `claude-zai -p` background mode and tell the user.
2. Pick a window name based on the task (e.g. `zai-video`, `zai-auth`). Keep it short, prefix with `zai-`.
3. Create the window in the *current* session (use `-c <cwd>` so it starts in the project dir):

   ```bash
   MY_PANE="$TMUX_PANE"
   WIN=zai-<taskslug>
   tmux new-window -d -n "$WIN" -c "$PWD" 'claude-zai'
   sleep 5   # claude-zai needs ~4-5s to boot and render UI
   TEAMMATE_PANE=$(tmux list-panes -t "$WIN" -F '#{pane_id}' | head -1)
   ```

4. **Capture gotcha.** `tmux capture-pane -p -S -30` (with history range) returns empty if no scrollback yet — use plain `tmux capture-pane -t <pane> -p` for the current visible buffer. Use `-S` when you need more context (agent stuck, unclear output, debugging).

5. Send the initial briefing — it MUST include (a) the task, (b) my pane id so it can message me, (c) the explicit messaging protocol. Use `tmux send-keys -l` (literal) for the body, then a separate `Enter`:

   ```bash
   BRIEF=$(cat <<EOF
   You are running as an interactive teammate in tmux. Your orchestrator (another
   Claude Code instance) is in pane ${MY_PANE}. The human user may also attach to
   this session and type directly — treat that input as coming from the user.

   Your teammate identity is: **${TEAMMATE_NAME}** (the tmux window name,
   e.g. "zai-video"). EVERY message you send back MUST start with
   \`[${TEAMMATE_NAME}]\` so the orchestrator can distinguish you from other
   teammates working in parallel.

   To send a message back to the orchestrator, run:
     tmux send-keys -l -t ${MY_PANE} "[${TEAMMATE_NAME}] <your message>" && tmux send-keys -t ${MY_PANE} Enter

   **MANDATORY: acknowledge every inbound message.** When a briefing or
   follow-up message arrives, send a one-line ack IMMEDIATELY before doing
   anything else: `[${TEAMMATE_NAME}] received: <short gist>`. This lets the
   orchestrator confirm delivery — if the ack doesn't come back within a minute
   or two, the orchestrator knows the keystrokes didn't land (scroll mode,
   modal dialog, pane wedged) and will diagnose via capture-pane.

   **MANDATORY: you MUST send a completion message to the orchestrator when you
   finish — even if the work succeeded without blockers.** Without that message
   the orchestrator has no way to know you're done and will keep waiting.
   The completion message should summarize: files changed (one line each), any
   deviations from the plan, and anything skipped (e.g. "migration NOT run, no
   containers started, no commit"). Send it BEFORE you go idle, prefixed with
   your identity tag.

   Also send a message when: you hit a blocker, you need a decision, or you're
   about to take an irreversible action. Do NOT narrate every step — the user
   and orchestrator can watch your pane directly.

   Working directory: <cwd>
   Task: <one-line summary>
   Full plan: <ABSOLUTE path to the plan file, if one exists — omit the line entirely for simple tasks>

   Begin by reading the plan file FIRST (if provided). Do not start implementing
   from just the briefing prose — the plan file has the authoritative context,
   constraints, file paths, and verification steps. Ask the orchestrator before
   making irreversible changes (commits, pushes, destructive git ops). Do not
   commit unless explicitly told to.
   EOF
   )
   TEAMMATE_NAME="$WIN"   # used in the briefing template above
   tmux send-keys -t "$TEAMMATE_PANE" -l "$BRIEF"
   sleep 1
   tmux send-keys -t "$TEAMMATE_PANE" Enter
   ```

6. Record the pane id somewhere stable for later sends. Simplest: save to `/tmp/claude-zai-teammate-<slug>.pane` — one line with the pane id.

## Sending follow-up messages

```bash
TEAMMATE_PANE=$(cat /tmp/claude-zai-teammate-<slug>.pane)
tmux send-keys -t "$TEAMMATE_PANE" -l "<message>"
sleep 1
tmux send-keys -t "$TEAMMATE_PANE" Enter
```

Always `-l` (literal) the body so special chars don't trigger tmux key parsing. Send Enter as a **separate call** with a brief sleep between — combining them in one `send-keys` invocation sometimes races with the app's input buffering. This was confirmed by killing a pane during the bypass-permissions menu when `Down Enter` was sent together.

## Observing without disturbing

```bash
tmux capture-pane -t "$TEAMMATE_PANE" -p -S -200
```

Use this to check progress when the teammate has been silent a while. Don't poll every few seconds — prefer waiting for the teammate to message back.

## Shutting down

When work is done or aborted:

```bash
tmux send-keys -t "$TEAMMATE_PANE" -l "/exit"
tmux send-keys -t "$TEAMMATE_PANE" Enter
# give it a moment, then force-close the window if still alive:
sleep 2 && tmux kill-window -t "$WIN" 2>/dev/null || true
rm -f /tmp/claude-zai-teammate-<slug>.pane
```

## Conventions I follow when using this

- **For substantial tasks, write a plan file to `~/.claude/plans/<slug>.md` and include the absolute path in the briefing.** For simple tasks (small bug fix, one-line change, focused tweak), an inline prose brief is fine — don't create plan files for everything. Rough rule: if the task would fit in a paragraph, skip the plan file; if it needs multiple sections or you find yourself enumerating many files, write one.
- Always tell the user the window name and how to attach (`tmux attach` then `Ctrl-b n` to cycle windows, or `tmux select-window -t <win>`).
- Don't flood the teammate with messages — one message, wait for reply, then follow up.
- The teammate's output is NOT automatically in my context. If I need to know what happened, either wait for its message or `capture-pane`.
- If the user types directly into the teammate pane, treat subsequent teammate messages as authoritative — the user may have redirected it.
- If `$TMUX` is unset, this skill cannot run; fall back to `claude-zai -p` in background and explain why.

## Learnings

See [LEARNINGS.md](./LEARNINGS.md) for dated gotchas and fixes. Before changing the spawn/messaging protocol, skim it — most traps already have a recorded answer. Append new entries there (not here) when you discover something non-obvious.
