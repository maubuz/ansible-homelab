#!/usr/bin/env bash
# Install GitHub CLI (gh) and GitHub Copilot CLI on Ubuntu.
#
# References:
#   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
#   https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli
#
# Idempotent: skips steps already completed.
# Run as a normal user — sudo is invoked only where needed.
#
# Usage:  ./12_copilot.sh

set -euo pipefail

# ── 1. GitHub CLI (gh) ────────────────────────────────────────────────────────
echo "[1/2] Installing GitHub CLI (gh)"
if command -v gh &>/dev/null; then
  echo "      gh already installed ($(gh --version | head -1)), skipping."
else
  sudo mkdir -p -m 755 /etc/apt/keyrings
  sudo mkdir -p -m 755 /etc/apt/sources.list.d
  out=$(mktemp)
  wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  rm -f "$out"
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install -y gh
fi

# ── 2. GitHub Copilot CLI ─────────────────────────────────────────────────────
echo "[2/2] Installing GitHub Copilot CLI"
if command -v copilot &>/dev/null; then
  echo "      Copilot CLI already installed, skipping."
else
  # Pipe to sudo bash to install system-wide to /usr/local/bin
  curl -fsSL https://gh.io/copilot-install | sudo bash
fi

echo ""
echo "Done. Authenticate with: copilot /login"
