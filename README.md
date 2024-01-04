# ansible-homelab
Automated configuration of workstations, servers and containers in my home lab using Ansible.

## Bootstrap Requirements

In order to run `local.yml` for the first time, the following packages are required:

- git
- ansible

## Installation

1. Clone this repository or copy contents of `bash-bootstrap.sh` to a local script.

2. Run `bash-bootstrap.sh` in order to:

    2a. Install requirements listed above
    2b. Run `ansible-playbook local.yml`

