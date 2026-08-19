#!/usr/bin/env bash
# Install Brave and force-install a set of Chromium extensions.
#
# Idempotent: re-running skips what is already in place. Run as a normal user —
# sudo is invoked only where needed.
#
# Usage:  ./2a_brave_browser.sh

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

brave_keyring_url="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
brave_keyring_path="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
brave_repo_uri="https://brave-browser-apt-release.s3.brave.com"
# deb822 .sources, not a one-line .list. Ubuntu 26.04 migrated third-party
# sources to this format; writing a .list here would sit alongside the migrated
# brave-browser-release.sources and apt would report a duplicate source.
brave_source_file="/etc/apt/sources.list.d/brave-browser-release.sources"

if [[ $EUID -eq 0 ]]; then
  echo "Do not run as root. The script will sudo for the steps that need it." >&2
  exit 1
fi

refresh_cache=0

# ── 1. Keyring ────────────────────────────────────────────────────────────────
if [[ -f "$brave_keyring_path" ]]; then
  echo "[1/4] Brave keyring already present, skipping download."
else
  echo "[1/4] Downloading Brave keyring"
  # Download to a temp file first, with -f so an HTTP error is a failure.
  # Piping curl straight into "sudo tee" would install an error page as the
  # signing key, and the check above would then skip the fix on every later run.
  tmpkey=$(mktemp)
  trap 'rm -f "$tmpkey"' EXIT
  curl -fsSL --retry 3 -o "$tmpkey" "$brave_keyring_url"
  sudo install -m 0644 -o root -g root "$tmpkey" "$brave_keyring_path"
  rm -f "$tmpkey"
  trap - EXIT
fi

# ── 2. APT source ─────────────────────────────────────────────────────────────
# Compared against the desired content rather than merely checked for existence.
# Ubuntu's 26.04 release upgrade rewrote this file with "Enabled: no", which cut
# Brave off from updates entirely — a browser with no security updates. An
# exists-only guard would have left it that way.
read -r -d '' brave_source <<EOF || true
Types: deb
URIs: $brave_repo_uri
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: $brave_keyring_path
Enabled: yes
EOF

if [[ -f "$brave_source_file" ]] && [[ "$(cat "$brave_source_file")" == "$brave_source" ]]; then
  echo "[2/4] Brave source already present and enabled, skipping."
else
  echo "[2/4] Writing $brave_source_file"
  printf '%s\n' "$brave_source" | sudo tee "$brave_source_file" >/dev/null
  # Drop a superseded one-line source, from an older run or a pre-upgrade install.
  sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
  refresh_cache=1
fi

# ── 3. Package ────────────────────────────────────────────────────────────────
# Checked independently of the source file. Previously the install lived inside
# the "create the source" branch, so an existing source plus a missing or
# removed package could never repair itself.
if dpkg-query -W -f='${db:Status-Status}' brave-browser 2>/dev/null | grep -q '^installed$'; then
  echo "[3/4] brave-browser already installed."
  if [[ $refresh_cache -eq 1 ]]; then
    echo "      source changed, refreshing cache so upgrades are visible"
    sudo apt-get update
  fi
else
  echo "[3/4] Installing brave-browser"
  sudo apt-get update
  sudo apt-get install -y brave-browser
fi

# ── 4. Extensions ─────────────────────────────────────────────────────────────
# [Working] Ref: https://stackoverflow.com/questions/73289644/how-to-install-browser-extension-for-namely-brave-through-terminal
# Alt ref1: https://community.brave.com/t/installing-extensions-via-command-line/463730/2
# Alt ref2: https://github.com/brave/brave-browser/issues/23966

EXTENSIONS_PATH=/opt/brave.com/brave/extensions
sudo mkdir -p "$EXTENSIONS_PATH"

EXTENSIONS=(
  # Bitwarden
  nngceckbapebfimnlniiiahkandclblb
  # Vimium
  dbepggeogbaibhgnhhndojpepiihcmeb
  # Tab Session Manager
  iaiomicjabeggjcfkbimgmglanimpnae
  # Tab to Window/Popup - Keyboard Shortcut
  adbkphmimfcaeonicpmamfddbbnphikh
  # Dark Reader
  eimadpbcbfnmbkopoojfekhnkhdbieeh
  # Google Docs Offline (for copy/paste functionality)
  ghbmnnjooekpmoecnnnilnnbdlolhkhi
)

echo "[4/4] Installing Brave/Chromium extensions"
for ext in "${EXTENSIONS[@]}"; do
  if [[ -f "${EXTENSIONS_PATH}/${ext}.json" ]]; then
    echo "      $ext already installed, skipping."
  else
    echo '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }' |
      sudo tee "${EXTENSIONS_PATH}/${ext}.json" >/dev/null
    echo "      installed $ext"
  fi
done

echo
echo "Done. Extensions are registered for force-install; restart Brave to pick them up."
