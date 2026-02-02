# macOS Dotfiles — chezmoi + iCloud

自動化 macOS 開發環境設定，支援多機器同步。

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

## 快速開始

### 新機器

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/weiting-tw/settings/main/chezmoi/install.sh)
```

install.sh 會自動偵測本地 repo，有則直接使用，無需 clone。

安裝後設定 secrets：

```bash
cp ~/.secrets.example ~/.secrets
chmod 600 ~/.secrets
vim ~/.secrets        # 填入 API keys
source ~/.zshrc
```

### 已有機器更新

```bash
chezmoi update
```

## 詳細文件

完整教學請參考 [chezmoi/README.md](chezmoi/README.md)。

## License

MIT
