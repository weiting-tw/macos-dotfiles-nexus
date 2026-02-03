# Host-Specific Overrides

Place machine-specific configurations in subdirectories named after the hostname.

## Structure

```
hosts/
├── MacBook-Air/
│   ├── Brewfile           # Host-specific Homebrew packages
│   └── .gitconfig-work    # Host-specific Git identity
├── MacBook-Pro/
│   └── Brewfile
└── example/
    └── .gitkeep           # Template directory
```

## Usage

1. Get your hostname: `hostname -s`
2. Create a directory: `mkdir -p hosts/$(hostname -s)`
3. Add host-specific files

The bootstrap script (`run_onchange_before_02-install-brew-packages.sh.tmpl`)
automatically detects and uses host-specific Brewfiles.
