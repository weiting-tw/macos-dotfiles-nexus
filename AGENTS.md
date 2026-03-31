# AGENTS.md — macos-dotfiles-nexus

## 專案概述

macOS 開發環境同步中樞，採用 **chezmoi + iCloud + Bitwarden** 三層混合架構，實現多台 Mac 之間的開發環境一致性。

- **chezmoi (Git)**：dotfiles 版本控制、模板渲染、一鍵安裝
- **iCloud Drive**：即時同步 AI 工具設定（Claude、Codex、OpenCode）、IDE 偏好設定
- **Bitwarden**：GPG/SSH 私鑰、API keys 等機敏資料

## chezmoi 模板變數

首次安裝時透過 `.chezmoi.toml.tmpl` 互動式設定：

| 變數 | 用途 |
|------|------|
| `email` | Git commit email |
| `name` | Git commit 作者名稱 |
| `is_work` | 公司機器（影響 Cask 安裝路徑） |
| `has_docker` | 是否安裝 Docker |
| `has_ai_tools` | 是否安裝 AI 工具（Claude、Codex、Gemini） |
| `version_manager` | 語言版本管理器（asdf 或 mise） |

## 管控內容一覽

### Shell 設定

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `dot_zshrc.tmpl` | `~/.zshrc` | Zsh 主設定（alias、PATH、AI 工具） |
| `dot_zsh_plugins.txt` | `~/.zsh_plugins.txt` | Antidote 插件清單 |
| `dot_zprofile` | `~/.zprofile` | Zsh profile |
| `dot_bash_profile` | `~/.bash_profile` | Bash profile（source ~/.secrets） |
| `dot_bashrc` | `~/.bashrc` | Bash 設定 |
| `dot_profile` | `~/.profile` | 通用 shell profile |
| `dot_hushlogin` | `~/.hushlogin` | 靜默終端登入訊息 |

### Git 設定

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `dot_gitconfig.tmpl` | `~/.gitconfig` | Git 全域設定（模板，注入 name/email） |
| `dot_gitignore` | `~/.gitignore` | 全域 gitignore |

### 開發工具

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `dot_editorconfig` | `~/.editorconfig` | 編輯器格式統一 |
| `dot_npmrc.tmpl` | `~/.npmrc` | npm 設定（模板） |
| `dot_tool-versions` | `~/.tool-versions` | asdf 語言版本 |

### SSH

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `private_dot_ssh/private_config.tmpl` | `~/.ssh/config` | SSH 全域設定（Bitwarden SSH Agent） |
| `private_dot_ssh/private_config.d/` | `~/.ssh/config.d/` | 機器特定的 Host 設定 |

### GPG

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `private_dot_gnupg/private_gpg-agent.conf.tmpl` | `~/.gnupg/gpg-agent.conf` | GPG agent 設定（pinentry-mac） |
| `private_dot_gnupg/private_gpg.conf.tmpl` | `~/.gnupg/gpg.conf` | GPG 設定（default-key） |

### AI 工具

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `private_dot_codex/config.toml.tmpl` | `~/.codex/config.toml` | Codex CLI 設定（Azure OpenAI profiles） |
| `private_dot_codex-mcp/config.toml.tmpl` | `~/.codex-mcp/config.toml` | Codex MCP server 設定 |
| `private_dot_config/opencode/` | `~/.config/opencode/` | OpenCode 設定 |
| `Library/Application Support/Claude/` | `~/Library/Application Support/Claude/` | Claude Desktop 設定 |

### Docker

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `private_dot_docker/config.json` | `~/.docker/config.json` | Docker 設定 |

### Secrets

| 檔案 | 目標路徑 | 說明 |
|------|----------|------|
| `dot_secrets.example` | `~/.secrets.example` | 環境變數範本（API keys、GPG、Bitwarden） |

`~/.secrets` 本身不受 Git 管控，需手動建立並填入真實值。

### macOS 系統設定

| 檔案 | 說明 |
|------|------|
| `run_onchange_after_06-configure-macos.sh.tmpl` | macOS defaults（Dock、Finder、鍵盤等） |
| `hosts` | 自訂 /etc/hosts |

## 安裝腳本（依執行順序）

| 腳本 | 階段 | 說明 |
|------|------|------|
| `run_once_before_01-install-xcode-tools.sh` | before | 安裝 Xcode CLI Tools |
| `run_onchange_before_02-install-brew-packages.sh.tmpl` | before | Homebrew + 套件安裝 |
| `run_onchange_before_03-install-npm-packages.sh.tmpl` | before | 全域 npm 套件 |
| `run_once_after_04-setup-git-identity.sh.tmpl` | after | Git 身份設定 |
| `run_once_after_05-setup-ssh.sh.tmpl` | after | SSH 設定 |
| `run_once_after_06-setup-gpg.sh.tmpl` | after | GPG key 匯入（透過 Bitwarden） |
| `run_onchange_after_07-setup-ai-tools.sh.tmpl` | after | AI 工具初始化 |
| `run_once_after_09-setup-launchd.sh.tmpl` | after | LaunchAgent 排程 |

## iCloud 同步（scripts/icloud-sync.sh）

透過 symlink 將本地設定指向 iCloud Drive，實現即時跨機同步：

| 指令 | 說明 |
|------|------|
| `icloud-sync.sh capture` | 本地 → iCloud（首次推送） |
| `icloud-sync.sh apply` | iCloud → 本地（建立 symlink） |
| `icloud-sync.sh diff` | 顯示差異 |
| `icloud-sync.sh status` | 同步狀態 |
| `icloud-sync.sh health` | 深度健康檢查 |

**同步項目：** Claude agents/skills/hooks/HUD、CLAUDE.md、.mcp.json、Codex skills、Claude Code Router、OpenCode config、Beyond Compare 5、VS Code extensions、iTerm2 preferences

## 重要注意事項

### 機敏資訊保護（嚴格遵守）

- **絕對不可 commit** 任何 API key、密碼、token、私鑰等機敏資料
- `~/.secrets` 僅存在於本機，不進 Git、不進 iCloud
- 模板中引用環境變數時使用 `{{ env "VAR_NAME" }}`，不可硬寫實際值
- `.gitignore` 已排除 `.secrets`，但提交前仍需確認 diff 中無機敏內容
- Bitwarden 負責管理 GPG/SSH 私鑰與 API keys，不可用其他方式儲存

### 一般注意事項

- 模板檔（`.tmpl`）會透過 chezmoi 渲染，依賴 `~/.secrets` 中的環境變數
- chezmoi source 目錄在 `~/.local/share/chezmoi`，與本 repo 是獨立副本
- `chezmoi update` 會從 Git 拉取並套用；手動改本地檔案會導致 drift
- `private_` 前綴的檔案會以 600 權限建立
