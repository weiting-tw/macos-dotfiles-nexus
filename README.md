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
git clone https://github.com/weiting-tw/dotfiles.git ~/Documents/workspace/dotfiles
cd ~/Documents/workspace/dotfiles && bash chezmoi/install.sh
```

安裝過程會互動式詢問：
- Email / 全名（Git identity）
- 是否為工作機器（cask 安裝到 ~/Applications）
- 是否安裝 Docker
- 是否安裝 AI tools（Claude, Codex, Gemini）

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

### 常用指令（Makefile）

```bash
make              # 顯示所有可用指令
make bootstrap    # 首次安裝
make apply        # 套用設定
make update       # 從 Git 拉取並套用
make doctor       # 健康檢查
make lint         # ShellCheck 檢查腳本
```

## 詳細文件

完整教學請參考 [chezmoi/README.md](chezmoi/README.md)。

## License

MIT
