#!/bin/bash
# Install Xcode Command Line Tools (run once)

if [[ "$(uname)" != "Darwin" ]]; then
    exit 0
fi

if xcode-select -p &>/dev/null; then
    echo "✓ Xcode Command Line Tools already installed"
    exit 0
fi

echo "Installing Xcode Command Line Tools..."
xcode-select --install

# Wait for installation to complete
echo "Waiting for installation to complete..."
until xcode-select -p &>/dev/null; do
    sleep 5
done

echo "✓ Xcode Command Line Tools installed"
