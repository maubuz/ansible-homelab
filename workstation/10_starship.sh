#!/bin/bash

## Fireship install with rust setup for eash updates
## From https://documentation.ubuntu.com/ubuntu-for-developers/howto/rust-setup/

# starship is in apt repos from 25.04 onwards
sudo apt update
if ! apt show starship &>/dev/null; then
  # Download binary
  curl -sS https://starship.rs/install.sh | sh
else
  sudo apt install -y starship
fi

# Add to bashrc if not already there
if ! grep -q 'starship init bash' ~/.bashrc; then
  echo 'eval "$(starship init bash)"' >>~/.bashrc
fi
