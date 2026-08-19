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

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

gh_keyring_path="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
gh_keyring_url="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
# deb822 .sources, not a one-line .list: Ubuntu 26.04 migrated this source to
# github-cli.sources, so writing a .list would create a duplicate source.
gh_source_file="/etc/apt/sources.list.d/github-cli.sources"

if [[ $EUID -eq 0 ]]; then
  echo "Do not run as root. The script will sudo for the steps that need it." >&2
  exit 1
fi

refresh_cache=0

# ── 1. GitHub CLI keyring ─────────────────────────────────────────────────────
echo "[1/4] GitHub CLI keyring"
if [[ -f "$gh_keyring_path" ]]; then
  echo "      already present, skipping."
else
  sudo mkdir -p -m 755 /etc/apt/keyrings
  tmpkey=$(mktemp)
  trap 'rm -f "$tmpkey"' EXIT
  # -f so an HTTP error fails the script instead of installing an error page
  # as the signing key.
  curl -fsSL --retry 3 -o "$tmpkey" "$gh_keyring_url"
  sudo install -m 0644 -o root -g root "$tmpkey" "$gh_keyring_path"
  rm -f "$tmpkey"
  trap - EXIT
fi

# ── 2. GitHub CLI APT source ──────────────────────────────────────────────────
# Compared against the desired content rather than merely checked for existence,
# and handled independently of whether gh is installed. The 26.04 release
# upgrade rewrote this file with "Enabled: no", cutting gh off from updates —
# and the old "command -v gh && skip everything" guard meant an installed gh
# guaranteed the source was never repaired.
echo "[2/4] GitHub CLI APT source"
read -r -d '' gh_source <<EOF || true
Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: $gh_keyring_path
Enabled: yes
EOF

if [[ -f "$gh_source_file" ]] && [[ "$(cat "$gh_source_file")" == "$gh_source" ]]; then
  echo "      already present and enabled, skipping."
else
  echo "      writing $gh_source_file"
  printf '%s\n' "$gh_source" | sudo tee "$gh_source_file" >/dev/null
  sudo rm -f /etc/apt/sources.list.d/github-cli.list
  refresh_cache=1
fi

# ── 3. GitHub CLI package ─────────────────────────────────────────────────────
echo "[3/4] GitHub CLI (gh)"
if dpkg-query -W -f='${db:Status-Status}' gh 2>/dev/null | grep -q '^installed$'; then
  echo "      already installed ($(gh --version | head -1))."
  if [[ $refresh_cache -eq 1 ]]; then
    echo "      source changed, refreshing cache so upgrades are visible"
    sudo apt-get update
  fi
else
  sudo apt-get update
  sudo apt-get install -y gh
fi

# ── 4. GitHub Copilot CLI ─────────────────────────────────────────────────────
echo "[4/4] GitHub Copilot CLI"
if command -v copilot &>/dev/null; then
  echo "      already installed, skipping."
else
  # Upstream distributes this as an install script with no published checksum
  # and no versioned URL, so it cannot be pinned or verified. Fetch it to a file
  # first so an HTTP error fails here rather than being fed to a root shell, and
  # so the script that will run is on disk to inspect if something goes wrong.
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL --retry 3 -o "$installer" https://gh.io/copilot-install
  echo "      running upstream installer ($installer) as root"
  sudo bash "$installer"
  rm -f "$installer"
  trap - EXIT
fi

echo
echo "Done. Authenticate with: copilot /login"
