# macos-dotfiles-nexus

macOS 開發環境同步中樞 — chezmoi + iCloud + Bitwarden 三層混合架構。

## 快速開始

### 新機器一鍵安裝

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/weiting-tw/macos-dotfiles-nexus/main/install.sh)
```

安裝後設定 secrets：

```bash
cp ~/.secrets.example ~/.secrets
chmod 600 ~/.secrets
vim ~/.secrets        # 填入 API keys
source ~/.zshrc
```

## 架構

```
chezmoi (Git)          iCloud Drive              Bitwarden
├── dotfiles           ├── Claude agents/skills  ├── GPG private keys
├── .gitconfig         ├── Claude hooks/HUD      ├── SSH private keys
├── .zshrc             ├── CLAUDE.md, .mcp.json  └── API keys
├── Brewfile           ├── Codex skills
├── SSH config         ├── Claude Code Router
├── macOS defaults     ├── OpenCode config
├── GPG setup          ├── VS Code extensions
├── LaunchAgents       └── iTerm2 preferences
└── AI tool templates
```

| 層級 | 用途 | 原因 |
|------|------|------|
| chezmoi (Git) | dotfiles 版本控制、GPG 設定、LaunchAgents | 穩定、需追蹤變更歷史、多機器同步 |
| iCloud Drive | Claude/Codex agents、設定檔、IDE 偏好設定 | 即時同步，不需每次 commit，跨機器最新 |
| Bitwarden | GPG/SSH 私鑰、API keys | 機敏資料不能存在任何 repo |

### 已有機器更新

```bash
chezmoi update              # 從 Git 拉取 + 套用變更
```

如果遇到歷史不一致（force push 後）：

```bash
cd ~/.local/share/chezmoi && git fetch origin && git reset --hard origin/main && chezmoi apply
```

如果需要重新跑 setup scripts（如 GPG 匯入）：

```bash
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

### 常用指令（Makefile）

```bash
make              # 顯示所有可用指令
make bootstrap    # 首次安裝（完整設定）
make apply        # 套用 chezmoi 設定到本機
make update       # 從 Git 拉取並套用
make diff         # 顯示本機與 chezmoi 設定差異
make status       # 顯示 chezmoi 狀態
make edit         # 開啟 chezmoi source 目錄
make doctor       # 檢查 chezmoi 健康狀態
make icloud-capture  # 本地設定 → iCloud
make icloud-apply    # iCloud 設定 → 本地
make icloud-status   # 顯示 iCloud 同步狀態
make icloud-health   # iCloud symlink 深度健康檢查
make lint         # 執行 shellcheck 檢查腳本
```

## iCloud 同步

13 個設定項目透過 symlink 在本地與 iCloud 同步，每 6 小時自動備份，每 2 小時進行健康檢查。

| 項目 | 位置 | 類型 |
|------|------|------|
| Claude agents | `~/.claude/agents` | dir |
| Claude skills | `~/.claude/skills` | dir |
| Claude hooks | `~/.claude/hooks` | dir |
| Claude HUD | `~/.claude/hud` | dir |
| CLAUDE.md | `~/.claude/CLAUDE.md` | file |
| Claude MCP config | `~/.claude/.mcp.json` | file |
| Claude settings.json | `~/.claude/settings.json` | file |
| Codex skills | `~/.codex/skills` | dir |
| Claude Code Router | `~/.claude-code-router/config.json` | file |
| OpenCode config | `~/.config/opencode/oh-my-opencode.json` | file |
| OpenCode agents | `~/.config/opencode/agent` | dir |
| OpenCode plugins | `~/.config/opencode/plugin` | dir |
| OpenCode superpowers | `~/.config/opencode/superpowers` | dir |

**iCloud 同步指令：**

```bash
make icloud-capture   # 推送本地設定 → iCloud
make icloud-apply     # 從 iCloud 拉取設定到本地
make icloud-status    # 顯示 iCloud 檔案清單與 symlink 狀態
make icloud-health    # 深度檢查：symlink 連結、iCloud 下載狀態、內容有效性
```

**自動排程：**
- `icloud-capture` 每 6 小時執行一次（LocalAugents: `com.user.icloud-capture`）
- `icloud-health` 每 2 小時執行一次，發現異常時發送 macOS 通知

## LaunchAgents（自動排程）

三個後台 agent 在登入時自動啟動，定期同步設定、檢查健康狀態。

| Agent | 間隔 | 目的 | 日誌 |
|-------|------|------|------|
| `com.user.chezmoi-update` | 12 小時 | Git pull → chezmoi apply | `~/.local/log/dotfiles/chezmoi-update.{out,err}.log` |
| `com.user.icloud-capture` | 6 小時 | 本地設定 → iCloud 備份 | `~/.local/log/dotfiles/icloud-capture.{out,err}.log` |
| `com.user.icloud-health` | 2 小時 | Symlink 健康檢查 + macOS 通知 | `~/.local/log/dotfiles/icloud-health.log` |
| `com.user.gpg-agent` | 登入時 | GPG agent 自動啟動 | `~/.local/log/dotfiles/gpg-agent.{out,err}.log` |

**檢查排程狀態：**

```bash
launchctl list | grep com.user
```

**手動觸發：**

```bash
launchctl start com.user.icloud-capture
launchctl start com.user.chezmoi-update
```

## GPG 簽名

GPG 簽名密鑰存放在 Bitwarden，bootstrap 時自動檢測並引導匯入。

**設定 GPG keys（每台機器）：**

在 `~/.config/chezmoi/chezmoi.toml` 加入：

```toml
[data.git]
    signing_key = "YOUR_KEY_ID"

[[data.gpg.keys]]
    id = "YOUR_KEY_ID"
    name = "Your Name"
    purpose = "work"

[[data.gpg.keys]]
    id = "ANOTHER_KEY_ID"
    name = "Personal"
    purpose = "personal"
```

**設定 Bitwarden（可選，在 `~/.secrets`）：**

```bash
export BW_SERVER=""            # Self-hosted URL（留空 = 互動式選擇）
export BW_CLIENTID=""          # 免互動登入用，可留空
export BW_CLIENTSECRET=""      # 免互動登入用，可留空
export BW_GPG_ITEM_NAME=""     # Bitwarden item 名稱（留空 = 搜尋 "GPG"）
```

**自動設定流程（Bootstrap 時）：**

`06-setup-gpg.sh` 在首次安裝時自動執行：

1. 檢測本機是否已有 GPG key（依據 `chezmoi.toml` 設定）
2. 詢問是否要設定 GPG
3. 有 `BW_SERVER` → 自動使用；沒有 → 互動式選擇（官方 / 自架）
4. 有 `BW_CLIENTID` → API key 自動登入；沒有 → 互動式帳密 + 2FA
5. 搜尋 Bitwarden 附件 → 下載 `.asc` → 匯入 → 設定信任等級

**手動匯入（不使用 Bitwarden CLI）：**

```bash
gpg --import work.asc && gpg --import work-public.asc
gpg --edit-key YOUR_KEY_ID trust    # 選擇 5 (ultimate)
```

**條件簽名：** `gpgsign = true` 僅在 `chezmoi.toml` 有設定 `signing_key` 時才啟用。

**設定檔層級：**

| 檔案 | 版控 | 用途 |
|------|------|------|
| `.chezmoidata.yaml` | Git | 預設值（`gpg.keys` 為空） |
| `~/.config/chezmoi/chezmoi.toml` | 本機 | 每台機器的 GPG key 設定 |
| `~/.secrets` | 本機 | Bitwarden 連線資訊（可選） |

## Codex MCP Wrapper

`~/.codex-mcp/config.toml` 為 Codex MCP wrapper 的獨立設定，與主 `~/.codex/config.toml` 分離。

**用途：** 避免 wrapper 載入 MCP servers 時的 model detection 超時（5 秒）。

**結構：**

```
~/.codex/config.toml            # 主設定（包含 MCP servers）
~/.codex-mcp/config.toml        # Wrapper 專用設定（無 MCP servers）
```

## 設定腳本

Bootstrap 時自動執行的設定腳本，檢查並初始化各項系統設定。

| 腳本 | 執行時機 | 功能 |
|------|--------|------|
| `04-setup-git-identity.sh` | 首次安裝 | 建立 `~/work` 和 `~/personal` 目錄，連結多身份 git config |
| `05-setup-ssh.sh` | 首次安裝 | 檢測 Bitwarden SSH Agent，引導設定 |
| `06-setup-gpg.sh` | 首次安裝 | 檢測 GPG 密鑰，缺少時提示從 Bitwarden 匯入 |
| `09-setup-launchd.sh` | 首次安裝 | 安裝所有 LaunchAgents 到 `~/Library/LaunchAgents/` |

## AI 工具設定

### OpenCode

OpenCode 設定檔位於 `~/.config/opencode/opencode.json`，由 chezmoi template 產生。

**Model 設定**：常用 model 已預設在 template 中（Antigravity、Gemini CLI 系列）。

調整 model：

```bash
chezmoi edit ~/.config/opencode/opencode.json   # 編輯 template
chezmoi apply                                    # 套用變更
```

**動態 Provider**：額外的 provider（如 Azure）可透過 `~/.opencode-providers.json` 載入，不需修改 template：

```json
{
  "azure": {
    "models": {
      "my-model": {
        "name": "My Azure Model",
        "limit": { "context": 128000, "output": 4096 },
        "modalities": { "input": ["text"], "output": ["text"] }
      }
    }
  }
}
```

### Codex (OpenAI)

設定檔位於 `~/.codex/config.toml`。需要 `AZURE_OPENAI_ENDPOINT` 環境變數（定義在 `~/.secrets`）。

### Secrets

所有 API key 集中在 `~/.secrets`，bootstrap 時會自動從 `~/.secrets.example` 複製。需手動填入：

| 變數 | 用途 |
|------|------|
| `PERPLEXITY_API_KEY` | Perplexity MCP |
| `CONTEXT7_API_KEY` | Context7 MCP |
| `AZURE_OPENAI_ENDPOINT` | Codex Azure Provider |
| `OPENAI_API_KEY_app_mfv8vy68` | Codex Azure API Key |
| `GPG_SIGNING_KEY` | Git commit 簽名密鑰 ID |

## License

MIT
