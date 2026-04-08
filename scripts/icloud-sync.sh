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
RED='\033[0;31m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_err()  { echo -e "${RED}✗${NC} $1"; }
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# ===== Symlink 註冊表 =====
# 格式: 路徑|類型(dir/file)|顯示名稱
SYMLINK_REGISTRY=(
    "$HOME/.claude/agents|dir|Claude agents"
    "$HOME/.claude/skills|dir|Claude skills"
    "$HOME/.claude/hooks|dir|Claude hooks"
    "$HOME/.claude/hud|dir|Claude HUD"
    "$HOME/.claude/CLAUDE.md|file|Claude CLAUDE.md"
    "$HOME/.claude/.mcp.json|file|Claude MCP config"
    "$HOME/.claude/settings.json|file|Claude settings"
    "$HOME/.codex/skills|dir|Codex skills"
    "$HOME/.claude-code-router/config.json|file|CCR config"
    "$HOME/.config/opencode/oh-my-openagent.json|file|OpenCode config"
    "$HOME/.config/opencode/agent|dir|OpenCode agents"
    "$HOME/.config/opencode/plugin|dir|OpenCode plugin"
    "$HOME/.config/opencode/superpowers|dir|OpenCode superpowers"
    "$HOME/.opencode-providers.json|file|OpenCode providers"
    "$HOME/Library/Application Support/Beyond Compare 5|dir|Beyond Compare 5"
    "$HOME/.agents|dir|Codex skills (agents)"
)

# ===== 健康檢查單項 =====
check_symlink_health() {
    local path="$1"
    local type="$2"
    local name="$3"

    # 1. 是否為 symlink
    if [[ ! -L "$path" ]]; then
        if [[ -e "$path" ]]; then
            log_warn "$name: 存在但非 symlink ($path)"
            suggest_fix "not_symlink" "$name" "$path"
        else
            log_err "$name: 不存在 ($path)"
            suggest_fix "not_exist" "$name" "$path"
        fi
        return 1
    fi

    # 2. symlink 目標是否存在（dangling check）
    if [[ ! -e "$path" ]]; then
        log_err "$name: symlink 斷鏈 (目標不存在)"
        suggest_fix "dangling" "$name" "$path"
        return 1
    fi

    # 3. 目標是否有內容
    if [[ "$type" == "dir" ]]; then
        if [[ -z "$(ls -A "$path" 2>/dev/null)" ]]; then
            log_err "$name: symlink 目標為空目錄"
            suggest_fix "empty_dir" "$name" "$path"
            return 1
        fi
    elif [[ "$type" == "file" ]]; then
        if [[ ! -s "$path" ]]; then
            log_err "$name: symlink 目標為空檔案"
            suggest_fix "empty_file" "$name" "$path"
            return 1
        fi
    fi

    # 4. 檢查 iCloud stub（.*.icloud 表示尚未下載）
    local target
    target="$(readlink "$path")"
    if [[ "$type" == "dir" ]]; then
        if find "$target" -maxdepth 1 -name ".*.icloud" 2>/dev/null | head -1 | grep -q .; then
            log_warn "$name: iCloud 尚有檔案未下載完成"
            suggest_fix "icloud_stub" "$name" "$path"
            return 1
        fi
    elif [[ "$type" == "file" ]]; then
        local target_dir target_base
        target_dir="$(dirname "$target")"
        target_base="$(basename "$target")"
        if [[ -f "$target_dir/.${target_base}.icloud" ]]; then
            log_warn "$name: iCloud 檔案未下載完成 (stub)"
            suggest_fix "icloud_stub" "$name" "$path"
            return 1
        fi
    fi

    log_ok "$name: 正常"
    return 0
}

# ===== macOS 通知 =====
notify_health_failure() {
    local message="$1"
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"$message\" with title \"iCloud Sync Health\" subtitle \"Symlink 問題\"" 2>/dev/null || true
    fi
}

# ===== 修復建議 =====
suggest_fix() {
    local issue="$1"
    local name="$2"
    local path="$3"
    case "$issue" in
        dangling)
            echo "  修復: 執行 'icloud-sync.sh apply' 重建 symlink，或檢查 iCloud 是否同步完成"
            ;;
        empty_dir)
            echo "  修復: 確認 iCloud 已同步完成，或從其他機器執行 'icloud-sync.sh capture' 推送內容"
            ;;
        empty_file)
            echo "  修復: 確認 iCloud 已同步完成，或從其他機器執行 'icloud-sync.sh capture'"
            ;;
        not_symlink)
            echo "  修復: 執行 'icloud-sync.sh apply' 將本地目錄轉為 symlink"
            ;;
        not_exist)
            echo "  修復: 執行 'icloud-sync.sh apply' 建立 symlink"
            ;;
        icloud_stub)
            echo "  修復: 開啟 Finder 瀏覽 iCloud 目錄，觸發下載；或執行 'brctl download $path'"
            ;;
        missing_node_modules)
            echo "  修復: 執行 'icloud-sync.sh apply' 自動建立 node_modules symlink"
            ;;
    esac
}

# ===== Health: 深度健康檢查 =====
health() {
    echo "=== iCloud Symlink Health Check ==="
    echo ""

    local errors=0
    local warnings=0
    local failed_items=()

    for entry in "${SYMLINK_REGISTRY[@]}"; do
        IFS='|' read -r path type name <<< "$entry"
        if ! check_symlink_health "$path" "$type" "$name"; then
            ((errors++))
            failed_items+=("$name")
        fi
    done

    # OpenCode 特殊檢查: node_modules 依賴
    echo ""
    log_info "OpenCode node_modules 檢查:"
    local sp_nm="$HOME/.config/opencode/superpowers"
    if [[ -L "$sp_nm" ]] && [[ -e "$sp_nm" ]]; then
        local sp_target
        sp_target="$(readlink "$sp_nm")"
        if [[ -d "$sp_target/.opencode/plugin" ]]; then
            if [[ ! -e "$sp_target/.opencode/node_modules" ]]; then
                log_err "OpenCode superpowers: 缺少 node_modules (plugin 無法運作)"
                suggest_fix "missing_node_modules" "OpenCode node_modules" "$sp_target"
                ((errors++))
                failed_items+=("OpenCode node_modules")
            else
                log_ok "OpenCode superpowers: node_modules 存在"
            fi
        fi
    fi

    echo ""
    echo "---"

    # 寫入 log
    local log_dir="$HOME/.local/log/dotfiles"
    mkdir -p "$log_dir"
    local log_file="$log_dir/icloud-health.log"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ "$errors" -gt 0 ]]; then
        local summary="${errors} 個 symlink 異常: $(IFS=', '; echo "${failed_items[*]}")"
        echo "$timestamp FAIL $summary" >> "$log_file"
        log_err "$summary"
        echo ""
        log_info "快速修復: icloud-sync.sh apply (重建 symlink)"
        notify_health_failure "${summary}。執行 icloud-sync.sh apply 修復"
        return 1
    else
        echo "$timestamp OK 所有 symlink 正常" >> "$log_file"
        log_ok "所有 symlink 健康正常"
        return 0
    fi
}

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
        check_conflict "$HOME/.claude/hooks" "$ICLOUD_DIR/claude/hooks" "Claude hooks" || has_conflict=true
        check_conflict "$HOME/.claude/hud" "$ICLOUD_DIR/claude/hud" "Claude HUD" || has_conflict=true
        check_conflict "$HOME/.claude/CLAUDE.md" "$ICLOUD_DIR/claude/CLAUDE.md" "Claude CLAUDE.md" || has_conflict=true
        check_conflict "$HOME/.claude/.mcp.json" "$ICLOUD_DIR/claude/mcp.json" "Claude MCP config" || has_conflict=true
        check_conflict "$HOME/.codex/skills" "$ICLOUD_DIR/codex/skills" "Codex skills" || has_conflict=true
        check_conflict "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json" "Claude settings.json" || has_conflict=true
        check_conflict "$HOME/.claude-code-router/config.json" "$ICLOUD_DIR/ccr/config.json" "CCR config" || has_conflict=true
        check_conflict "$HOME/.config/opencode/oh-my-openagent.json" "$ICLOUD_DIR/opencode/oh-my-openagent.json" "OpenCode config" || has_conflict=true
        check_conflict "$HOME/.config/opencode/agent" "$ICLOUD_DIR/opencode/agent" "OpenCode agents" || has_conflict=true
        check_conflict "$HOME/.config/opencode/plugin" "$ICLOUD_DIR/opencode/plugin" "OpenCode plugin" || has_conflict=true
        check_conflict "$HOME/.config/opencode/superpowers" "$ICLOUD_DIR/opencode/superpowers" "OpenCode superpowers" || has_conflict=true
        check_conflict "$HOME/Library/Application Support/Beyond Compare 5" "$ICLOUD_DIR/bcompare5" "Beyond Compare 5" || has_conflict=true
        check_conflict "$HOME/.agents" "$ICLOUD_DIR/codex-skills" "Codex skills (agents)" || has_conflict=true

        if [[ "$has_conflict" == "true" ]]; then
            log_warn "發現衝突，capture 中止"
            exit 1
        fi
    fi

    mkdir -p "$ICLOUD_DIR"/{claude/{agents,skills,hooks,hud},codex/skills,codex-skills,ccr,opencode/{agent,plugin,superpowers},vscode,iterm2,bcompare5}

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

    # Claude Code hooks
    if [[ -d "$HOME/.claude/hooks" ]] && [[ ! -L "$HOME/.claude/hooks" ]]; then
        rsync -av --delete "$HOME/.claude/hooks/" "$ICLOUD_DIR/claude/hooks/"
        log_ok "Claude hooks → iCloud"
    fi

    # Claude Code HUD
    if [[ -d "$HOME/.claude/hud" ]] && [[ ! -L "$HOME/.claude/hud" ]]; then
        rsync -av --delete "$HOME/.claude/hud/" "$ICLOUD_DIR/claude/hud/"
        log_ok "Claude HUD → iCloud"
    fi

    # Claude Code CLAUDE.md
    if [[ -f "$HOME/.claude/CLAUDE.md" ]] && [[ ! -L "$HOME/.claude/CLAUDE.md" ]]; then
        cp "$HOME/.claude/CLAUDE.md" "$ICLOUD_DIR/claude/CLAUDE.md"
        log_ok "Claude CLAUDE.md → iCloud"
    fi

    # Claude Code MCP config
    if [[ -f "$HOME/.claude/.mcp.json" ]] && [[ ! -L "$HOME/.claude/.mcp.json" ]]; then
        cp "$HOME/.claude/.mcp.json" "$ICLOUD_DIR/claude/mcp.json"
        log_ok "Claude MCP config → iCloud"
    fi

    # Codex skills
    if [[ -d "$HOME/.codex/skills" ]] && [[ ! -L "$HOME/.codex/skills" ]]; then
        rsync -av --delete "$HOME/.codex/skills/" "$ICLOUD_DIR/codex/skills/"
        log_ok "Codex skills → iCloud"
    fi

    # Claude Code settings.json
    if [[ -f "$HOME/.claude/settings.json" ]] && [[ ! -L "$HOME/.claude/settings.json" ]]; then
        cp "$HOME/.claude/settings.json" "$ICLOUD_DIR/claude/settings.json"
        log_ok "Claude settings.json → iCloud"
    fi

    # Claude Code Router (CCR) config
    if [[ -f "$HOME/.claude-code-router/config.json" ]] && [[ ! -L "$HOME/.claude-code-router/config.json" ]]; then
        cp "$HOME/.claude-code-router/config.json" "$ICLOUD_DIR/ccr/config.json"
        log_ok "CCR config.json → iCloud"
    fi

    # OpenCode non-sensitive
    if [[ -f "$HOME/.config/opencode/oh-my-openagent.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-openagent.json" ]]; then
        cp "$HOME/.config/opencode/oh-my-openagent.json" "$ICLOUD_DIR/opencode/oh-my-openagent.json"
        log_ok "OpenCode oh-my-openagent.json → iCloud"
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

    # Beyond Compare 5
    if [[ -d "$HOME/Library/Application Support/Beyond Compare 5" ]] && [[ ! -L "$HOME/Library/Application Support/Beyond Compare 5" ]]; then
        rsync -av --delete --exclude='*.bak' --exclude='.BCLOCK' --exclude='.DS_Store' "$HOME/Library/Application Support/Beyond Compare 5/" "$ICLOUD_DIR/bcompare5/"
        log_ok "Beyond Compare 5 → iCloud"
    fi

    # Codex skills (agents)
    if [[ -d "$HOME/.agents" ]] && [[ ! -L "$HOME/.agents" ]]; then
        rsync -av --delete --exclude='.DS_Store' "$HOME/.agents/" "$ICLOUD_DIR/codex-skills/"
        log_ok "Codex skills (agents) → iCloud"
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

    # Claude hooks (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/hooks" ]]; then
        if [[ ! -L "$HOME/.claude/hooks" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.claude/hooks" ]] && log_info "[DRY-RUN] Would backup: ~/.claude/hooks → ~/.claude/hooks.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/hooks → $ICLOUD_DIR/claude/hooks"
            else
                [[ -d "$HOME/.claude/hooks" ]] && mv "$HOME/.claude/hooks" "$HOME/.claude/hooks.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/hooks" "$HOME/.claude/hooks"
                log_ok "Claude hooks ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude hooks already symlinked"
        fi
    fi

    # Claude HUD (create symlink)
    if [[ -d "$ICLOUD_DIR/claude/hud" ]]; then
        if [[ ! -L "$HOME/.claude/hud" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.claude/hud" ]] && log_info "[DRY-RUN] Would backup: ~/.claude/hud → ~/.claude/hud.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/hud → $ICLOUD_DIR/claude/hud"
            else
                [[ -d "$HOME/.claude/hud" ]] && mv "$HOME/.claude/hud" "$HOME/.claude/hud.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/hud" "$HOME/.claude/hud"
                log_ok "Claude HUD ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude HUD already symlinked"
        fi
    fi

    # Claude CLAUDE.md (create symlink)
    if [[ -f "$ICLOUD_DIR/claude/CLAUDE.md" ]]; then
        if [[ ! -L "$HOME/.claude/CLAUDE.md" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.claude/CLAUDE.md" ]] && log_info "[DRY-RUN] Would backup: CLAUDE.md → CLAUDE.md.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/CLAUDE.md → $ICLOUD_DIR/claude/CLAUDE.md"
            else
                [[ -f "$HOME/.claude/CLAUDE.md" ]] && mv "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
                log_ok "Claude CLAUDE.md ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude CLAUDE.md already symlinked"
        fi
    fi

    # Claude MCP config (create symlink)
    if [[ -f "$ICLOUD_DIR/claude/mcp.json" ]]; then
        if [[ ! -L "$HOME/.claude/.mcp.json" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.claude/.mcp.json" ]] && log_info "[DRY-RUN] Would backup: .mcp.json → .mcp.json.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/.mcp.json → $ICLOUD_DIR/claude/mcp.json"
            else
                [[ -f "$HOME/.claude/.mcp.json" ]] && mv "$HOME/.claude/.mcp.json" "$HOME/.claude/.mcp.json.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/mcp.json" "$HOME/.claude/.mcp.json"
                log_ok "Claude MCP config ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude MCP config already symlinked"
        fi
    fi

    # Claude settings.json (create symlink)
    if [[ -f "$ICLOUD_DIR/claude/settings.json" ]]; then
        if [[ ! -L "$HOME/.claude/settings.json" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.claude/settings.json" ]] && log_info "[DRY-RUN] Would backup: settings.json → settings.json.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.claude/settings.json → $ICLOUD_DIR/claude/settings.json"
            else
                [[ -f "$HOME/.claude/settings.json" ]] && mv "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/claude/settings.json" "$HOME/.claude/settings.json"
                log_ok "Claude settings.json ← iCloud (symlinked)"
            fi
        else
            log_ok "Claude settings.json already symlinked"
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

        if [[ -f "$ICLOUD_DIR/opencode/oh-my-openagent.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-openagent.json" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -f "$HOME/.config/opencode/oh-my-openagent.json" ]] && log_info "[DRY-RUN] Would backup: oh-my-openagent.json → oh-my-openagent.json.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.config/opencode/oh-my-openagent.json → $ICLOUD_DIR/opencode/oh-my-openagent.json"
            else
                [[ -f "$HOME/.config/opencode/oh-my-openagent.json" ]] && mv "$HOME/.config/opencode/oh-my-openagent.json" "$HOME/.config/opencode/oh-my-openagent.json.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/opencode/oh-my-openagent.json" "$HOME/.config/opencode/oh-my-openagent.json"
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

    # Beyond Compare 5 (create symlink)
    if [[ -d "$ICLOUD_DIR/bcompare5" ]]; then
        if [[ ! -L "$HOME/Library/Application Support/Beyond Compare 5" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/Library/Application Support/Beyond Compare 5" ]] && log_info "[DRY-RUN] Would backup: Beyond Compare 5 → Beyond Compare 5.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/Library/Application Support/Beyond Compare 5 → $ICLOUD_DIR/bcompare5"
            else
                [[ -d "$HOME/Library/Application Support/Beyond Compare 5" ]] && mv "$HOME/Library/Application Support/Beyond Compare 5" "$HOME/Library/Application Support/Beyond Compare 5.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/bcompare5" "$HOME/Library/Application Support/Beyond Compare 5"
                log_ok "Beyond Compare 5 ← iCloud (symlinked)"
            fi
        else
            log_ok "Beyond Compare 5 already symlinked"
        fi
    fi

    # Codex skills (agents) (create symlink)
    if [[ -d "$ICLOUD_DIR/codex-skills" ]]; then
        if [[ ! -L "$HOME/.agents" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                [[ -d "$HOME/.agents" ]] && log_info "[DRY-RUN] Would backup: .agents → .agents.backup.TIMESTAMP"
                log_info "[DRY-RUN] Would symlink: ~/.agents → $ICLOUD_DIR/codex-skills"
            else
                [[ -d "$HOME/.agents" ]] && mv "$HOME/.agents" "$HOME/.agents.backup.$(date +%s)"
                ln -sf "$ICLOUD_DIR/codex-skills" "$HOME/.agents"
                log_ok "Codex skills (agents) ← iCloud (symlinked)"
            fi
        else
            log_ok "Codex skills (agents) already symlinked"
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

    # OpenCode superpowers node_modules 依賴修復
    if [[ -d "$ICLOUD_DIR/opencode/superpowers/.opencode/plugin" ]]; then
        if [[ ! -e "$ICLOUD_DIR/opencode/superpowers/.opencode/node_modules" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY-RUN] Would symlink: superpowers node_modules → ~/.config/opencode/node_modules"
            else
                if [[ -d "$HOME/.config/opencode/node_modules" ]]; then
                    ln -sf "$HOME/.config/opencode/node_modules" \
                        "$ICLOUD_DIR/opencode/superpowers/.opencode/node_modules"
                    log_ok "OpenCode superpowers node_modules ← local (symlinked)"
                else
                    log_warn "OpenCode node_modules 不存在，跳過 superpowers 依賴修復"
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_ok "[DRY-RUN] Apply preview complete!"
    else
        log_ok "Apply complete!"

        # Apply 後自動執行健康檢查
        echo ""
        health || true
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

    # Claude hooks
    if [[ -d "$HOME/.claude/hooks" ]] && [[ ! -L "$HOME/.claude/hooks" ]]; then
        if [[ -d "$ICLOUD_DIR/claude/hooks" ]]; then
            echo ""
            log_info "Claude hooks:"
            if diff -rq "$HOME/.claude/hooks" "$ICLOUD_DIR/claude/hooks" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Claude HUD
    if [[ -d "$HOME/.claude/hud" ]] && [[ ! -L "$HOME/.claude/hud" ]]; then
        if [[ -d "$ICLOUD_DIR/claude/hud" ]]; then
            echo ""
            log_info "Claude HUD:"
            if diff -rq "$HOME/.claude/hud" "$ICLOUD_DIR/claude/hud" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Claude CLAUDE.md
    if [[ -f "$HOME/.claude/CLAUDE.md" ]] && [[ ! -L "$HOME/.claude/CLAUDE.md" ]]; then
        if [[ -f "$ICLOUD_DIR/claude/CLAUDE.md" ]]; then
            echo ""
            log_info "Claude CLAUDE.md:"
            if diff -q "$HOME/.claude/CLAUDE.md" "$ICLOUD_DIR/claude/CLAUDE.md" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
            fi
        fi
    fi

    # Claude MCP config
    if [[ -f "$HOME/.claude/.mcp.json" ]] && [[ ! -L "$HOME/.claude/.mcp.json" ]]; then
        if [[ -f "$ICLOUD_DIR/claude/mcp.json" ]]; then
            echo ""
            log_info "Claude MCP config:"
            if diff -q "$HOME/.claude/.mcp.json" "$ICLOUD_DIR/claude/mcp.json" 2>/dev/null; then
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
    if [[ -f "$HOME/.claude/settings.json" ]] && [[ ! -L "$HOME/.claude/settings.json" ]]; then
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
    if [[ -f "$HOME/.config/opencode/oh-my-openagent.json" ]] && [[ ! -L "$HOME/.config/opencode/oh-my-openagent.json" ]]; then
        if [[ -f "$ICLOUD_DIR/opencode/oh-my-openagent.json" ]]; then
            echo ""
            log_info "OpenCode oh-my-openagent.json:"
            if diff -q "$HOME/.config/opencode/oh-my-openagent.json" "$ICLOUD_DIR/opencode/oh-my-openagent.json" 2>/dev/null; then
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

    # Beyond Compare 5
    if [[ -d "$HOME/Library/Application Support/Beyond Compare 5" ]] && [[ ! -L "$HOME/Library/Application Support/Beyond Compare 5" ]]; then
        if [[ -d "$ICLOUD_DIR/bcompare5" ]]; then
            echo ""
            log_info "Beyond Compare 5:"
            if diff -rq "$HOME/Library/Application Support/Beyond Compare 5" "$ICLOUD_DIR/bcompare5" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
                diff -rq "$HOME/Library/Application Support/Beyond Compare 5" "$ICLOUD_DIR/bcompare5" 2>/dev/null | head -20 | sed 's/^/  /'
            fi
        fi
    fi

    # Codex skills (agents)
    if [[ -d "$HOME/.agents" ]] && [[ ! -L "$HOME/.agents" ]]; then
        if [[ -d "$ICLOUD_DIR/codex-skills" ]]; then
            echo ""
            log_info "Codex skills (agents):"
            if diff -rq "$HOME/.agents" "$ICLOUD_DIR/codex-skills" 2>/dev/null; then
                echo "  (identical)"
            else
                has_diff=true
                diff -rq "$HOME/.agents" "$ICLOUD_DIR/codex-skills" 2>/dev/null | head -20 | sed 's/^/  /'
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

# ===== Status: 顯示同步狀態（含健康檢查）=====
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

    [[ -f "$ICLOUD_DIR/opencode/oh-my-openagent.json" ]] && \
        log_info "OpenCode oh-my-openagent.json"

    [[ -d "$ICLOUD_DIR/opencode/agent" ]] && \
        log_info "OpenCode agents/ ($(ls "$ICLOUD_DIR/opencode/agent" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/opencode/plugin" ]] && \
        log_info "OpenCode plugin/ ($(ls "$ICLOUD_DIR/opencode/plugin" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/opencode/superpowers" ]] && \
        log_info "OpenCode superpowers/ ($(ls "$ICLOUD_DIR/opencode/superpowers" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/bcompare5" ]] && \
        log_info "Beyond Compare 5/ ($(ls "$ICLOUD_DIR/bcompare5" 2>/dev/null | wc -l | tr -d ' ') files)"

    [[ -d "$ICLOUD_DIR/codex-skills" ]] && \
        log_info "Codex skills (agents)/ ($(ls "$ICLOUD_DIR/codex-skills" 2>/dev/null | wc -l | tr -d ' ') files)"

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

    # 使用統一註冊表做深度檢查
    for entry in "${SYMLINK_REGISTRY[@]}"; do
        IFS='|' read -r path type name <<< "$entry"
        local display_path="${path/#$HOME/~}"
        if [[ -L "$path" ]]; then
            if [[ ! -e "$path" ]]; then
                log_err "$display_path → iCloud (斷鏈!)"
            elif [[ "$type" == "dir" && -z "$(ls -A "$path" 2>/dev/null)" ]]; then
                log_warn "$display_path → iCloud (目標為空)"
            elif [[ "$type" == "file" && ! -s "$path" ]]; then
                log_warn "$display_path → iCloud (檔案為空)"
            else
                log_ok "$display_path → iCloud"
            fi
        elif [[ -e "$path" ]]; then
            log_warn "$display_path (not symlinked)"
        fi
    done

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
    health)   health ;;
    *)
        echo "Usage: icloud-sync.sh [command] [options]"
        echo ""
        echo "Commands:"
        echo "  capture [--force]      — 將本地設定同步到 iCloud"
        echo "  apply [-n|--dry-run]   — 從 iCloud 同步設定到本地"
        echo "  diff                   — 顯示本地與 iCloud 的差異"
        echo "  status                 — 顯示同步狀態"
        echo "  health                 — 深度健康檢查（驗證 symlink 目標可用性）"
        echo ""
        echo "Options:"
        echo "  --force         (capture) 強制覆蓋，即使 iCloud 版本較新"
        echo "  -n, --dry-run   (apply) 預覽變更而不實際執行"
        exit 1
        ;;
esac
