#!/usr/bin/env bash
# sync-mcp.sh — 把 iCloud 上的 mcp.json 模板渲染後合併進 ~/.claude.json
#
# 流程:
#   iCloud mcp.json (含 ${VAR}) → envsubst (讀 ~/.secrets) → jq merge 進 ~/.claude.json
#
# 用法:
#   scripts/sync-mcp.sh          # 執行同步
#   scripts/sync-mcp.sh --dry    # 只印出會產生的結果
#   scripts/sync-mcp.sh --diff   # 顯示與現況差異

set -euo pipefail

ICLOUD_MCP="$HOME/Library/Mobile Documents/com~apple~CloudDocs/dotfiles-shared/claude/mcp.json"
CLAUDE_JSON="$HOME/.claude.json"
SECRETS_FILE="$HOME/.secrets"
BACKUP_DIR="$HOME/.claude/backups"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}✓${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*" >&2; }
log_err()  { echo -e "${RED}✗${NC} $*" >&2; }
log_info() { echo -e "${BLUE}ℹ${NC} $*" >&2; }

MODE="apply"
case "${1:-}" in
    --dry)  MODE="dry" ;;
    --diff) MODE="diff" ;;
    "") ;;
    *) log_err "未知參數: $1"; exit 2 ;;
esac

# ===== 前置檢查 =====
for bin in jq envsubst; do
    command -v "$bin" >/dev/null || { log_err "缺少 $bin (brew install jq gettext)"; exit 1; }
done
[[ -f "$ICLOUD_MCP" ]]   || { log_err "iCloud 模板不存在: $ICLOUD_MCP"; exit 1; }
[[ -f "$CLAUDE_JSON" ]]  || { log_err "~/.claude.json 不存在 (請先啟動 Claude Code 一次)"; exit 1; }

# ===== 載入 secrets =====
if [[ -f "$SECRETS_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$SECRETS_FILE"; set +a
    log_info "已載入 $SECRETS_FILE"
else
    log_warn "$SECRETS_FILE 不存在，${VAR} 將展開為空字串"
fi

# ===== 渲染模板 =====
# 先收集模板中實際出現的變數名稱，再用 envsubst 限定展開（避免誤展開不相關字串）
VARS_IN_TEMPLATE=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$ICLOUD_MCP" | sort -u | tr '\n' ' ')
log_info "模板需要的變數: ${VARS_IN_TEMPLATE:-（無）}"

RENDERED=$(envsubst "$VARS_IN_TEMPLATE" < "$ICLOUD_MCP")

# 驗證是 JSON
if ! echo "$RENDERED" | jq empty 2>/dev/null; then
    log_err "渲染後非合法 JSON，請檢查模板"
    exit 1
fi

# ===== pencil 條件式略過 =====
if [[ ! -d /Applications/Pencil.app ]]; then
    RENDERED=$(echo "$RENDERED" | jq 'del(.mcpServers.pencil)')
    log_warn "Pencil.app 不存在，略過 pencil MCP"
fi

# ===== dry-run =====
if [[ "$MODE" == "dry" ]]; then
    echo "$RENDERED" | jq .
    exit 0
fi

# ===== diff 模式 =====
CURRENT_MCP=$(jq '{mcpServers: (.mcpServers // {})}' "$CLAUDE_JSON")
NEW_MCP=$(echo "$RENDERED" | jq '{mcpServers: .mcpServers}')

if [[ "$MODE" == "diff" ]]; then
    diff <(echo "$CURRENT_MCP" | jq --sort-keys .) <(echo "$NEW_MCP" | jq --sort-keys .) || true
    exit 0
fi

# ===== apply：若無變化則跳過 =====
if [[ "$(echo "$CURRENT_MCP" | jq --sort-keys .)" == "$(echo "$NEW_MCP" | jq --sort-keys .)" ]]; then
    log_ok "mcpServers 已是最新，無需更新"
    exit 0
fi

# ===== 備份 =====
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/claude.json.$(date +%Y%m%d-%H%M%S)"
cp "$CLAUDE_JSON" "$BACKUP_FILE"
log_info "已備份: $BACKUP_FILE"

# ===== 寫入 =====
TMP=$(mktemp)
jq --argjson new "$NEW_MCP" '.mcpServers = $new.mcpServers' "$CLAUDE_JSON" > "$TMP"
# 驗證一下
jq empty "$TMP"
mv "$TMP" "$CLAUDE_JSON"
chmod 600 "$CLAUDE_JSON"

COUNT=$(echo "$NEW_MCP" | jq '.mcpServers | length')
log_ok "已更新 ~/.claude.json（$COUNT 個 MCP servers）"

# 檢查有沒有變數沒被設到（渲染後出現空字串 env）
EMPTY_VARS=$(echo "$NEW_MCP" | jq -r '
  .mcpServers | to_entries[] |
  . as $s |
  (.value.env // {}) + (.value.headers // {}) |
  to_entries[] | select(.value == "") |
  "\($s.key): \(.key)"
')
if [[ -n "$EMPTY_VARS" ]]; then
    log_warn "以下欄位為空（~/.secrets 可能缺 export）:"
    echo "$EMPTY_VARS" | sed 's/^/    /'
fi
