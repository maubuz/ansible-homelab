#! /bin/bash

# Instruction from wezterm website
# https://github.com/jesseduffield/lazygit?tab=readme-ov-file#ubuntu

LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf /tmp/lazygit.tar.gz lazygit

sudo install lazygit /usr/local/bin

