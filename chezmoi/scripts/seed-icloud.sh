#!/bin/bash
# Seed iCloud with initial AI tool configs from local machine
# Run once after first chezmoi apply to populate iCloud
set -euo pipefail

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles-shared"

GREEN='\033[0;32m'
NC='\033[0m'
log_ok() { echo -e "${GREEN}✓${NC} $1"; }

echo "Seeding iCloud with initial configs from local machine..."
mkdir -p "$ICLOUD_DIR"/{claude/{agents,skills},codex/skills,opencode/{agent,plugin,superpowers},vscode,iterm2}

# Claude Code settings (non-sensitive)
if [[ -f "$HOME/.claude/settings.json" ]]; then
    cp "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json"
    log_ok "Claude settings.json → iCloud"
fi

# Claude agents
if [[ -d "$HOME/.claude/agents" ]] && [[ ! -L "$HOME/.claude/agents" ]]; then
    cp -R "$HOME/.claude/agents/"* "$ICLOUD_DIR/claude/agents/" 2>/dev/null || true
    log_ok "Claude agents → iCloud"
fi

# Claude skills
if [[ -d "$HOME/.claude/skills" ]] && [[ ! -L "$HOME/.claude/skills" ]]; then
    cp -R "$HOME/.claude/skills/"* "$ICLOUD_DIR/claude/skills/" 2>/dev/null || true
    log_ok "Claude skills → iCloud"
fi

# Codex skills
if [[ -d "$HOME/.codex/skills" ]] && [[ ! -L "$HOME/.codex/skills" ]]; then
    cp -R "$HOME/.codex/skills/"* "$ICLOUD_DIR/codex/skills/" 2>/dev/null || true
    log_ok "Codex skills → iCloud"
fi

# OpenCode non-sensitive
if [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
    cp "$HOME/.config/opencode/oh-my-opencode.json" "$ICLOUD_DIR/opencode/oh-my-opencode.json"
    log_ok "OpenCode oh-my-opencode.json → iCloud"
fi

if [[ -d "$HOME/.config/opencode/agent" ]] && [[ ! -L "$HOME/.config/opencode/agent" ]]; then
    cp -R "$HOME/.config/opencode/agent/"* "$ICLOUD_DIR/opencode/agent/" 2>/dev/null || true
    log_ok "OpenCode agents → iCloud"
fi

if [[ -d "$HOME/.config/opencode/plugin" ]] && [[ ! -L "$HOME/.config/opencode/plugin" ]]; then
    cp -R "$HOME/.config/opencode/plugin/"* "$ICLOUD_DIR/opencode/plugin/" 2>/dev/null || true
    log_ok "OpenCode plugin → iCloud"
fi

if [[ -d "$HOME/.config/opencode/superpowers" ]] && [[ ! -L "$HOME/.config/opencode/superpowers" ]]; then
    cp -R "$HOME/.config/opencode/superpowers/"* "$ICLOUD_DIR/opencode/superpowers/" 2>/dev/null || true
    log_ok "OpenCode superpowers → iCloud"
fi

# iTerm2 preferences
if [[ -f "$HOME/Library/Preferences/com.googlecode.iterm2.plist" ]]; then
    cp "$HOME/Library/Preferences/com.googlecode.iterm2.plist" "$ICLOUD_DIR/iterm2/"
    log_ok "iTerm2 preferences → iCloud"
fi

# VS Code extensions
if command -v code &>/dev/null; then
    code --list-extensions > "$ICLOUD_DIR/vscode/extensions.txt" 2>/dev/null || true
    log_ok "VS Code extensions list → iCloud"
fi

echo ""
echo "✓ iCloud seeding complete!"
echo "  iCloud will automatically sync to your other devices."
echo "  On other machines, run: chezmoi apply"
