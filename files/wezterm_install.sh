#! /bin/bash
#
# Mauricio Buschinelli, Feb 2024
#
# Install script for WezTerm terminal emulator. As per documentation on https://wezfurlong.org/wezterm/install/linux.html

curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg

echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list

sudo apt update -y
sudo apt install wezterm -y

