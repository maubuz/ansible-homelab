#!/bin/bash

brave_keyring_url="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
brave_keyring_path="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
brave_source_list="/etc/apt/sources.list.d/brave-browser-release.list"

if [[ -f "$brave_keyring_path" ]]; then
  echo "Brave keyring already exists at $brave_keyring_path. Skipping download."
else
  echo "Downloading Brave keyring..."
  sudo curl -fsSLo "$brave_keyring_path" "$brave_keyring_url"
fi

if [[ -f "$brave_source_list" ]]; then
  echo "Brave source list already exists at $brave_source_list. Skipping creation."
else
  echo "Creating Brave source list..."
  echo "deb [signed-by=$brave_keyring_path] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee "$brave_source_list"
  sudo apt update
  sudo apt install brave-browser
fi

# [Working] Ref: https://stackoverflow.com/questions/73289644/how-to-install-browser-extension-for-namely-brave-through-terminal
# Alt ref1: https://community.brave.com/t/installing-extensions-via-command-line/463730/2
# Alt ref2: https://github.com/brave/brave-browser/issues/23966

EXTENSIONS_PATH=/opt/brave.com/brave/extensions
sudo mkdir -p $EXTENSIONS_PATH

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
)

echo "Installing Brave/Chromium extensions..."
for ext in "${EXTENSIONS[@]}"; do
  if [[ -f "${EXTENSIONS_PATH}/${ext}.json" ]]; then
    echo "Extension $ext already installed. Skipping."
  else
    echo '{ "external_update_url": "https://clients2.google.com/service/update2/crx" }' | sudo tee "${EXTENSIONS_PATH}/${ext}.json"
  fi
done
