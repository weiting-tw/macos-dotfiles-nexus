# macOS Bootstrap — chezmoi + iCloud 混合架構

自動化 macOS 開發環境設定，支援多機器同步與團隊共用。

## 架構概覽

```
┌─────────────────────────────────────────────────────────┐
│                    分層同步策略                           │
├──────────────┬──────────────────┬───────────────────────┤
│  chezmoi     │  iCloud Drive    │  Bitwarden           │
│  (Git)       │  (雲端即時同步)   │  (密鑰管理)           │
├──────────────┼──────────────────┼───────────────────────┤
│ • dotfiles   │ • AI agents      │ • SSH private keys   │
│ • .gitconfig │ • AI skills      │ • API keys           │
│ • .zshrc     │ • MCP configs    │ • tokens             │
│ • Brewfile   │ • VS Code exts   │                      │
│ • SSH config │ • iTerm2 prefs   │                      │
│ • macOS      │ • OpenCode       │                      │
│   defaults   │   plugins        │                      │
│ • GPG config │ • Brewfile       │                      │
│              │   snapshot       │                      │
└──────────────┴──────────────────┴───────────────────────┘
```

### 為什麼用混合架構？

| 需求 | 解法 | 原因 |
|------|------|------|
| dotfiles 版本控制 | chezmoi (Git) | 穩定、需追蹤變更歷史 |
| 機敏資料保護 | Bitwarden | SSH 私鑰、API keys 不能存在任何 repo |
| AI tools 頻繁變動 | iCloud Drive | MCP configs、agents 經常調整，不想每次 commit |
| 多機器同步 | chezmoi update + iCloud | 穩定設定走 Git pull，頻繁設定走雲端即時同步 |
| 團隊共用 | iCloud 共享資料夾 | 直接分享資料夾，不需裝任何工具 |

## 快速開始

### 新機器一鍵設定

```bash
# 方法 1：直接執行（推薦）
bash <(curl -fsSL https://raw.githubusercontent.com/weiting-tw/dotfiles/main/chezmoi/install.sh)

# 方法 2：先 clone 再執行
git clone https://github.com/weiting-tw/dotfiles.git
cd settings/chezmoi
bash install.sh
```

install.sh 會自動偵測本地 repo，有則直接使用，無需 clone。

安裝過程會互動式詢問：
- Email 地址
- 全名
- 是否為工作機器（公司機器 cask 安裝到 ~/Applications）
- 是否安裝 Docker
- 是否安裝 AI tools（Claude, Codex, Gemini）

### 已有設定的機器更新

```bash
chezmoi update    # 從 Git 拉取 + 套用
```

### 常用指令（Makefile）

```bash
make              # 顯示所有可用指令
make bootstrap    # 首次安裝（完整設定）
make apply        # 套用 chezmoi 設定到本機
make update       # 從 Git 拉取最新設定並套用
make diff         # 顯示本機與 chezmoi 設定差異
make doctor       # 檢查 chezmoi 健康狀態
make lint         # 執行 shellcheck 檢查腳本
make icloud-capture   # 本地設定 → iCloud
make icloud-apply     # iCloud 設定 → 本地
make icloud-status    # 顯示 iCloud 同步狀態
```

## 目錄結構

```
chezmoi/                          # chezmoi source directory
├── .chezmoi.toml.tmpl            # 互動式設定模板（新機器會詢問）
├── .chezmoidata.yaml             # 預設值
├── .chezmoiignore                # 忽略清單
├── .chezmoiexternal.toml         # 外部資源（Antidote）
│
├── dot_zshrc.tmpl                # → ~/.zshrc
├── dot_zsh_plugins.txt           # → ~/.zsh_plugins.txt
├── dot_gitconfig.tmpl            # → ~/.gitconfig（含 Go template）
├── dot_bash_profile              # → ~/.bash_profile
├── dot_bashrc                    # → ~/.bashrc
├── dot_profile                   # → ~/.profile
├── dot_zprofile                  # → ~/.zprofile
├── dot_editorconfig              # → ~/.editorconfig
├── dot_gitignore_global          # → ~/.gitignore_global
├── dot_tool-versions             # → ~/.tool-versions
├── dot_hushlogin                 # → ~/.hushlogin
├── dot_npmrc.tmpl                # → ~/.npmrc（從環境變數注入 token）
├── dot_secrets.example           # → ~/.secrets.example（參考用）
│
├── private_dot_ssh/              # → ~/.ssh/（權限 700）
│   ├── config.tmpl               # SSH config（含 Bitwarden Agent）
│   ├── private_known_hosts       # known_hosts
│   └── *.pub                     # SSH 公鑰
│
├── private_dot_gnupg/            # → ~/.gnupg/
│   └── gpg-agent.conf
│
├── private_dot_docker/           # → ~/.docker/
│   └── config.json
│
├── private_dot_codex/            # → ~/.codex/
│   └── config.toml.tmpl          # Codex config（含 API key template）
│
├── private_dot_config/           # → ~/.config/
│   └── opencode/
│       └── opencode.json.tmpl    # OpenCode config（含 API key template）
│
├── Library/
│   └── Application Support/
│       └── Claude/
│           └── claude_desktop_config.json.tmpl  # Claude Desktop MCP config
│
├── run_once_before_01-install-xcode-tools.sh           # Xcode CLI Tools
├── run_onchange_before_02-install-brew-packages.sh.tmpl # Homebrew + Brewfile + mise
├── run_onchange_before_03-install-npm-packages.sh.tmpl  # npm 全域套件
├── run_once_after_04-setup-git-identity.sh.tmpl         # Git includeIf
├── run_once_after_05-setup-ssh.sh.tmpl                  # SSH + Bitwarden
├── run_onchange_after_06-configure-macos.sh.tmpl        # macOS defaults
├── run_onchange_after_07-setup-ai-tools.sh.tmpl         # AI tools + iCloud（需 has_ai_tools）
├── run_once_after_09-setup-launchd.sh.tmpl              # Auto-sync agents（含失敗通知）
│
├── scripts/                      # 輔助腳本（不被 chezmoi apply）
│   ├── icloud-sync.sh            # iCloud 雙向同步
│   ├── seed-icloud.sh            # 首次 iCloud 初始化
│   └── icloud-capture.plist.tmpl # LaunchAgent 模板
│
├── hosts/                        # 機器特定覆寫
│   └── MacBook-Air/
│       ├── Brewfile              # 額外套件
│       ├── ssh_config            # 額外 SSH hosts
│       └── .gitconfig-work       # 工作 Git identity
│
└── install.sh                    # 一鍵 bootstrap 入口
```

## 分層同步策略

### 哪些走 chezmoi（Git 版本控制）

| 檔案 | 目標路徑 | 說明 |
|------|---------|------|
| dot_zshrc.tmpl | ~/.zshrc | Shell 設定（template: is_work 條件 Homebrew appdir） |
| dot_gitconfig.tmpl | ~/.gitconfig | Git 設定（template 注入 name/email） |
| dot_editorconfig | ~/.editorconfig | 編輯器格式設定 |
| private_dot_ssh/config.tmpl | ~/.ssh/config | SSH config（template 注入 key 路徑） |
| configs/Brewfile | - | Homebrew 套件清單 |
| macOS defaults script | - | 系統偏好設定 |

### 哪些走 iCloud（雲端即時同步）

| 檔案 | iCloud 路徑 | 說明 |
|------|------------|------|
| Claude agents/*.md | dotfiles-shared/claude/agents/ | AI agent 定義 |
| Claude settings.json | dotfiles-shared/claude/settings.json | Claude Code 偏好 |
| OpenCode oh-my-opencode.json | dotfiles-shared/opencode/ | OpenCode 插件設定 |
| OpenCode agent/*.md | dotfiles-shared/opencode/agent/ | Agent 定義 |
| VS Code extensions.txt | dotfiles-shared/vscode/ | 擴充套件清單 |
| iTerm2 preferences | dotfiles-shared/iterm2/ | iTerm2 設定（自動讀寫） |
| Brewfile.snapshot | dotfiles-shared/ | 自動 dump 的套件快照 |

### 哪些走 Bitwarden（密鑰管理）

| 項目 | 說明 |
|------|------|
| SSH private keys | 存在 Bitwarden vault，透過 SSH Agent 提供 |
| API keys | 手動填入 ~/.secrets（不進 Git、不進 iCloud） |

## 日常操作指南

### 修改 dotfile

```bash
# 用 chezmoi edit 編輯（自動開啟 source 版本）
chezmoi edit ~/.zshrc

# 預覽變更
chezmoi diff

# 套用變更
chezmoi apply

# 提交到 Git
chezmoi cd
git add -A && git commit -m "update zshrc"
git push
```

### 新增 AI tool config

AI tool 的非機敏設定走 iCloud：

```bash
# 修改後會自動同步到 iCloud（因為是 symlink）
# 或手動觸發同步
icloud-sync.sh capture
```

含 API key 的設定走 chezmoi template：

```bash
# 編輯 template
chezmoi edit ~/.codex/config.toml

# 套用（會從 ~/.secrets 讀取環境變數）
chezmoi apply
```

### 新增機器特定設定

```bash
# 1. 在 hosts/ 下建立目錄
mkdir -p "$(chezmoi source-path)/hosts/$(hostname -s)"

# 2. 新增機器特定 Brewfile
cat > "$(chezmoi source-path)/hosts/$(hostname -s)/Brewfile" << 'EOF'
brew "postgresql"
cask "docker"
EOF

# 3. 提交
chezmoi cd && git add -A && git commit -m "add host-specific Brewfile"
```

### 更新 Secrets

```bash
# 編輯 secrets（不會進 Git）
vim ~/.secrets

# 重新套用 template（注入新的 API keys）
chezmoi apply
```

### 手動 iCloud 同步

```bash
# 將本地設定推到 iCloud
icloud-sync.sh capture

# 從 iCloud 拉到本地
icloud-sync.sh apply

# 查看同步狀態
icloud-sync.sh status
```

## 多機器使用流程

### 第一台機器（首次設定）

```bash
# 1. 執行 bootstrap
bash install.sh

# 2. 設定 secrets
vim ~/.secrets

# 3. 重新套用
chezmoi apply

# 4. 初始化 iCloud 資料
$(chezmoi source-path)/scripts/seed-icloud.sh
```

### 第二台以後的機器

```bash
# 1. 執行 bootstrap（會自動偵測 iCloud 資料）
bash install.sh

# 2. 設定 secrets（每台機器獨立）
vim ~/.secrets

# 3. 重新套用
chezmoi apply
```

### 日常同步

```bash
# 自動：launchd 每 12 小時執行 chezmoi update
# 自動：launchd 每 6 小時執行 icloud-sync.sh capture
# 手動：
chezmoi update              # 拉取 Git 變更
icloud-sync.sh apply        # 套用 iCloud 變更
```

## 共用設定給他人

### 方法 1：iCloud 共享資料夾

```bash
# 在 Finder 中右鍵 iCloud 的 dotfiles-shared 資料夾
# → 共享 → 選擇對象
# 對方只需要 iCloud 帳號，不需要安裝任何工具
```

### 方法 2：Git repo（完整系統）

```bash
# 1. Fork 此 repo
# 2. 修改 .chezmoidata.yaml 的預設值
# 3. 在新機器執行：
chezmoi init --apply https://github.com/weiting-tw/dotfiles.git
```

### 方法 3：只共用部分設定

```bash
# 匯出單一 dotfile
chezmoi cat ~/.zshrc > ~/Desktop/zshrc-example.txt

# 匯出 Brewfile
cp "$(chezmoi source-path)/hosts/$(hostname -s)/Brewfile" ~/Desktop/
```

## 從舊系統遷移

如果你之前使用的是 shell script 版本的 bootstrap：

```bash
# 1. 備份舊設定
mkdir -p ~/.dotfiles_backup/migration
cp ~/.zshrc ~/.gitconfig ~/.bash_profile ~/.dotfiles_backup/migration/

# 2. 移除舊的 symlinks
for f in ~/.zshrc ~/.gitconfig ~/.bash_profile ~/.bashrc ~/.profile; do
    [[ -L "$f" ]] && rm "$f"
done

# 3. 執行新的 bootstrap
bash install.sh

# 4. 初始化 iCloud（首次）
$(chezmoi source-path)/scripts/seed-icloud.sh

# 5. 驗證
chezmoi diff    # 應該沒有差異
```

## 疑難排解

### chezmoi apply 失敗

```bash
# 查看詳細錯誤
chezmoi apply --verbose

# 試執行（不實際修改）
chezmoi apply --dry-run

# 重新初始化
chezmoi init --apply
```

### Template 渲染錯誤

```bash
# 測試 template
chezmoi execute-template '{{ .email }}'
chezmoi execute-template '{{ env "NPM_AUTH_TOKEN" }}'

# 查看所有 data
chezmoi data
```

### iCloud 同步未生效

```bash
# 檢查 iCloud 目錄是否存在
ls -la ~/Library/Mobile\ Documents/com~apple~CloudDocs/dotfiles-shared/

# 手動觸發同步
icloud-sync.sh status
icloud-sync.sh capture

# 檢查 symlinks
ls -la ~/.claude/agents
ls -la ~/.config/opencode/oh-my-opencode.json
```

### Bitwarden SSH Agent 未偵測到

```bash
# 檢查 socket（直接或 container 路徑）
ls -la ~/.bitwarden-ssh-agent.sock
ls -la ~/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock

# 如果在 container 路徑找到但 ~ 下沒有，建立 symlink：
ln -sf ~/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock ~/.bitwarden-ssh-agent.sock

# 確認 Bitwarden 設定
# 1. 開啟 Bitwarden 桌面版（官網版或 App Store 版皆可）
# 2. Settings > SSH Agent > Enable
# 3. 解鎖 Bitwarden
```

### LaunchAgent 未執行

```bash
# 檢查 agent 狀態
launchctl list | grep -E "chezmoi|icloud"

# 手動載入
launchctl load ~/Library/LaunchAgents/com.user.chezmoi-update.plist
launchctl load ~/Library/LaunchAgents/com.user.icloud-capture.plist

# 查看 log
cat ~/.local/log/dotfiles/chezmoi-update.out.log
cat ~/.local/log/dotfiles/icloud-capture.out.log
```

### secrets 未注入

```bash
# 確認 ~/.secrets 存在且已 source
source ~/.secrets
echo $CONTEXT7_API_KEY    # 應該有值

# 重新套用 template
chezmoi apply

# 查看渲染結果
chezmoi cat ~/.codex/config.toml
```

## 進階設定

### 新增 chezmoi template 變數

```yaml
# 編輯 .chezmoidata.yaml
chezmoi edit-config-template

# 或直接修改 source
vim "$(chezmoi source-path)/.chezmoidata.yaml"
```

### Feature Flags

chezmoi init 時會詢問 feature flags，控制可選功能：

| Flag | 預設 | 作用 |
|------|------|------|
| `is_work` | false | 公司機器 cask 安裝到 ~/Applications |
| `has_docker` | false | 安裝 Docker |
| `has_ai_tools` | true | 安裝 AI tools（Claude, Codex, Gemini）+ iCloud 同步 |

修改 flag：
```bash
chezmoi init   # 重新回答問題
# 或直接編輯 ~/.config/chezmoi/chezmoi.toml
```

### 語言版本管理（mise）

使用 [mise](https://mise.jdx.dev/) 管理語言版本（.tool-versions 格式）：

```bash
mise install          # 安裝 .tool-versions 指定的版本
mise use python@3.13  # 設定 Python 版本
```

### 新增 run script

```bash
# 命名規則：
# run_once_before_*   — 只執行一次，在 apply 前
# run_once_after_*    — 只執行一次，在 apply 後
# run_onchange_*      — 內容變更時重新執行

# 範例：新增一個安裝腳本
vim "$(chezmoi source-path)/run_once_after_install-my-tool.sh"
```
