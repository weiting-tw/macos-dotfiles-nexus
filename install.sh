#!/bin/bash
# shellcheck disable=SC2088
# ============================================================
# macOS Bootstrap — chezmoi + iCloud 混合架構
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/weiting-tw/macos-dotfiles-nexus/main/install.sh | bash
#   或
#   bash install.sh [--chezmoi-only] [--icloud-only] [--help]
# ============================================================
set -euo pipefail

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_ok()    { echo -e "${GREEN}✓${NC} $1"; }
log_info()  { echo -e "${BLUE}ℹ${NC} $1"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_title() { echo -e "\n${BOLD}$1${NC}"; }

# ===== 參數解析 =====
CHEZMOI_ONLY=false
ICLOUD_ONLY=false
REPO_URL="${DOTFILES_REPO:-https://github.com/weiting-tw/macos-dotfiles-nexus.git}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --chezmoi-only) CHEZMOI_ONLY=true; shift ;;
        --icloud-only)  ICLOUD_ONLY=true; shift ;;
        --repo)         REPO_URL="$2"; shift 2 ;;
        --help|-h)
            echo "macOS Bootstrap — chezmoi + iCloud 混合架構"
            echo ""
            echo "用法: install.sh [選項]"
            echo ""
            echo "選項:"
            echo "  --chezmoi-only    只執行 chezmoi（dotfiles、packages、system config）"
            echo "  --icloud-only     只設定 iCloud 同步（AI tools、extensions）"
            echo "  --repo URL        指定 dotfiles git repo URL"
            echo "  --help, -h        顯示此說明"
            echo ""
            echo "預設行為: 執行完整 bootstrap（chezmoi + iCloud）"
            exit 0
            ;;
        *) log_error "未知選項: $1"; exit 1 ;;
    esac
done

# ===== macOS 檢查 =====
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "此腳本僅支援 macOS"
    exit 1
fi

log_title "🖥  macOS Bootstrap — chezmoi + iCloud"
echo "Repository: $REPO_URL"
echo ""

# 不主動要 sudo：整個流程皆為使用者層操作；
# 唯一例外是 Homebrew 首次安裝（官方安裝器需要管理員權限，會自行提示）

# ===== Step 1: Xcode Command Line Tools =====
if [[ "$ICLOUD_ONLY" != true ]]; then
    log_title "Step 1: Xcode Command Line Tools"
    if xcode-select -p &>/dev/null; then
        log_ok "已安裝"
    else
        log_info "安裝中..."
        xcode-select --install
        until xcode-select -p &>/dev/null; do sleep 5; done
        log_ok "安裝完成"
    fi
fi

# ===== Step 2: Homebrew =====
if [[ "$ICLOUD_ONLY" != true ]]; then
    log_title "Step 2: Homebrew"
    if command -v brew &>/dev/null; then
        log_ok "已安裝"
    else
        log_info "安裝中..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Apple Silicon PATH
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        log_ok "安裝完成"
    fi
fi

# ===== Step 3: chezmoi =====
if [[ "$ICLOUD_ONLY" != true ]]; then
    log_title "Step 3: chezmoi"
    if command -v chezmoi &>/dev/null; then
        log_ok "已安裝"
    else
        log_info "安裝中..."
        brew install chezmoi
        log_ok "安裝完成"
    fi

    # ===== Step 4: Initialize + Apply chezmoi =====
    log_title "Step 4: chezmoi init + apply"

    # 判斷腳本是否在本地 repo 中執行
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    if [[ -f "$SCRIPT_DIR/.chezmoi.toml.tmpl" ]]; then
        # 本地執行：使用 --source 直接連結至此目錄（不複製）
        log_info "偵測到本地 repo: $SCRIPT_DIR"
        chezmoi init --source "$SCRIPT_DIR" --prompt
    else
        # 遠端執行：標準 chezmoi init
        log_info "未偵測到本地 repo，從遠端初始化..."
        chezmoi init --prompt "$REPO_URL" --branch main
    fi

    # ===== Secrets 設定（在 apply 前載入，確保 template 能正確渲染）=====
    if [[ ! -f "$HOME/.secrets" ]] && [[ -f "$HOME/.secrets.example" ]]; then
        log_info "從範本建立 ~/.secrets..."
        cp "$HOME/.secrets.example" "$HOME/.secrets"
        chmod 600 "$HOME/.secrets"
        log_warn "請之後編輯 ~/.secrets 填入 API keys"
    fi
    if [[ -f "$HOME/.secrets" ]]; then
        set -a
        source "$HOME/.secrets"
        set +a
        log_ok "已載入 ~/.secrets 環境變數"
    fi

    # 現在執行 apply，template 能正確取得 env 變數
    chezmoi apply

    log_ok "chezmoi 設定完成"
fi

# ===== Step 5: Secrets 確認 =====
if [[ "$ICLOUD_ONLY" != true ]]; then
    log_title "Step 5: Secrets"
    if [[ -f "$HOME/.secrets" ]]; then
        log_ok "~/.secrets 已存在"
    else
        log_warn "~/.secrets 不存在，部分設定可能未正確渲染"
        log_info "請參考 README 建立 ~/.secrets，然後執行 chezmoi apply"
    fi
fi

# ===== Step 6: iCloud 同步 =====
if [[ "$CHEZMOI_ONLY" != true ]]; then
    log_title "Step 6: iCloud 同步設定"

    ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles-shared"
    CHEZMOI_SOURCE="$(chezmoi source-path 2>/dev/null || echo "")"

    if [[ -d "$ICLOUD_DIR" ]]; then
        log_ok "iCloud 同步目錄已存在"

        # Apply iCloud configs
        if [[ -n "$CHEZMOI_SOURCE" ]] && [[ -f "$CHEZMOI_SOURCE/scripts/icloud-sync.sh" ]]; then
            bash "$CHEZMOI_SOURCE/scripts/icloud-sync.sh" apply
        fi
    else
        log_info "建立 iCloud 同步目錄..."
        mkdir -p "$ICLOUD_DIR"/{claude/agents,opencode/agent,vscode}

        # Seed from repo if this is first machine
        if [[ -n "$CHEZMOI_SOURCE" ]] && [[ -f "$CHEZMOI_SOURCE/scripts/seed-icloud.sh" ]]; then
            log_info "首次設定，從 repo 初始化 iCloud 資料..."
            bash "$CHEZMOI_SOURCE/scripts/seed-icloud.sh"
        fi

        log_ok "iCloud 同步目錄已建立"
    fi
fi

# ===== 安裝摘要 =====
echo ""
log_title "📋 安裝摘要"
echo ""

# 檢查各項目狀態
check_installed() {
    local name="$1"
    local check="$2"
    if eval "$check" &>/dev/null; then
        log_ok "$name"
        return 0
    else
        log_warn "$name（未安裝）"
        return 1
    fi
}

echo "系統工具："
check_installed "Xcode CLI Tools" "xcode-select -p"
check_installed "Homebrew" "command -v brew"
check_installed "chezmoi" "command -v chezmoi"

echo ""
echo "CLI 工具："
check_installed "git" "command -v git"
check_installed "fzf" "command -v fzf"
check_installed "ripgrep (rg)" "command -v rg"
check_installed "bat" "command -v bat"
check_installed "eza" "command -v eza"
check_installed "jq" "command -v jq"
check_installed "zoxide" "command -v zoxide"

echo ""
echo "開發工具："
check_installed "Node.js" "command -v node"
check_installed "Python" "command -v python3"
check_installed "asdf/mise" "command -v asdf || command -v mise"

echo ""
echo "應用程式："
check_installed "iTerm2" "[[ -d '/Applications/iTerm.app' || -d ~/Applications/iTerm.app ]]"
check_installed "VS Code" "[[ -d '/Applications/Visual Studio Code.app' || -d ~/Applications/Visual\\ Studio\\ Code.app ]]"
check_installed "Bitwarden" "[[ -d '/Applications/Bitwarden.app' || -d ~/Applications/Bitwarden.app ]]"

echo ""
echo "設定檔案："
check_installed "~/.zshrc" "[[ -f ~/.zshrc ]]"
check_installed "~/.gitconfig" "[[ -f ~/.gitconfig ]]"
[[ -f ~/.secrets ]] && log_ok "~/.secrets" || log_warn "~/.secrets（需要手動建立）"

# ===== 完成 =====
echo ""
log_title "✅ Bootstrap 完成！"
echo ""
echo "接下來："
echo "  1. 編輯 ~/.secrets 填入 API keys"
echo "  2. 重新開啟終端機讓設定生效"
echo "  3. 執行 'chezmoi apply' 重新渲染含 secrets 的 template"
echo ""
echo "日常操作："
echo "  chezmoi edit ~/.zshrc       — 編輯 dotfile"
echo "  chezmoi apply               — 套用變更"
echo "  chezmoi update              — 從 git 拉取並套用"
echo "  chezmoi diff                — 預覽變更"
echo ""
