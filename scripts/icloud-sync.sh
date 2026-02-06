#!/bin/bash
# shellcheck disable=SC2088
# iCloud 雙向同步腳本
# 用法: icloud-sync.sh [capture|apply|diff|status] [options]
set -euo pipefail

# ===== 防止並發執行（macOS 相容）=====
LOCK_FILE="/tmp/icloud-sync.lock"
if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "Another icloud-sync instance is running. Exiting."
    exit 0
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles-shared"

# 顏色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# ===== iCloud 可用性檢查 =====
check_icloud_ready() {
    if [[ ! -d "$ICLOUD_DIR" ]]; then
        log_warn "iCloud 目錄不存在: $ICLOUD_DIR"
        return 1
    fi
    # 檢查是否有 iCloud 暫存檔（表示尚未下載完成）
    if find "$ICLOUD_DIR" -name ".*.icloud" -maxdepth 2 2>/dev/null | head -1 | grep -q .; then
        log_warn "iCloud 尚有檔案未下載完成，部分同步可能不完整"
    fi
    return 0
}

# ===== 衝突檢查 =====
check_conflict() {
    local local_path="$1"
    local icloud_path="$2"
    local name="$3"

    if [[ ! -e "$local_path" ]] || [[ -L "$local_path" ]]; then
        return 0  # 本地不存在或已是 symlink，無衝突
    fi

    if [[ ! -e "$icloud_path" ]]; then
        return 0  # iCloud 不存在，無衝突
    fi

    local local_mtime icloud_mtime
    local_mtime=$(stat -f '%m' "$local_path" 2>/dev/null || echo 0)
    icloud_mtime=$(stat -f '%m' "$icloud_path" 2>/dev/null || echo 0)

    if [[ "$icloud_mtime" -gt "$local_mtime" ]]; then
        log_warn "衝突: $name iCloud 版本較新 (iCloud: $(date -r "$icloud_mtime" '+%Y-%m-%d %H:%M'), 本地: $(date -r "$local_mtime" '+%Y-%m-%d %H:%M'))"
        log_warn "使用 --force 強制覆蓋，或先執行 'apply' 同步 iCloud 版本"
        return 1
    fi
    return 0
}

# ===== Capture: 本地 → iCloud =====
capture() {
    local force=false
    [[ "${1:-}" == "--force" ]] && force=true

    log_info "Capturing local configs to iCloud..."
    if ! check_icloud_ready; then
        log_warn "iCloud 未就緒，跳過 capture"
        exit 1
    fi

    # 衝突檢查（除非 --force）
    if [[ "$force" != "true" ]]; then
        local has_conflict=false
        check_conflict "$HOME/.claude/agents" "$ICLOUD_DIR/claude/agents" "Claude agents" || has_conflict=true
        check_conflict "$HOME/.claude/skills" "$ICLOUD_DIR/claude/skills" "Claude skills" || has_conflict=true
        check_conflict "$HOME/.codex/skills" "$ICLOUD_DIR/codex/skills" "Codex skills" || has_conflict=true
        check_conflict "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json" "Claude settings.json" || has_conflict=true
        check_conflict "$HOME/.claude-code-router/config.json" "$ICLOUD_DIR/ccr/config.json" "CCR config" || has_conflict=true
        check_conflict "$HOME/.config/opencode/oh-my-opencode.json" "$ICLOUD_DIR/opencode/oh-my-opencode.json" "OpenCode config" || has_conflict=true
        check_conflict "$HOME/.config/opencode/agent" "$ICLOUD_DIR/opencode/agent" "OpenCode agents" || has_conflict=true
        check_conflict "$HOME/.config/opencode/plugin" "$ICLOUD_DIR/opencode/plugin" "OpenCode plugin" || has_conflict=true
        check_conflict "$HOME/.config/opencode/superpowers" "$ICLOUD_DIR/opencode/superpowers" "OpenCode superpowers" || has_conflict=true

        if [[ "$has_conflict" == "true" ]]; then
            log_warn "發現衝突，capture 中止"
            exit 1
        fi
    fi

    mkdir -p "$ICLOUD_DIR"/{claude/{agents,skills},codex/skills,ccr,opencode/{agent,plugin,superpowers},vscode,iterm2}

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

    # Claude Code Router (CCR) config
    if [[ -f "$HOME/.claude-code-router/config.json" ]] && [[ ! -L "$HOME/.claude-code-router/config.json" ]]; then
        cp "$HOME/.claude-code-router/config.json" "$ICLOUD_DIR/ccr/config.json"
        log_ok "CCR config.json → iCloud"
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

    # OpenCode providers (動態 provider 設定)
    if [[ -f "$HOME/.opencode-providers.json" ]] && [[ ! -L "$HOME/.opencode-providers.json" ]]; then
        cp "$HOME/.opencode-providers.json" "$ICLOUD_DIR/opencode/opencode-providers.json"
        log_ok "OpenCode providers → iCloud"
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
    local dry_run=false
    [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]] && dry_run=true

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would apply iCloud configs to local..."
    else
        log_info "Applying iCloud configs to local..."
    fi

    if ! check_icloud_ready; then
        log_warn "iCloud 未就緒，跳過 apply"
        log_info "Run 'icloud-sync.sh capture' on another machine first."
        exit 1
    fi

    # Claude agents (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/agents" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: ~/.claude"
        else
            mkdir -p "$HOME/.claude"
        fi
        if [[ ! -L "$HOME/.claude/agents" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.claude/agents" ]] && log_info "[DRY-RUN] Would backup: ~/.claude/agents → ~/.claude/agents.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/agents → $ICLOUD_DIR/claude/agents"
            else
                [[ -d "$HOME/.claude/agents" ]] && mv "$HOME/.claude/agents" "$HOME/.claude/agents.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/agents" "$HOME/.claude/agents"
                log_ok "Claude agents ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude agents already symlinked"
        fi
    fi

    # Claude skills (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/skills" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: ~/.claude"
        else
            mkdir -p "$HOME/.claude"
        fi
        if [[ ! -L "$HOME/.claude/skills" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.claude/skills" ]] && log_info "[DRY-RUN] Would backup: ~/.claude/skills → ~/.claude/skills.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/skills → $ICLOUD_DIR/claude/skills"
            else
                [[ -d "$HOME/.claude/skills" ]] && mv "$HOME/.claude/skills" "$HOME/.claude/skills.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/skills" "$HOME/.claude/skills"
                log_ok "Claude skills ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude skills already symlinked"
        fi
    fi

    # Codex skills (create symlink)
    if [[ -d "$ICLOUD_DIR/codex/skills" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: ~/.codex"
        else
            mkdir -p "$HOME/.codex"
        fi
        if [[ ! -L "$HOME/.codex/skills" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.codex/skills" ]] && log_info "[DRY-RUN] Would backup: ~/.codex/skills → ~/.codex/skills.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.codex/skills → $ICLOUD_DIR/codex/skills"
            else
                [[ -d "$HOME/.codex/skills" ]] && mv "$HOME/.codex/skills" "$HOME/.codex/skills.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/codex/skills" "$HOME/.codex/skills"
                log_ok "Codex skills ← iCloud (symlinked)"
            fi
        else
            log_ok "Codex skills already symlinked"
        fi
    fi

    # Claude Code Router (CCR) config (create symlink)
    if [[ -f "$ICLOUD_DIR/ccr/config.json" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: ~/.claude-code-router"
        else
            mkdir -p "$HOME/.claude-code-router"
        fi
        if [[ ! -L "$HOME/.claude-code-router/config.json" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.claude-code-router/config.json" ]] && log_info "[DRY-RUN] Would backup: config.json → config.json.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude-code-router/config.json → $ICLOUD_DIR/ccr/config.json"
            else
                [[ -f "$HOME/.claude-code-router/config.json" ]] && mv "$HOME/.claude-code-router/config.json" "$HOME/.claude-code-router/config.json.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/ccr/config.json" "$HOME/.claude-code-router/config.json"
                log_ok "CCR config ← iCloud (symlinked)"
            fi
        else
            log_ok "CCR config already symlinked"
        fi
    fi

    # OpenCode (create symlinks)
    if [[ -d "$ICLOUD_DIR/opencode" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would create directory: ~/.config/opencode"
        else
            mkdir -p "$HOME/.config/opencode"
        fi

        if [[ -f "$ICLOUD_DIR/opencode/oh-my-opencode.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && log_info "[DRY-RUN] Would backup: oh-my-opencode.json → oh-my-opencode.json.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.config/opencode/oh-my-opencode.json → $ICLOUD_DIR/opencode/oh-my-opencode.json"
            else
                [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && mv "$HOME/.config/opencode/oh-my-opencode.json" "$HOME/.config/opencode/oh-my-opencode.json.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/opencode/oh-my-opencode.json" "$HOME/.config/opencode/oh-my-opencode.json"
                log_ok "OpenCode config ← iCloud (symlinked)"
            fi
        fi

        if [[ -d "$ICLOUD_DIR/opencode/agent" ]] && [[ ! -L "$HOME/.config/opencode/agent" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.config/opencode/agent" ]] && log_info "[DRY-RUN] Would backup: agent/ → agent.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.config/opencode/agent → $ICLOUD_DIR/opencode/agent"
            else
                [[ -d "$HOME/.config/opencode/agent" ]] && mv "$HOME/.config/opencode/agent" "$HOME/.config/opencode/agent.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/opencode/agent" "$HOME/.config/opencode/agent"
                log_ok "OpenCode agents ← iCloud (symlinked)"
            fi
        fi

        if [[ -d "$ICLOUD_DIR/opencode/plugin" ]] && [[ ! -L "$HOME/.config/opencode/plugin" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.config/opencode/plugin" ]] && log_info "[DRY-RUN] Would backup: plugin/ → plugin.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.config/opencode/plugin → $ICLOUD_DIR/opencode/plugin"
            else
                [[ -d "$HOME/.config/opencode/plugin" ]] && mv "$HOME/.config/opencode/plugin" "$HOME/.config/opencode/plugin.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/opencode/plugin" "$HOME/.config/opencode/plugin"
                log_ok "OpenCode plugin ← iCloud (symlinked)"
            fi
        fi

        if [[ -d "$ICLOUD_DIR/opencode/superpowers" ]] && [[ ! -L "$HOME/.config/opencode/superpowers" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.config/opencode/superpowers" ]] && log_info "[DRY-RUN] Would backup: superpowers/ → superpowers.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.config/opencode/superpowers → $ICLOUD_DIR/opencode/superpowers"
            else
                [[ -d "$HOME/.config/opencode/superpowers" ]] && mv "$HOME/.config/opencode/superpowers" "$HOME/.config/opencode/superpowers.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/opencode/superpowers" "$HOME/.config/opencode/superpowers"
                log_ok "OpenCode superpowers ← iCloud (symlinked)"
            fi
        fi
    fi

    # OpenCode providers (動態 provider 設定)
    if [[ -f "$ICLOUD_DIR/opencode/opencode-providers.json" ]] && [[ ! -L "$HOME/.opencode-providers.json" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would symlink: ~/.opencode-providers.json → $ICLOUD_DIR/opencode/opencode-providers.json"
        else
            [[ -f "$HOME/.opencode-providers.json" ]] && mv "$HOME/.opencode-providers.json" "$HOME/.opencode-providers.json.backup.$(date +%s)"
            ln -sf "$ICLOUD_DIR/opencode/opencode-providers.json" "$HOME/.opencode-providers.json"
            log_ok "OpenCode providers ← iCloud (symlinked)"
        fi
    fi

    # iTerm2 preferences (set native iCloud sync)
    if [[ -d "$ICLOUD_DIR/iterm2" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would configure iTerm2 PrefsCustomFolder: $ICLOUD_DIR/iterm2"
        else
            defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ICLOUD_DIR/iterm2"
            defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
            log_ok "iTerm2 ← iCloud (native PrefsCustomFolder)"
        fi
    fi

    # VS Code extensions
    if command -v code &>/dev/null && [[ -f "$ICLOUD_DIR/vscode/extensions.txt" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] Would install VS Code extensions from: $ICLOUD_DIR/vscode/extensions.txt"
        else
            log_info "Installing VS Code extensions..."
            while IFS= read -r ext; do
                [[ -z "$ext" || "$ext" == \#* ]] && continue
                code --install-extension "$ext" --force 2>/dev/null || true
            done < "$ICLOUD_DIR/vscode/extensions.txt"
            log_ok "VS Code extensions installed"
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_ok "[DRY-RUN] Apply preview complete!"
    else
        log_ok "Apply complete!"
    fi
}

# ===== Diff: 顯示本地與 iCloud 差異 =====
diff_configs() {
    log_info "Comparing local vs iCloud..."

    if ! check_icloud_ready; then
        log_warn "iCloud 未就緒"
        exit 1
    fi

    local has_diff=false

    # Claude agents
    if [[ -d "$HOME/.claude/agents" ]] && [[ ! -L "$HOME/.claude/agents" ]]; then
        if [[ -d "$ICLOUD_DIR/claude/agents" ]]; then
            echo ""
            log_info "Claude agents:"
            if diff -rq "$HOME/.claude/agents" "$ICLOUD_DIR/claude/agents" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Claude skills
    if [[ -d "$HOME/.claude/skills" ]] && [[ ! -L "$HOME/.claude/skills" ]]; then
        if [[ -d "$ICLOUD_DIR/claude/skills" ]]; then
            echo ""
            log_info "Claude skills:"
            if diff -rq "$HOME/.claude/skills" "$ICLOUD_DIR/claude/skills" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Codex skills
    if [[ -d "$HOME/.codex/skills" ]] && [[ ! -L "$HOME/.codex/skills" ]]; then
        if [[ -d "$ICLOUD_DIR/codex/skills" ]]; then
            echo ""
            log_info "Codex skills:"
            if diff -rq "$HOME/.codex/skills" "$ICLOUD_DIR/codex/skills" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # CCR config
    if [[ -f "$HOME/.claude-code-router/config.json" ]] && [[ ! -L "$HOME/.claude-code-router/config.json" ]]; then
        if [[ -f "$ICLOUD_DIR/ccr/config.json" ]]; then
            echo ""
            log_info "CCR config.json:"
            if diff -q "$HOME/.claude-code-router/config.json" "$ICLOUD_DIR/ccr/config.json" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Claude settings.json
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        if [[ -f "$ICLOUD_DIR/claude/settings.json" ]]; then
            echo ""
            log_info "Claude settings.json:"
            if diff -q "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # OpenCode config
    if [[ -f "$HOME/.config/opencode/oh-my-opencode.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-opencode.json" ]]; then
        if [[ -f "$ICLOUD_DIR/opencode/oh-my-opencode.json" ]]; then
            echo ""
            log_info "OpenCode oh-my-opencode.json:"
            if diff -q "$HOME/.config/opencode/oh-my-opencode.json" "$ICLOUD_DIR/opencode/oh-my-opencode.json" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # OpenCode agents
    if [[ -d "$HOME/.config/opencode/agent" ]] && [[ ! -L "$HOME/.config/opencode/agent" ]]; then
        if [[ -d "$ICLOUD_DIR/opencode/agent" ]]; then
            echo ""
            log_info "OpenCode agents:"
            if diff -rq "$HOME/.config/opencode/agent" "$ICLOUD_DIR/opencode/agent" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # OpenCode plugin
    if [[ -d "$HOME/.config/opencode/plugin" ]] && [[ ! -L "$HOME/.config/opencode/plugin" ]]; then
        if [[ -d "$ICLOUD_DIR/opencode/plugin" ]]; then
            echo ""
            log_info "OpenCode plugin:"
            if diff -rq "$HOME/.config/opencode/plugin" "$ICLOUD_DIR/opencode/plugin" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # OpenCode superpowers
    if [[ -d "$HOME/.config/opencode/superpowers" ]] && [[ ! -L "$HOME/.config/opencode/superpowers" ]]; then
        if [[ -d "$ICLOUD_DIR/opencode/superpowers" ]]; then
            echo ""
            log_info "OpenCode superpowers:"
            if diff -rq "$HOME/.config/opencode/superpowers" "$ICLOUD_DIR/opencode/superpowers" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    echo ""
    if [[ "$has_diff" == "false" ]]; then
        log_ok "No differences found"
    else
        log_info "Differences found above"
    fi
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

    [[ -f "$ICLOUD_DIR/ccr/config.json" ]] && \
        log_info "CCR config.json ($(stat -f '%Sm' "$ICLOUD_DIR/ccr/config.json" 2>/dev/null || echo 'unknown'))"

    [[ -f "$ICLOUD_DIR/opencode/opencode-providers.json" ]] && \
        log_info "OpenCode providers.json ($(stat -f '%Sm' "$ICLOUD_DIR/opencode/opencode-providers.json" 2>/dev/null || echo 'unknown'))"

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

    if [[ -L "$HOME/.claude-code-router/config.json" ]]; then
        log_ok "~/.claude-code-router/config.json → iCloud"
    elif [[ -f "$HOME/.claude-code-router/config.json" ]]; then
        log_warn "~/.claude-code-router/config.json (not symlinked)"
    fi

    if [[ -L "$HOME/.opencode-providers.json" ]]; then
        log_ok "~/.opencode-providers.json → iCloud"
    elif [[ -f "$HOME/.opencode-providers.json" ]]; then
        log_warn "~/.opencode-providers.json (not symlinked)"
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
    capture)  shift; capture "$@" ;;
    apply)    shift; apply "$@" ;;
    diff)     diff_configs ;;
    status)   status ;;
    *)
        echo "Usage: icloud-sync.sh [command] [options]"
        echo ""
        echo "Commands:"
        echo "  capture [--force]      — 將本地設定同步到 iCloud"
        echo "  apply [-n|--dry-run]   — 從 iCloud 同步設定到本地"
        echo "  diff                   — 顯示本地與 iCloud 的差異"
        echo "  status                 — 顯示同步狀態"
        echo ""
        echo "Options:"
        echo "  --force         (capture) 強制覆蓋，即使 iCloud 版本較新"
        echo "  -n, --dry-run   (apply) 預覽變更而不實際執行"
        exit 1
        ;;
esac
