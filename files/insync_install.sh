#! /bin/bash
#
# Mauricio Buschinelli, Feb 2024
#
# Install script for Insync as per official documentation on https://www.insynchq.com/downloads/linux#apt

# STEP 1: Add our public GPG key to allow apt to authenticate the Insync repository
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ACCAF35C

# STEP 2: Create a file /etc/apt/sources.list.d/insync.list with the following content
echo "deb http://apt.insync.io/ubuntu mantic non-free contrib" | sudo tee /etc/apt/sources.list.d/insync.list

# STEP 3: Update the apt repository
sudo apt-get update -y

# STEP 4: Install Insync
sudo apt-get install insync -y

