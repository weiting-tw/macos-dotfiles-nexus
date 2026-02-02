#!/bin/bash
# iCloud 雙向同步腳本
# 用法: icloud-sync.sh [capture|apply|status]
set -euo pipefail

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles-shared"

# 顏色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# ===== Capture: 本地 → iCloud =====
capture() {
    log_info "Capturing local configs to iCloud..."
    mkdir -p "$ICLOUD_DIR"/{claude/{agents,skills},codex/skills,opencode/{agent,plugin,superpowers},vscode,iterm2}

    # Claude Code agents
    if [[ -d "$HOME/.claude/agents" ]] && [[ ! -L "$HOME/.claude/agents" ]]; then
        rsync -av --delete "$HOME/.claude/agents/" "$ICLOUD_DIR/claude/agents/"
        log_ok "Claude agents → iCloud"
    fi

    # Claude Code skills
    if [[ -d "$HOME/.claude/skills" ]] && [[ ! -L "$HOME/.claude/skills" ]]; then
        rsync -av --delete "$HOME/.claude/skills/" "$ICLOUD_DIR/claude/skills/"
        log_ok "Claude skills → iCloud"
    fi

    # Codex skills
    if [[ -d "$HOME/.codex/skills" ]] && [[ ! -L "$HOME/.codex/skills" ]]; then
        rsync -av --delete "$HOME/.codex/skills/" "$ICLOUD_DIR/codex/skills/"
        log_ok "Codex skills → iCloud"
    fi

    # Claude Code settings.json
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        cp "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json"
        log_ok "Claude settings.json → iCloud"
    fi

    # OpenCode non-sensitive
    if [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
        cp "$HOME/.config/opencode/oh-my-opencode.json" "$ICLOUD_DIR/opencode/oh-my-opencode.json"
        log_ok "OpenCode oh-my-opencode.json → iCloud"
    fi

    if [[ -d "$HOME/.config/opencode/agent" ]] && [[ ! -L "$HOME/.config/opencode/agent" ]]; then
        rsync -av --delete "$HOME/.config/opencode/agent/" "$ICLOUD_DIR/opencode/agent/"
        log_ok "OpenCode agents → iCloud"
    fi

    if [[ -d "$HOME/.config/opencode/plugin" ]] && [[ ! -L "$HOME/.config/opencode/plugin" ]]; then
        rsync -av --delete "$HOME/.config/opencode/plugin/" "$ICLOUD_DIR/opencode/plugin/"
        log_ok "OpenCode plugin → iCloud"
    fi

    if [[ -d "$HOME/.config/opencode/superpowers" ]] && [[ ! -L "$HOME/.config/opencode/superpowers" ]]; then
        rsync -av --delete "$HOME/.config/opencode/superpowers/" "$ICLOUD_DIR/opencode/superpowers/"
        log_ok "OpenCode superpowers → iCloud"
    fi

    # VS Code extensions
    if command -v code &>/dev/null; then
        code --list-extensions > "$ICLOUD_DIR/vscode/extensions.txt"
        log_ok "VS Code extensions list → iCloud ($(wc -l < "$ICLOUD_DIR/vscode/extensions.txt" | tr -d ' ') extensions)"
    fi

    # iTerm2 preferences
    if [[ -f "$HOME/Library/Preferences/com.googlecode.iterm2.plist" ]]; then
        cp "$HOME/Library/Preferences/com.googlecode.iterm2.plist" "$ICLOUD_DIR/iterm2/"
        log_ok "iTerm2 preferences → iCloud"
    fi

    # Brewfile snapshot
    if command -v brew &>/dev/null; then
        brew bundle dump --force --file="$ICLOUD_DIR/Brewfile.snapshot"
        log_ok "Brewfile snapshot → iCloud"
    fi

    log_ok "Capture complete!"
}

# ===== Apply: iCloud → 本地 =====
apply() {
    log_info "Applying iCloud configs to local..."

    if [[ ! -d "$ICLOUD_DIR" ]]; then
        log_warn "iCloud directory not found: $ICLOUD_DIR"
        log_info "Run 'icloud-sync.sh capture' on another machine first."
        exit 1
    fi

    # Claude agents (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/agents" ]]; then
        mkdir -p "$HOME/.claude"
        if [[ ! -L "$HOME/.claude/agents" ]]; then
            [[ -d "$HOME/.claude/agents" ]] && mv "$HOME/.claude/agents" "$HOME/.claude/agents.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/claude/agents" "$HOME/.claude/agents"
            log_ok "Claude agents ← iCloud (symlinked)"
        else
            log_ok "Claude agents already symlinked"
        fi
    fi

    # Claude skills (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/skills" ]]; then
        mkdir -p "$HOME/.claude"
        if [[ ! -L "$HOME/.claude/skills" ]]; then
            [[ -d "$HOME/.claude/skills" ]] && mv "$HOME/.claude/skills" "$HOME/.claude/skills.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/claude/skills" "$HOME/.claude/skills"
            log_ok "Claude skills ← iCloud (symlinked)"
        else
            log_ok "Claude skills already symlinked"
        fi
    fi

    # Codex skills (create symlink)
    if [[ -d "$ICLOUD_DIR/codex/skills" ]]; then
        mkdir -p "$HOME/.codex"
        if [[ ! -L "$HOME/.codex/skills" ]]; then
            [[ -d "$HOME/.codex/skills" ]] && mv "$HOME/.codex/skills" "$HOME/.codex/skills.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/codex/skills" "$HOME/.codex/skills"
            log_ok "Codex skills ← iCloud (symlinked)"
        else
            log_ok "Codex skills already symlinked"
        fi
    fi

    # OpenCode (create symlinks)
    if [[ -d "$ICLOUD_DIR/opencode" ]]; then
        mkdir -p "$HOME/.config/opencode"

        if [[ -f "$ICLOUD_DIR/opencode/oh-my-opencode.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
            [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && mv "$HOME/.config/opencode/oh-my-opencode.json" "$HOME/.config/opencode/oh-my-opencode.json.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/opencode/oh-my-opencode.json" "$HOME/.config/opencode/oh-my-opencode.json"
            log_ok "OpenCode config ← iCloud (symlinked)"
        fi

        if [[ -d "$ICLOUD_DIR/opencode/agent" ]] && [[ ! -L "$HOME/.config/opencode/agent" ]]; then
            [[ -d "$HOME/.config/opencode/agent" ]] && mv "$HOME/.config/opencode/agent" "$HOME/.config/opencode/agent.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/opencode/agent" "$HOME/.config/opencode/agent"
            log_ok "OpenCode agents ← iCloud (symlinked)"
        fi

        if [[ -d "$ICLOUD_DIR/opencode/plugin" ]] && [[ ! -L "$HOME/.config/opencode/plugin" ]]; then
            [[ -d "$HOME/.config/opencode/plugin" ]] && mv "$HOME/.config/opencode/plugin" "$HOME/.config/opencode/plugin.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/opencode/plugin" "$HOME/.config/opencode/plugin"
            log_ok "OpenCode plugin ← iCloud (symlinked)"
        fi

        if [[ -d "$ICLOUD_DIR/opencode/superpowers" ]] && [[ ! -L "$HOME/.config/opencode/superpowers" ]]; then
            [[ -d "$HOME/.config/opencode/superpowers" ]] && mv "$HOME/.config/opencode/superpowers" "$HOME/.config/opencode/superpowers.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/opencode/superpowers" "$HOME/.config/opencode/superpowers"
            log_ok "OpenCode superpowers ← iCloud (symlinked)"
        fi
    fi

    # iTerm2 preferences (set native iCloud sync)
    if [[ -d "$ICLOUD_DIR/iterm2" ]]; then
        defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ICLOUD_DIR/iterm2"
        defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
        log_ok "iTerm2 ← iCloud (native PrefsCustomFolder)"
    fi

    # VS Code extensions
    if command -v code &>/dev/null && [[ -f "$ICLOUD_DIR/vscode/extensions.txt" ]]; then
        log_info "Installing VS Code extensions..."
        while IFS= read -r ext; do
            [[ -z "$ext" || "$ext" == \#* ]] && continue
            code --install-extension "$ext" --force 2>/dev/null || true
        done < "$ICLOUD_DIR/vscode/extensions.txt"
        log_ok "VS Code extensions installed"
    fi

    log_ok "Apply complete!"
}

# ===== Status: 顯示同步狀態 =====
status() {
    echo "=== iCloud Sync Status ==="
    echo ""

    if [[ -d "$ICLOUD_DIR" ]]; then
        log_ok "iCloud directory: $ICLOUD_DIR"
    else
        log_warn "iCloud directory not found"
        return
    fi

    echo ""
    echo "Files in iCloud:"

    [[ -f "$ICLOUD_DIR/claude/settings.json" ]] && \
        log_info "Claude settings.json ($(stat -f '%Sm' "$ICLOUD_DIR/claude/settings.json" 2>/dev/null || echo 'unknown'))"

    [[ -d "$ICLOUD_DIR/claude/agents" ]] && \
        log_info "Claude agents/ ($(ls "$ICLOUD_DIR/claude/agents" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/claude/skills" ]] && \
        log_info "Claude skills/ ($(ls "$ICLOUD_DIR/claude/skills" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/codex/skills" ]] && \
        log_info "Codex skills/ ($(ls "$ICLOUD_DIR/codex/skills" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -f "$ICLOUD_DIR/opencode/oh-my-opencode.json" ]] && \
        log_info "OpenCode oh-my-opencode.json"

    [[ -d "$ICLOUD_DIR/opencode/agent" ]] && \
        log_info "OpenCode agents/ ($(ls "$ICLOUD_DIR/opencode/agent" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/opencode/plugin" ]] && \
        log_info "OpenCode plugin/ ($(ls "$ICLOUD_DIR/opencode/plugin" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/opencode/superpowers" ]] && \
        log_info "OpenCode superpowers/ ($(ls "$ICLOUD_DIR/opencode/superpowers" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -f "$ICLOUD_DIR/vscode/extensions.txt" ]] && \
        log_info "VS Code extensions.txt ($(wc -l < "$ICLOUD_DIR/vscode/extensions.txt" | tr -d ' ') extensions)"

    [[ -f "$ICLOUD_DIR/iterm2/com.googlecode.iterm2.plist" ]] && \
        log_info "iTerm2 plist ($(stat -f '%Sm' "$ICLOUD_DIR/iterm2/com.googlecode.iterm2.plist" 2>/dev/null || echo 'unknown'))"

    [[ -f "$ICLOUD_DIR/Brewfile.snapshot" ]] && \
        log_info "Brewfile.snapshot ($(stat -f '%Sm' "$ICLOUD_DIR/Brewfile.snapshot" 2>/dev/null || echo 'unknown'))"

    echo ""
    echo "Local symlinks:"

    if [[ -L "$HOME/.claude/agents" ]]; then
        log_ok "~/.claude/agents → iCloud"
    else
        log_warn "~/.claude/agents (not symlinked)"
    fi

    if [[ -L "$HOME/.claude/skills" ]]; then
        log_ok "~/.claude/skills → iCloud"
    else
        log_warn "~/.claude/skills (not symlinked)"
    fi

    if [[ -L "$HOME/.codex/skills" ]]; then
        log_ok "~/.codex/skills → iCloud"
    else
        log_warn "~/.codex/skills (not symlinked)"
    fi

    if [[ -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
        log_ok "~/.config/opencode/oh-my-opencode.json → iCloud"
    else
        log_warn "OpenCode config (not symlinked)"
    fi

    if [[ -L "$HOME/.config/opencode/agent" ]]; then
        log_ok "~/.config/opencode/agent → iCloud"
    else
        log_warn "OpenCode agents (not symlinked)"
    fi

    if [[ -L "$HOME/.config/opencode/plugin" ]]; then
        log_ok "~/.config/opencode/plugin → iCloud"
    else
        log_warn "OpenCode plugin (not symlinked)"
    fi

    if [[ -L "$HOME/.config/opencode/superpowers" ]]; then
        log_ok "~/.config/opencode/superpowers → iCloud"
    else
        log_warn "OpenCode superpowers (not symlinked)"
    fi

    # iTerm2 native sync (not symlink, uses PrefsCustomFolder)
    local iterm_folder
    iterm_folder="$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || echo '')"
    local iterm_load
    iterm_load="$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || echo '0')"
    if [[ "$iterm_load" == "1" && "$iterm_folder" == "$ICLOUD_DIR/iterm2" ]]; then
        log_ok "iTerm2 → iCloud (native PrefsCustomFolder)"
    elif [[ "$iterm_load" == "1" ]]; then
        log_warn "iTerm2 PrefsCustomFolder 指向: $iterm_folder (預期: $ICLOUD_DIR/iterm2)"
    else
        log_warn "iTerm2 iCloud sync 未啟用"
    fi
}

# ===== Main =====
case "${1:-status}" in
    capture)  capture ;;
    apply)    apply ;;
    status)   status ;;
    *)
        echo "Usage: icloud-sync.sh [capture|apply|status]"
        echo ""
        echo "  capture  — 將本地設定同步到 iCloud"
        echo "  apply    — 從 iCloud 同步設定到本地"
        echo "  status   — 顯示同步狀態"
        exit 1
        ;;
esac
