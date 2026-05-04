#!/usr/bin/env bash
# Install and configure kanata on a fresh Ubuntu 24.04 Desktop.
#
# Idempotent: re-running updates the binary, refreshes the udev rule, and
# rewrites the systemd user unit. Run as a normal user — sudo is invoked
# only for the steps that need it.
#
# Usage:  ./install-kanata.sh
#         KANATA_VERSION=v1.11.0 ./install-kanata.sh  # pin a specific version

set -euo pipefail

# Specify specific version tag or default to latest
KANATA_VERSION="${KANATA_VERSION:-latest}"
KANATA_BIN="/usr/local/bin/kanata"
CONFIG_DIR="$HOME/.config/kanata"
CONFIG_FILE="$CONFIG_DIR/mauMap.kanata.kbd"
UNIT_PATH="$HOME/.config/systemd/user/kanata.service"

if [[ $EUID -eq 0 ]]; then
  echo "Do not run as root. The script will sudo for the steps that need it." >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    echo "Warning: this script targets Ubuntu 24.04 (detected ${PRETTY_NAME:-unknown})." >&2
  fi
fi

echo "[1/5] Installing kanata $KANATA_VERSION to $KANATA_BIN"
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
  sudo install -m 0755 -o root -g root "$tmpdir/kanata_linux_x64" "$KANATA_BIN"
  rm -rf "$tmpdir"
  trap - EXIT
fi

echo "[2/5] Creating uinput group and adding $USER to input,uinput"
getent group uinput >/dev/null || sudo groupadd uinput
sudo usermod -aG input,uinput "$USER"

echo "[3/5] Loading uinput kernel module and persisting it"
echo 'uinput' | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
sudo modprobe uinput

echo "[4/5] Installing udev rule for /dev/uinput access"
sudo tee /etc/udev/rules.d/70-kanata.rules >/dev/null <<'EOF'
# Give the uinput group read/write access to /dev/uinput so kanata can
# create its virtual output device without running as root.
KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "[5/5] Writing config dir and systemd user unit"
mkdir -p "$CONFIG_DIR" "$(dirname "$UNIT_PATH")"

cat >"$UNIT_PATH" <<'EOF'
[Unit]
Description=Kanata keyboard remapper
Documentation=https://github.com/jtroo/kanata
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kanata --cfg %h/.config/kanata/mauMap.kanata.kbd
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

cat <<EOF

=== Done ===
To use:
  1. Drop your config at:  $CONFIG_FILE
  2. Log out and back in   (for input/uinput group membership to apply)
  3. Start the service:    systemctl --user start kanata.service

If using compose-key sequences on GNOME Wayland, set the xkb option once
  gsettings set org.gnome.desktop.input-sources xkb-options "['compose:ralt']"
Note that setxkbmap is not persistent on Wayland
EOF
