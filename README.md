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
chezmoi (Git)          iCloud Drive           Bitwarden
├── dotfiles           ├── AI agents          ├── SSH private keys
├── .gitconfig         ├── AI skills/plugins  └── API keys
├── .zshrc             ├── VS Code exts
├── Brewfile           ├── iTerm2 prefs
├── SSH config         └── MCP configs
├── macOS defaults
└── AI tool templates
```

| 層級 | 用途 | 原因 |
|------|------|------|
| chezmoi (Git) | dotfiles 版本控制 | 穩定、需追蹤變更歷史 |
| iCloud Drive | AI tools、iTerm2 等頻繁變動設定 | 即時同步，不需每次 commit |
| Bitwarden | SSH 私鑰、API keys | 機敏資料不能存在任何 repo |

### 已有機器更新

```bash
chezmoi update
```

### 常用指令（Makefile）

```bash
make              # 顯示所有可用指令
make bootstrap    # 首次安裝
make apply        # 套用設定
make update       # 從 Git 拉取並套用
make doctor       # 健康檢查
make lint         # ShellCheck 檢查腳本
```

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

## License

MIT
