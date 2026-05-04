#!/usr/bin/env bash
# Install lazygit on Ubuntu.
# https://github.com/jesseduffield/lazygit?tab=readme-ov-file#ubuntu
#
# Idempotent: skips download if already at the target version.
# Run as a normal user — sudo is invoked only where needed.
#
# Usage:  ./7_workstation-lazygit.sh
#         LAZYGIT_VERSION=0.44.1 ./7_workstation-lazygit.sh  # pin a specific version

set -euo pipefail

LAZYGIT_VERSION="${LAZYGIT_VERSION:-latest}"
LAZYGIT_BIN="/usr/local/bin/lazygit"

if [[ "$LAZYGIT_VERSION" == "latest" ]]; then
  LAZYGIT_VERSION=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/jesseduffield/lazygit/releases/latest | sed 's|.*/tag/v||')
fi

echo "Installing lazygit $LAZYGIT_VERSION to $LAZYGIT_BIN"
if [[ -x "$LAZYGIT_BIN" ]] && "$LAZYGIT_BIN" --version 2>/dev/null | grep -qF "$LAZYGIT_VERSION"; then
  echo "Already at $LAZYGIT_VERSION, skipping download."
else
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fL --retry 3 -o "$tmpdir/lazygit.tar.gz" \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
  tar xf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit
  sudo install -m 0755 -o root -g root "$tmpdir/lazygit" "$LAZYGIT_BIN"
  rm -rf "$tmpdir"
  trap - EXIT
fi

