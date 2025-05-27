#!/bin/bash

## Disable Gnome's default keybindings to switch-to-application and app-hotkeys
# Avoids keybinding conflicts when switching between workspaces
# Source: https://unix.stackexchange.com/questions/677878/supernumber-key-combos-remapping-in-gnome-40-switch-workspaces-instead-of-laun

for i in {1..9}; do 
  gsettings set "org.gnome.shell.keybindings" "switch-to-application-${i}" "[]"
  gsettings set "org.gnome.desktop.wm.keybindings" "switch-to-workspace-${i}" "['<Super>${i}']"
  gsettings set "org.gnome.desktop.wm.keybindings" "move-to-workspace-${i}" "['<Super><Shift>${i}']"
  gsettings set "org.gnome.shell.extensions.dash-to-dock" "app-hotkey-${i}" "[]"
done
