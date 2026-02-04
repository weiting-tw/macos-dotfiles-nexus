#!/bin/bash
# shellcheck disable=SC2088
# ============================================================
# macOS Bootstrap — chezmoi + iCloud 混合架構
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/weiting-tw/macos-dotfiles-nexus/main/chezmoi/install.sh | bash
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

# ===== sudo keep-alive =====
log_info "需要管理員權限（用於 Homebrew、macOS defaults 等）"
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &

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
    LOCAL_CHEZMOI=""

    # 情況 1: install.sh 在 chezmoi/ 目錄內（直接執行 repo 裡的 install.sh）
    if [[ -f "$SCRIPT_DIR/.chezmoi.toml.tmpl" ]]; then
        LOCAL_CHEZMOI="$SCRIPT_DIR"
    # 情況 2: install.sh 在 repo 根目錄，chezmoi/ 是子目錄
    elif [[ -d "$SCRIPT_DIR/chezmoi" && -f "$SCRIPT_DIR/chezmoi/.chezmoi.toml.tmpl" ]]; then
        LOCAL_CHEZMOI="$SCRIPT_DIR/chezmoi"
    fi

    if [[ -n "$LOCAL_CHEZMOI" ]]; then
        log_info "偵測到本地 repo: $LOCAL_CHEZMOI"
        log_info "使用 --source 直接連結至此目錄（不複製）"
        chezmoi init --source "$LOCAL_CHEZMOI" --apply
    else
        log_info "未偵測到本地 repo，從遠端初始化..."
        chezmoi init --apply "$REPO_URL" --branch main
    fi

    log_ok "chezmoi 設定完成"
fi

# ===== Step 5: Secrets 設定 =====
if [[ "$ICLOUD_ONLY" != true ]]; then
    log_title "Step 5: Secrets"
    if [[ -f "$HOME/.secrets" ]]; then
        log_ok "~/.secrets 已存在"
    else
        log_warn "~/.secrets 不存在"
        if [[ -f "$HOME/.secrets.example" ]]; then
            log_info "從範本建立..."
            cp "$HOME/.secrets.example" "$HOME/.secrets"
            chmod 600 "$HOME/.secrets"
            log_warn "請編輯 ~/.secrets 填入 API keys"
            log_info "  vim ~/.secrets"
        else
            log_info "請參考 README 建立 ~/.secrets"
        fi
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
echo "  icloud-sync.sh capture      — 手動同步到 iCloud"
echo "  icloud-sync.sh apply        — 從 iCloud 同步到本地"
echo ""
