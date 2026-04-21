#!/bin/bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/nathabonfim59/claudzai/main"
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

ask() {
    local prompt="$1"
    local default="${2:-y}"
    local choices="[Y/n]"
    [ "$default" = "n" ] && choices="[y/N]"

    while true; do
        echo -ne "  ${BOLD}${prompt}${RESET} ${choices} "
        read -r answer
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
    read -r answer
    echo "$answer"
}

# ── 1. API key ──────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}  claudzai installer${RESET}"
echo ""

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

# ── 4. Teammate skill ───────────────────────────────────────────────────

echo ""
if ask "Install the claude-zai-teammate skill?"; then
    if command -v npx &>/dev/null; then
        info "Running npx skills add — use SPACE to select Claude Code, then install globally."
        echo ""
        npx skills add https://github.com/nathabonfim59/claudzai
        ok "Skill install complete"
    else
        warn "npx not found. Install Node.js first, then run:"
        echo "  npx skills add https://github.com/nathabonfim59/claudzai"
    fi
else
    info "Skipped skill install"
fi

# ── Done ─────────────────────────────────────────────────────────────────

echo ""
ok "All done! Run ${BOLD}claude-zai${RESET} to get started."
echo "  Restart your shell or run ${BOLD}source ~/.bashrc${RESET} (or ~/.zshrc) to pick up changes."
echo ""
