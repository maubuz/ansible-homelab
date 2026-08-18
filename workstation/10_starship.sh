#!/usr/bin/env bash
#
## Starship prompt, preferring the distro package over the upstream installer.
## From https://documentation.ubuntu.com/ubuntu-for-developers/howto/rust-setup/
#
# Idempotent: skips the install when starship is already on PATH, and only
# appends to .bashrc once.
#
# Usage:  ./10_starship.sh

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

if command -v starship >/dev/null; then
  echo "[1/2] starship already installed ($(starship --version | head -1)), skipping."
else
  # starship is in the Ubuntu archive from 25.04 onwards. "apt-cache show"
  # succeeds when the package exists in the configured repositories, so a
  # failure here means the distro does not carry it and the upstream installer
  # is the fallback.
  sudo apt-get update
  if apt-cache show starship &>/dev/null; then
    echo "[1/2] Installing starship from the distro repositories"
    sudo apt-get install -y starship
  else
    echo "[1/2] starship not in the repositories, using the upstream installer"
    installer=$(mktemp)
    trap 'rm -f "$installer"' EXIT
    curl -fsSL --retry 3 -o "$installer" https://starship.rs/install.sh
    sh "$installer" --yes
    rm -f "$installer"
    trap - EXIT
  fi
fi

# Add to bashrc if not already there
echo "[2/2] Configuring ~/.bashrc"
if grep -q 'starship init bash' ~/.bashrc; then
  echo "      already initialised, skipping."
else
  echo 'eval "$(starship init bash)"' >>~/.bashrc
  echo "      added starship init to ~/.bashrc"
fi

echo
echo "Done. Open a new shell to pick up the prompt."
