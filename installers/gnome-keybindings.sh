#!/usr/bin/env bash
#
## Disable Gnome's default keybindings to switch-to-application and app-hotkeys
# Avoids keybinding conflicts when switching between workspaces
# Source: https://unix.stackexchange.com/questions/677878/supernumber-key-combos-remapping-in-gnome-40-switch-workspaces-instead-of-laun
#
# Idempotent: setting a key to the value it already holds is a no-op.
#
# Usage:  ./6_gnome-no-hotkey.sh

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

command -v gsettings >/dev/null || {
  echo "gsettings not found — this script only applies to a GNOME session." >&2
  exit 1
}

# dash-to-dock is a separate extension and is often not installed. Its schema
# has to be probed before writing: with set -e in place, a gsettings call
# against a missing schema would abort the whole script partway through.
if gsettings list-schemas | grep -qx "org.gnome.shell.extensions.dash-to-dock"; then
  dash_to_dock=true
else
  dash_to_dock=false
  echo "dash-to-dock schema not present, skipping its app-hotkey bindings."
fi

for i in {1..9}; do
  gsettings set "org.gnome.shell.keybindings" "switch-to-application-${i}" "[]"
  gsettings set "org.gnome.desktop.wm.keybindings" "switch-to-workspace-${i}" "['<Super>${i}']"
  gsettings set "org.gnome.desktop.wm.keybindings" "move-to-workspace-${i}" "['<Super><Shift>${i}']"
  if [[ $dash_to_dock == true ]]; then
    gsettings set "org.gnome.shell.extensions.dash-to-dock" "app-hotkey-${i}" "[]"
  fi
done

echo "Done. Super+1..9 switches workspaces; Super+Shift+1..9 moves windows."
