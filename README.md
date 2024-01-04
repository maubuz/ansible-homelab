# ansible-homelab
Automated configuration of workstations, servers and containers in my home lab using Ansible.

## Bootstrap Requirements

In order to run `local.yml` for the first time, the following packages are required:

- git
- ansible

## Installation

1. Install required packages with:

   1. APT distro:

   ```sh
   sudo apt update -y && sudo apt install git ansible -y
   ```
   2. DNF distro:

     ```sh
     sudo dnf upgrade -y && sudo dnf install git ansible -y
     ```

 2. Use `ansible-pull` to run playbook `local.yml` directly from this repository:
    ```sh
    ansible-pull -U https://github.com/maubuz/ansible-homelab.git
    ```

    
