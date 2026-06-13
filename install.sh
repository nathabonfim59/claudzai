#!/bin/bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/nathabonfim59/claudzai/main"
GITHUB_API="https://api.github.com/repos/nathabonfim59/claudzai"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.glm}"

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
RED='\033[31m'
RESET='\033[0m'

info()  { echo -e "${CYAN}  ->${RESET} $*"; }
ok()    { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()  { echo -e "${YELLOW}  !${RESET} $*"; }
die()   { echo -e "${RED}  ✗${RESET} $*"; exit 1; }

# Compare two semver strings (strips a leading "v" and any pre-release
# suffix). Echoes -1 if $1 < $2, 0 if equal, 1 if $1 > $2.
semver_cmp() {
    local IFS=.
    local -a a b
    read -ra a <<< "${1#v}"
    read -ra b <<< "${2#v}"
    local i x y
    for i in 0 1 2; do
        x=${a[i]:-0}; y=${b[i]:-0}
        x=${x%%[^0-9]*}; y=${y%%[^0-9]*}
        x=${x:-0}; y=${y:-0}
        if (( x > y )); then echo 1; return; fi
        if (( x < y )); then echo -1; return; fi
    done
    echo 0
}

# Echo the latest released version (no leading "v"), or nothing if it can't
# be determined. Prefers the latest GitHub Release, falls back to tags.
fetch_latest_version() {
    local ver
    ver=$(curl -fsSL "${GITHUB_API}/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    [ -n "$ver" ] && { echo "$ver"; return 0; }
    ver=$(curl -fsSL "${GITHUB_API}/tags" 2>/dev/null \
        | grep -oE '"name":[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    [ -n "$ver" ] && echo "$ver"
    return 0
}

ask() {
    local prompt="$1"
    local default="${2:-y}"
    local choices="[Y/n]"
    [ "$default" = "n" ] && choices="[y/N]"

    while true; do
        echo -ne "  ${BOLD}${prompt}${RESET} ${choices} "
        read -r answer < /dev/tty
        answer="${answer:-$default}"
        case "$answer" in
            y|Y|yes) return 0 ;;
            n|N|no)  return 1 ;;
            *)       echo "  Please answer y or n." ;;
        esac
    done
}

ask_text() {
    local prompt="$1"
    echo -ne "  ${BOLD}${prompt}${RESET} "
    read -r answer < /dev/tty
    echo "$answer"
}

# ── Flags (passed via `bash -s -- <flag>`; only affect update mode) ────────
FORCE=0
CHECK_ONLY=0
for _arg in "$@"; do
    case "$_arg" in
        --force|-f) FORCE=1 ;;
        --check|-c) CHECK_ONLY=1 ;;
    esac
done

# ── Update mode: refresh an existing install without re-prompting ─────────
# Re-running the installer on an already-installed system pulls the latest
# claude-zai wrapper and skill while leaving your settings, API key, and
# memory links untouched. Fully non-interactive.
if [ -f "${INSTALL_DIR}/claude-zai" ]; then
    echo ""
    echo -e "${BOLD}  claudzai updater${RESET} (existing install detected)"
    echo ""

    if [ -n "${ZAI_API_KEY:-}" ]; then
        ok "ZAI_API_KEY is set"
    else
        warn "ZAI_API_KEY is not set (add it to your shell config before running claude-zai)"
    fi

    # ── Version check ────────────────────────────────────────────────────
    installed_version=$(grep -oE 'CLAUDE_ZAI_VERSION="[0-9]+\.[0-9]+\.[0-9]+"' "${INSTALL_DIR}/claude-zai" 2>/dev/null \
        | head -1 | cut -d'"' -f2 || true)

    if [ "${CHECK_ONLY}" -eq 1 ]; then
        latest_version=$(fetch_latest_version)
        echo ""
        echo "  Installed: ${installed_version:-unknown}"
        echo "  Latest:    ${latest_version:-unknown}"
        if [ -n "$installed_version" ] && [ -n "$latest_version" ]; then
            case "$(semver_cmp "$latest_version" "$installed_version")" in
                1)  echo "  Status:    update available (v${installed_version} -> v${latest_version})" ;;
                0)  echo "  Status:    up to date" ;;
                -1) echo "  Status:    installed is newer than the latest release" ;;
            esac
        fi
        exit 0
    fi

    if [ "${FORCE}" -ne 1 ]; then
        latest_version=$(fetch_latest_version)
        if [ -z "$latest_version" ]; then
            echo ""
            warn "Could not determine the latest version (no release found or network error)"
            info "Proceeding with the update — use --check to inspect versions"
        elif [ -z "$installed_version" ]; then
            echo ""
            info "Installed version unknown (pre-versioned install) — updating to v${latest_version}"
        else
            case "$(semver_cmp "$latest_version" "$installed_version")" in
                0)
                    ok "Already up to date (v${installed_version})"
                    echo "  Run with --force to refresh the files anyway."
                    exit 0
                    ;;
                -1)
                    warn "Installed version (v${installed_version}) is newer than the latest release (v${latest_version})"
                    echo "  Run with --force to refresh the files anyway."
                    exit 0
                    ;;
                1)
                    info "Update available: v${installed_version} -> v${latest_version}"
                    ;;
            esac
        fi
    fi

    # Refresh the wrapper (this is where model mappings and backend config live)
    echo ""
    info "Updating claude-zai to the latest version..."
    mkdir -p "$INSTALL_DIR"
    tmp=$(mktemp)
    curl -fsSL "${REPO}/claude-zai" -o "$tmp" || die "Failed to download claude-zai"
    chmod +x "$tmp"
    mv "$tmp" "${INSTALL_DIR}/claude-zai"
    ok "Updated ${INSTALL_DIR}/claude-zai"

    # Ensure install dir is in PATH
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            if [ -f "$HOME/.zshrc" ]; then
                rc_file="$HOME/.zshrc"
            else
                rc_file="$HOME/.bashrc"
            fi
            echo "" >> "$rc_file"
            echo "# Added by claudzai installer" >> "$rc_file"
            echo "export PATH=\"\${PATH}:${INSTALL_DIR}\"" >> "$rc_file"
            ok "Added ${INSTALL_DIR} to PATH in ${rc_file}"
            export PATH="${PATH}:${INSTALL_DIR}"
            ;;
    esac

    # Preserve user-customized settings; only seed if missing
    echo ""
    if [ -f "${CONFIG_DIR}/settings.json" ]; then
        info "Kept existing ${CONFIG_DIR}/settings.json (untouched)"
    else
        mkdir -p "$CONFIG_DIR"
        tmp=$(mktemp)
        curl -fsSL "${REPO}/settings.json" -o "$tmp" || die "Failed to download settings.json"
        mv "$tmp" "${CONFIG_DIR}/settings.json"
        ok "Saved settings to ${CONFIG_DIR}/settings.json"
    fi

    # Refresh the teammate skill (idempotent: installs or updates to latest)
    echo ""
    if command -v npx &>/dev/null; then
        info "Updating claude-zai-teammate skill..."
        # < /dev/tty: under `curl | bash`, stdin IS the script stream. Without
        # this redirect npx drains the remaining script bytes as its stdin, so
        # the command refresh and "done" banner below never execute.
        if npx skills add nathabonfim59/claudzai -a claude-code -g -y < /dev/tty; then
            ok "Skill updated"
        else
            warn "Skill update failed (continuing)"
        fi
    else
        info "npx not found, skipping skill update"
    fi

    # Refresh the /claude-zai-update slash command
    mkdir -p "${CONFIG_DIR}/commands"
    tmp=$(mktemp)
    if curl -fsSL "${REPO}/commands/claude-zai-update.md" -o "$tmp"; then
        mv "$tmp" "${CONFIG_DIR}/commands/claude-zai-update.md"
        ok "Updated /claude-zai-update command"
    else
        rm -f "$tmp"
        warn "Could not refresh /claude-zai-update command (skipped)"
    fi

    echo ""
    ok "claudzai updated to the latest version!"
    echo ""
    exit 0
fi

# ── Fresh install (interactive) ──────────────────────────────────────────

echo ""
echo -e "${BOLD}  claudzai installer${RESET}"
echo ""

# ── 1. API key ──────────────────────────────────────────────────────────

if [ -n "${ZAI_API_KEY:-}" ]; then
    ok "ZAI_API_KEY is already set"
else
    warn "ZAI_API_KEY is not set"
    echo ""
    key=$(ask_text "Enter your Z.AI API key (will be saved to shell config):")
    [ -z "$key" ] && die "No API key provided, aborting."

    # Detect shell config
    if [ -f "$HOME/.zshrc" ]; then
        rc_file="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        rc_file="$HOME/.bashrc"
    else
        rc_file="$HOME/.bashrc"
    fi

    echo "" >> "$rc_file"
    echo "# Z.AI API key (added by claudzai installer)" >> "$rc_file"
    echo "export ZAI_API_KEY=\"${key}\"" >> "$rc_file"
    export ZAI_API_KEY="$key"
    ok "Saved to ${rc_file}"
fi

# ── 2. Download claude-zai ──────────────────────────────────────────────

echo ""
info "Downloading claude-zai to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"

tmp=$(mktemp)
curl -fsSL "${REPO}/claude-zai" -o "$tmp" || die "Failed to download claude-zai"
chmod +x "$tmp"
mv "$tmp" "${INSTALL_DIR}/claude-zai"
ok "Installed to ${INSTALL_DIR}/claude-zai"

# Ensure install dir is in PATH
case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        warn "${INSTALL_DIR} is not in your PATH"
        if [ -f "$HOME/.zshrc" ]; then
            rc_file="$HOME/.zshrc"
        else
            rc_file="$HOME/.bashrc"
        fi
        echo "" >> "$rc_file"
        echo "# Added by claudzai installer" >> "$rc_file"
        echo "export PATH=\"\${PATH}:${INSTALL_DIR}\"" >> "$rc_file"
        ok "Added ${INSTALL_DIR} to PATH in ${rc_file}"
        export PATH="${PATH}:${INSTALL_DIR}"
        ;;
esac

# ── 3. Recommended settings ─────────────────────────────────────────────

echo ""
if ask "Copy recommended settings to ${CONFIG_DIR}/settings.json?"; then
    mkdir -p "$CONFIG_DIR"
    tmp=$(mktemp)
    curl -fsSL "${REPO}/settings.json" -o "$tmp" || die "Failed to download settings.json"
    if [ -f "${CONFIG_DIR}/settings.json" ]; then
        warn "settings.json already exists"
        if ask "Overwrite it?"; then
            mv "$tmp" "${CONFIG_DIR}/settings.json"
            ok "Settings saved to ${CONFIG_DIR}/settings.json"
        else
            rm -f "$tmp"
            info "Kept existing settings.json"
        fi
    else
        mv "$tmp" "${CONFIG_DIR}/settings.json"
        ok "Settings saved to ${CONFIG_DIR}/settings.json"
    fi
else
    info "Skipped settings"
fi

# ── 4. Link project memories ─────────────────────────────────────────────

CLAUDE_PROJECTS="$HOME/.claude/projects"

echo ""
if [ -d "$CLAUDE_PROJECTS" ]; then
    if ask "Link project memories from ${CLAUDE_PROJECTS}? (shared between Claude and claudzai)"; then
        mkdir -p "$CONFIG_DIR"
        if [ -d "${CONFIG_DIR}/projects" ] && [ ! -L "${CONFIG_DIR}/projects" ]; then
            warn "${CONFIG_DIR}/projects already exists and is not a symlink, skipping"
        else
            ln -sfn "$CLAUDE_PROJECTS" "${CONFIG_DIR}/projects"
            ok "Linked ${CONFIG_DIR}/projects -> ${CLAUDE_PROJECTS}"
        fi
    else
        info "Skipped memory linking"
    fi
else
    info "No existing Claude project memories found, skipping"
fi

# ── 5. Teammate skill ───────────────────────────────────────────────────

echo ""
if ask "Install the claude-zai-teammate skill?"; then
    if command -v npx &>/dev/null; then
        info "Installing skill to Claude Code globally..."
        echo ""
        # < /dev/tty: under `curl | bash`, stdin IS the script stream. Without
        # this redirect npx drains the remaining script bytes as its stdin, so
        # the /claude-zai-update command below never gets installed.
        npx skills add nathabonfim59/claudzai -a claude-code -g -y < /dev/tty
        ok "Skill installed"
    else
        warn "npx not found. Install Node.js first, then run:"
        echo "  npx skills add nathabonfim59/claudzai -a claude-code -g -y"
    fi
else
    info "Skipped skill install"
fi

# ── 6. claude-zai-update command ────────────────────────────────────────

echo ""
mkdir -p "${CONFIG_DIR}/commands"
tmp=$(mktemp)
if curl -fsSL "${REPO}/commands/claude-zai-update.md" -o "$tmp"; then
    mv "$tmp" "${CONFIG_DIR}/commands/claude-zai-update.md"
    ok "Installed /claude-zai-update command"
else
    rm -f "$tmp"
    warn "Could not install /claude-zai-update command (skipped)"
fi

# ── Done ─────────────────────────────────────────────────────────────────

echo ""
ok "All done! Run ${BOLD}claude-zai${RESET} to get started."
echo -e "  Restart your shell or run ${BOLD}source ~/.bashrc${RESET} (or ~/.zshrc) to pick up changes."
echo ""
