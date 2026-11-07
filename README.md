# ansible-homelab

Ansible configuration for my homelab. It provisions Ubuntu 24.04 and later
(26.04 preferred) on laptops with desktop environments, laptops running as
servers, GPU workstations and Raspberry Pis.

## Host types

| Host type | Inventory group | Mode | Status |
| --- | --- | --- | --- |
| Laptop or workstation with a desktop | `workstations` | Interactive | Working |
| Laptop server | `laptop_servers` (child of `servers`) | Unattended (controller only) | Working: `server` role plus `server_laptop` ([docs/laptop-server.md](docs/laptop-server.md)) |
| Raspberry Pi | `servers` | Unattended (pull or controller) | Working: the `server` role (see below) |
| GPU workstation, Raspberry Pi as its own type | own group + `group_vars` file | | Planned |

Interactive means a person at the machine types their sudo password. Unattended
means the `ansiblebot` account with passwordless sudo, started by `ansible-pull`
on the host or by a controller over SSH. See
[docs/execution-model.md](docs/execution-model.md).

## Setup

Install the bootstrap requirements:

```sh
sudo apt update -y && sudo apt install git ansible -y
```

Then, on the machine being configured, either:

```sh
git clone https://github.com/maubuz/ansible-homelab.git && cd ansible-homelab
scripts/run-playbook.sh workstation      # interactive: a workstation
```

or let a host pull and apply a playbook itself. A desktop or any host that needs
only package upgrades pulls `local.yml`; a server that should also get the
`ansiblebot` account pulls `local-server.yml`:

```sh
ansible-pull -U https://github.com/maubuz/ansible-homelab.git local-server.yml
```

`local-server.yml` grants passwordless root to the keys in `ansiblebot_keys`, so
never run it on a desktop. Pull needs a sudo password unless the user already has
passwordless sudo; add `--ask-become-pass` for an interactive first run.

or drive servers from another machine, as described next.

### Adding a server (from a controller)

A controller is any machine with this repository and an SSH route to the server,
such as a laptop on the same network. The server needs a fresh Ubuntu install, an
admin user with sudo, and SSH reachable from the controller.

1. **Once per controller:** create a dedicated key with a passphrase and load it
   into the agent. The `ansiblebot` account has passwordless sudo, so this key is
   effectively root on every server; the private half never leaves the controller.

   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_ansiblebot -C "ansiblebot@$(hostname)"
   ssh-add ~/.ssh/id_ed25519_ansiblebot
   ```

   Add the contents of `~/.ssh/id_ed25519_ansiblebot.pub` to `ansiblebot_keys`
   in `group_vars/all.yml`, one entry per controller. Commit it; public keys are
   not secret. Removing an entry revokes that key on the next `ansiblebot` run.

2. Let the controller log in as the admin user without a password, and accept the
   host key once, because `--unattended` cannot answer the prompt:

   ```sh
   ssh-copy-id <admin>@pi4.lan
   ssh <admin>@pi4.lan true
   ```

3. Add the host to `inventory.ini`:

   ```ini
   [servers]
   pi4.lan
   ```

4. Bootstrap it once as the admin user. This creates the `ansiblebot` account,
   installs the keys from `ansiblebot_keys`, grants passwordless sudo, upgrades
   packages, then installs everything in the `server` role. `server_admin_user`,
   who administers Syncthing, must already exist on the host, and so must every
   user in `server_syncthing_users` (see
   [docs/syncthing-server.md](docs/syncthing-server.md)).
   `group_vars/servers.yml` sets `ansible_user: ansiblebot`, which does not exist yet on a fresh host, so
   override it for this run:

   ```sh
   scripts/run-playbook.sh servers -- -e ansible_user=<admin> --ask-become-pass --limit pi4.lan
   ```

5. Check that `ansiblebot` works, then run unattended from now on:

   ```sh
   ssh ansiblebot@pi4.lan sudo -n true
   scripts/run-playbook.sh --unattended servers
   ```

   Add `-- --limit pi4.lan` to target one host.

Every host type gets the `baseline_*` packages and snaps in `group_vars/all.yml`.
A server gets them from the `server` role, which applies, in order: `bootstrap`,
`ansiblebot`, `server_syncthing`, `server_packages`, `server_python`,
`server_node`, `wezterm` and `tailscale`. These install system-wide, so every user
on the host has `node`, `uv` and the rest. Set `server_admin_user` in
`group_vars/all.yml` to the existing user who administers Syncthing, and list in
`server_syncthing_users` the users who each get their own Syncthing instance; the
run fails until the admin is set. Syncthing runs as a dedicated `syncthing`
account, with a GUI on a Unix socket per instance: see
[docs/syncthing-server.md](docs/syncthing-server.md). After the first run,
`sudo tailscale up` is still a manual step. See
[docs/execution-model.md](docs/execution-model.md).

## Layout

```
site.yml            every playbook, for every group
local.yml           ansible-pull entry point for any host; package upgrades only
local-server.yml    ansible-pull entry point for a server; adds the ansiblebot account
inventory.ini       hosts and groups
group_vars/         per-group values: package lists, GNOME extension list
playbooks/          one thin playbook per area; workstation.yml imports them in order
roles/              one role per area; apt_source is shared by wezterm, tailscale and server_node;
                    server_* roles are the system-wide counterparts of the per-user workstation roles
installers/         shell installers not yet converted to roles
scripts/            run-playbook.sh (the way to run playbooks), test-vm.sh
docs/               rationale and procedures, linked below
```

## Everyday commands

```sh
scripts/run-playbook.sh <name>            # run one playbook; name is any unique substring
scripts/run-playbook.sh --check <name>    # dry run
ansible-lint playbooks/ roles/ local.yml local-server.yml site.yml
scripts/test-vm.sh run <name>             # first-install path on a clean Ubuntu 26.04 VM
```

Every wrapped run is logged to `logs/`, and `logs/latest.log` is the one to hand
to someone (or something) helping to debug a failure.

## Docs

- [docs/running.md](docs/running.md): the wrapper, logs, credentials, dry runs, troubleshooting, linting
- [docs/testing.md](docs/testing.md): the throwaway VM, how to test a change, and what it cannot cover
- [docs/testing-unattended.md](docs/testing-unattended.md): VM scenarios for the `ansiblebot` account, keys, and the pull and controller paths
- [docs/execution-model.md](docs/execution-model.md): interactive vs unattended, running from a controller, adding a host type
- [docs/laptop-server.md](docs/laptop-server.md): laptop servers: lid action, sleep masking, tunables, rollback, BIOS prerequisite
- [docs/syncthing-server.md](docs/syncthing-server.md): Syncthing on servers: system and personal instances, reaching a GUI, pairing, admin access
- [docs/adr/](docs/adr/): recorded design decisions

## Contributing conventions

- Third-party APT repositories go through the `apt_source` role, not hand-rolled
  keyring tasks.
- Plays set `become: false` and roles put `become: true` on individual tasks.
- `workstation.yml` order matters in one place: `python` installs pipx, which
  `ansible-tools` and `gnome_extensions` need.
