.PHONY: help bootstrap apply update diff status edit doctor icloud-capture icloud-apply icloud-status lint

help: ## 顯示可用指令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap: ## 首次安裝（完整設定）
	@bash install.sh

apply: ## 套用 chezmoi 設定到本機
	@chezmoi apply

update: ## 從 Git 拉取最新設定並套用
	@chezmoi update

diff: ## 顯示本機與 chezmoi 設定差異
	@chezmoi diff

status: ## 顯示 chezmoi 狀態
	@chezmoi status

edit: ## 開啟 chezmoi source 目錄
	@chezmoi cd

doctor: ## 檢查 chezmoi 健康狀態
	@chezmoi doctor

icloud-capture: ## 本地設定 → iCloud
	@bash scripts/icloud-sync.sh capture

icloud-apply: ## iCloud 設定 → 本地
	@bash scripts/icloud-sync.sh apply

icloud-status: ## 顯示 iCloud 同步狀態
	@bash scripts/icloud-sync.sh status

lint: ## 執行 shellcheck 檢查腳本
	@shellcheck scripts/*.sh install.sh || true

.DEFAULT_GOAL := help
