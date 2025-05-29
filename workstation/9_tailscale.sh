#!/bin/bash

## Based on official install from https://tailscale.com/kb/1476/install-ubuntu-2404

# Source distribution name $VERSION_CODENAME into shell
. /etc/os-release
CODENAME="${VERSION_CODENAME}"
tailscale_keyring_file="/usr/share/keyrings/tailscale-archive-keyring.gpg"
tailscale_list_file="/etc/apt/sources.list.d/tailscale.list"

if [ -f "${tailscale_keyring_file}" ] && [ -f "${tailscale_list_file}" ]; then
    echo "Tailscale keyring and list files already exists. Skipping keyring and apt list installation."
else
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.noarmor.gpg" | sudo tee "${tailscale_keyring_file}" >/dev/null
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.tailscale-keyring.list" | sudo tee "${tailscale_list_file}"
fi

sudo apt-get update
sudo apt-get install tailscale

sudo tailscale up
