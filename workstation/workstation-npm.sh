#! /bin/bash
#
# Install NVM and NPM LTS
# Mauricio Buschinelli. Created: Feb 2024. Last modified: ??
#
# TODO convert this script to an Ansible playbook


# Install and configure NVM from official instructions
# https://github.com/nvm-sh/nvm?tab=readme-ov-file#installing-and-updating
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

source ~/.bashrc

nvm install --lts

npm install -g typescript

