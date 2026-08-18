#!/usr/bin/env bash
# Install and configure kanata on a fresh Ubuntu 24.04+ Desktop.
#
# Idempotent: re-running skips the download when the pinned version is already
# installed, refreshes the udev rule, and rewrites the systemd user unit. Run as
# a normal user — sudo is invoked only for the steps that need it.
#
# Usage:  ./11_kanata.sh
#         KANATA_VERSION=latest ./11_kanata.sh   # track the newest release
#         KANATA_SHA256=<hash> ./11_kanata.sh    # verify the downloaded binary
#
# The config itself is not installed here — it comes from the dotfiles repo via
# stow. See 11_kanata.md.

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

# Pinned by default so re-runs are idempotent. Set to "latest" to track the
# newest release (which re-downloads on every run).
KANATA_VERSION="${KANATA_VERSION:-v1.11.0}"
# Optional expected sha256 of the unzipped binary. Empty = skip verification.
KANATA_SHA256="${KANATA_SHA256:-}"
KANATA_BIN="/usr/local/bin/kanata"
CONFIG_DIR="$HOME/.config/kanata"
CONFIG_FILE="$CONFIG_DIR/mauMap.kanata.kbd"
UNIT_PATH="$HOME/.config/systemd/user/kanata.service"

if [[ $EUID -eq 0 ]]; then
  echo "Do not run as root. The script will sudo for the steps that need it." >&2
  exit 1
fi

for cmd in curl unzip; do
  command -v "$cmd" >/dev/null || {
    echo "Missing required command: $cmd  (sudo apt install -y $cmd)" >&2
    exit 1
  }
done

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  # Floor check: warn only on non-Ubuntu or anything older than 24.04.
  if [[ "${ID:-}" != "ubuntu" ]] ||
    [[ "$(printf '%s\n' 24.04 "${VERSION_ID:-0}" | sort -V | head -n1)" != "24.04" ]]; then
    echo "Warning: this script targets Ubuntu 24.04+ (detected ${PRETTY_NAME:-unknown})." >&2
  fi
fi

echo "[1/6] Installing kanata $KANATA_VERSION to $KANATA_BIN"
if [[ "$KANATA_VERSION" != "latest" ]] && \
   [[ -x "$KANATA_BIN" ]] && \
   "$KANATA_BIN" --version 2>/dev/null | grep -qF "${KANATA_VERSION#v}"; then
  echo "      already at $KANATA_VERSION, skipping download"
else
  if [[ "$KANATA_VERSION" == "latest" ]]; then
    DOWNLOAD_URL="https://github.com/jtroo/kanata/releases/latest/download/linux-binaries-x64.zip"
  else
    DOWNLOAD_URL="https://github.com/jtroo/kanata/releases/download/${KANATA_VERSION}/linux-binaries-x64.zip"
  fi
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  curl -fL --retry 3 -o "$tmpdir/linux-binaries-x64.zip" "$DOWNLOAD_URL"
  unzip -q "$tmpdir/linux-binaries-x64.zip" kanata_linux_x64 -d "$tmpdir"
  if [[ -n "$KANATA_SHA256" ]]; then
    echo "      verifying sha256"
    echo "$KANATA_SHA256  $tmpdir/kanata_linux_x64" | sha256sum -c - >/dev/null
  fi
  sudo install -m 0755 -o root -g root "$tmpdir/kanata_linux_x64" "$KANATA_BIN"
  rm -rf "$tmpdir"
  trap - EXIT
fi

echo "[2/6] Creating uinput group and adding $USER to input,uinput"
getent group uinput >/dev/null || sudo groupadd uinput
sudo usermod -aG input,uinput "$USER"

echo "[3/6] Loading uinput kernel module and persisting it"
echo 'uinput' | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
sudo modprobe uinput

echo "[4/6] Installing udev rule for /dev/uinput access"
sudo tee /etc/udev/rules.d/70-kanata.rules >/dev/null <<'EOF'
# Give the uinput group read/write access to /dev/uinput so kanata can
# create its virtual output device without running as root.
KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "[5/6] Writing config dir and systemd user unit"
mkdir -p "$CONFIG_DIR" "$(dirname "$UNIT_PATH")"

cat >"$UNIT_PATH" <<'EOF'
[Unit]
Description=Kanata keyboard remapper
Documentation=https://github.com/jtroo/kanata
After=graphical-session.target
PartOf=graphical-session.target
# Config comes from the dotfiles repo via stow. Without it, skip the unit
# rather than restart-looping.
ConditionPathExists=%h/.config/kanata/mauMap.kanata.kbd

[Service]
Type=simple
# --no-wait skips kanata's "Press enter to exit" prompt on a fatal error.
# It only exits without the flag because StandardInput defaults to null and
# the prompt reads EOF; with any real stdin it would hang and Restart=
# on-failure would never fire. Upstream recommends it for service use.
ExecStart=/usr/local/bin/kanata --cfg %h/.config/kanata/mauMap.kanata.kbd --no-wait
Restart=on-failure
RestartSec=2

# --- Hardening (user-mode systemd) -----------------------------------------
# Only directives that work without root are enabled. Anything requiring
# capability manipulation or kernel-namespace setup would fail this unit
# with status=218/CAPABILITIES.
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
RestrictNamespaces=true
RestrictRealtime=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictAddressFamilies=AF_UNIX
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @mount @swap @reboot @cpu-emulation @obsolete
UMask=0077
# Omitted (require root / system-mode unit):
#   CapabilityBoundingSet, AmbientCapabilities, RestrictSUIDSGID,
#   ProtectKernel{Tunables,Modules,Logs}, ProtectControlGroups, ProtectClock,
#   ProtectHostname, ProtectProc, PrivateNetwork, DeviceAllow, DevicePolicy

[Install]
# Manually started by default. For auto start: Uncomment WantedBy and systemctl --user enable kanata.service
# WantedBy=default.target
EOF

systemctl --user daemon-reload

echo "[6/6] Ensuring the compose key xkb option is set"
# The config's arrows layer emits `cmps` (KEY_COMPOSE). X and Wayland alias that
# keycode to <MENU>, which the default layout binds to Menu — not Multi_key — so
# compose sequences silently do nothing without an xkb option.
#
# compose:menu is used rather than compose:ralt so that an existing lv3:ralt_alt
# (Right Alt as level-3 shift for accented characters) keeps working.
XKB_OPTION="compose:menu"
if command -v gsettings >/dev/null; then
  current=$(gsettings get org.gnome.desktop.input-sources xkb-options 2>/dev/null || echo "@as []")
  if [[ "$current" == *"'$XKB_OPTION'"* ]]; then
    echo "      $XKB_OPTION already set"
  elif [[ "$current" == "@as []" || "$current" == "[]" ]]; then
    gsettings set org.gnome.desktop.input-sources xkb-options "['$XKB_OPTION']"
    echo "      set xkb-options to ['$XKB_OPTION']"
  else
    gsettings set org.gnome.desktop.input-sources xkb-options "${current%]}, '$XKB_OPTION']"
    echo "      appended $XKB_OPTION to ${current}"
  fi
else
  echo "      gsettings not found, skipping (set $XKB_OPTION manually)"
fi

cat <<EOF

=== Done ===
To use:
  1. Log out and back in   (for input/uinput group membership to apply)
  2. Stow the config from ~/.dotfiles:
       stow -vt ~/.config kanata
     This links $CONFIG_FILE
  3. Start the service:    systemctl --user start kanata.service

See 11_kanata.md for verification steps and troubleshooting.
EOF
