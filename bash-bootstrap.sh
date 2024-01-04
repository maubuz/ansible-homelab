#! /bin/bash

##### Bootstrap script to prepare Linux system for running Ansible playbooks.


##### Determines if the Linux system is using apt (Ubuntu, Debian, etc) or dnf (Fedora) as the package manager
# Intended to be used in other scripts
#
# Example:
# ```sh
# source ./get-package-manager.sh
# PACKAGE_MANAGER=$(get-package-manager)
# sudo $PACKAGE_MANAGER update -y
# ```
function get-package-manager()
{
    if [ -f /etc/os-release ]; then
        # Assumes distribution is complient with freedesktop.org and systemd
        . /etc/os-release
        local OS_NAME=$NAME

        if [[ $OS_NAME = *"Ubuntu"* || $OS_NAME = *"Debian"* ]]; then
            PACKAGER="apt"
        elif [[ $OS_NAME = *"Fedora"* ]]; then
            PACKAGER="dnf"
        else
            echo "Could not determine the package manager. Exiting with error" >&2
            exit 1
        fi
    else
        # Fall back to detecting whether apt or dnf are installed 
        if which dnf > /dev/null; then
            PACKAGER="dnf"
        elif which apt > /dev/null; then
            PACKAGER="apt"
        else
            echo "Could not determine the package manager. Exiting with error" >&2
            exit 1
        fi
    fi

    echo $PACKAGER
}


#### Main script ####

INSTALL_PACKAGES=("git" "ansible")

PACKAGE_MANAGER="$(get-package-manager)"
echo "Using package manager $PACKAGE_MANAGER"

sudo "$PACKAGE_MANAGER" update -y
# For debugging
# sudo "$PACKAGE_MANAGER" install "${INSTALL_PACKAGES[@]}" --assumeno  # DNF specific
# sudo "$PACKAGE_MANAGER" install "${INSTALL_PACKAGES[@]}" --dry-run  # APT specific
# For production
sudo "$PACKAGE_MANAGER" install "${INSTALL_PACKAGES[@]}" -y


#### Run entrypoint playbook ####

ansible-playbook local.yml


