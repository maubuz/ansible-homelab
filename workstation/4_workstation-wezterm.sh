#! /bin/bash

# Instruction from wezterm website
# https://wezfurlong.org/wezterm/install/linux.html

if ! [[ -f /usr/share/keyrings/wezterm-fury.gpg ]]; then
  curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
else
  echo "WezTerm GPG key already exists"
fi
if ! [[ -f /etc/apt/sources.list.d/wezterm.list ]]; then
  echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
else
  echo "wezterm.list already exists"
fi

sudo apt update
sudo apt install wezterm
