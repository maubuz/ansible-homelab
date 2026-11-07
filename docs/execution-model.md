# Execution model

Two modes, and three ways to start them.

| Mode | Who escalates | Started by | Applies |
| --- | --- | --- | --- |
| **Interactive** | The person at the machine, typing their sudo password | `scripts/run-playbook.sh <playbook>` on the target itself | `playbooks/workstation.yml` and its parts |
| **Unattended, pull** | `ansiblebot`, passwordless | `ansible-pull` on the target | `local-server.yml` (the `server` role), or `local.yml` (`bootstrap`) on a host that needs no account |
| **Unattended, controller** | `ansiblebot`, passwordless | `scripts/run-playbook.sh --unattended servers` from another machine, over SSH | `playbooks/servers.yml` (the `server` role) |

## Why plays never escalate

Plays set `become: false`; each role puts `become: true` on the tasks that need
root. Play-level `become` also applies to fact gathering, where `sudo -H`
rewrites `HOME` to `/root`, so any path built from `ansible_facts.env.HOME`
silently points at the wrong home.

`node`, `python`, `syncthing`, `opencode` and `gnome_extensions` install into the
home of whoever connects (nvm, `pipx ensurepath`, a user systemd service). That is
right for a person at a workstation and wrong for a daemon account: run as
`ansiblebot`, they would provision `/home/ansiblebot`. Servers therefore have
their own roles, which install system-wide and escalate per task:

| Workstation (per user) | Server (system-wide) |
| --- | --- |
| `desktop` (`desktop_*`) | `server_packages` (reads `baseline_*`) |
| `node`: nvm in `~/.nvm` | `server_node`: NodeSource apt repository, `/usr/bin/node` |
| `python`: uv in `~/.local` | `server_python`: uv in `/opt/pipx`, linked into `/usr/local/bin` |
| `syncthing`: user service | `server_syncthing`: system instance `syncthing@syncthing` plus `syncthing@<user>` personal instances |

`wezterm` and `tailscale` are plain apt installs and serve both sides. The two
sides never share a variable name; only `baseline_*` in `group_vars/all.yml` is
common, and each side composes its own list from it.

## The `server` role

`roles/server/meta/main.yml` lists everything a server gets, in order, and has no
tasks of its own. `playbooks/servers.yml` and `local-server.yml` both apply just
this role, so a pulling server and a controller-managed one cannot drift apart.
`server_syncthing` runs right after `ansiblebot` so a missing `server_admin_user`
(the person who administers Syncthing; a member of the `syncthing` group, not the
user it runs as) fails before the long installs. The model is in
[syncthing-server.md](syncthing-server.md). The wrapper follows these dependencies when it
decides whether a run escalates.

`ansible-pull` generates an inventory with no groups, so it never loads
`group_vars/servers.yml`. Values a server role needs on a pull (`baseline_*`,
`server_admin_user`, `server_syncthing_users`) live in `group_vars/all.yml` or the role's defaults.
Moving Node to a newer LTS line is a manual edit of `server_node_major`; nvm on
workstations follows the LTS by itself.

### Laptop servers

`playbooks/servers.yml` has a second play, `hosts: laptop_servers`, applying
`server_laptop`. `laptop_servers` is a child of `servers`, so those hosts get the
`server` role first. The role is not a dependency of `server`, and
`local-server.yml` does not apply it, so laptop servers are push only. See
[laptop-server.md](laptop-server.md).

`playbooks/preflight-laptop-server.yml` is a read-only entry point for the same
group (it runs `tasks/preflight.yml` of `server_laptop`). Run it after the `server`
role, so it connects as `ansiblebot` with passwordless root.

## The `ansiblebot` account

The `ansiblebot` role creates it: a system account with no password, authorized
SSH keys, and passwordless sudo via `/etc/sudoers.d/ansiblebot`.

Its keys come from `ansiblebot_keys` in `group_vars/all.yml`: one dedicated
public key per controller, each with the private half kept only on that
controller, ideally behind a passphrase and `ssh-agent`. The list is exclusive,
so it is the whole truth. Removing a key revokes it on the next `ansiblebot` run,
and the role refuses to run with an empty list rather than wipe every key.

The `ansiblebot` key is effectively root on every server, so a controller holds
the keys to all of them. `ansible-pull` avoids that concentration, since each
host holds its own credentials; prefer it for hosts that should not depend on
one machine.

Before adding a playbook to either unattended mode, make it escalate explicitly
or take its target user from an inventory variable instead of from the
connecting user's environment.

## Running with `ansible-pull`

`ansible-pull` runs on the host itself and generates an inventory holding only
that machine, so the playbooks use `hosts: all`. Two entry points:

| Entry point | Roles | Use on |
| --- | --- | --- |
| `local.yml` | `bootstrap` | Any host, desktops included. Upgrades packages and nothing more |
| `local-server.yml` | the `server` role | Servers only. Also creates the `ansiblebot` account and installs the server tooling |

The first pull on a server runs as an existing admin user, with a sudo password
(`--ask-become-pass`). It creates `ansiblebot`. Later pulls can run as `ansiblebot`
without a password, for example from a timer, and a controller can reach the host
over SSH as well. A pulling server and a controller-managed server therefore end
up in the same state, and a server can switch between the two.

`local-server.yml` is separate from `local.yml` because the account is
root-equivalent. A desktop that pulls `local.yml` can never get it, because no
role that run applies knows about it.

## Running from a controller

A controller is any machine with this repository and an SSH route to the target.

1. Generate this controller's key and add its public half to
   `ansiblebot_keys` (see "Adding a server" in the README).
2. Add the host under `[servers]` in `inventory.ini`.
3. Bootstrap it once with an existing admin account. `group_vars/servers.yml`
   sets `ansible_user: ansiblebot`, which does not exist yet on a fresh host, so
   override it. Extra vars beat inventory vars, and `--ask-become-pass` supplies
   the admin's sudo password:

   ```sh
   scripts/run-playbook.sh servers -- -e ansible_user=<admin> --ask-become-pass
   ```

4. From then on, connect as `ansiblebot` with no password:

   ```sh
   scripts/run-playbook.sh --unattended servers
   scripts/run-playbook.sh --unattended servers -- --limit pi4.lan
   ```

Use `playbooks/servers.yml` from a controller rather than `local-server.yml`. The
`local*.yml` playbooks target `hosts: all`, which would also match this
machine's own `localhost` entry in `[workstations]`.

`--unattended` makes the wrapper skip its sudo prompt. That prompt is decided
from the controller's own sudo policy, which says nothing about the remote
hosts. Without the flag, a controller with a password-protected sudo would ask
for a password the targets never need, and exit 2 with no terminal.

## Adding a host type

A host type that needs different packages or settings gets its own inventory
group and its own `group_vars/<group>.yml`. Roles read the values; they do not
branch on which kind of machine they are on.

For example, to point the `opencode` role at the arm64 build on Raspberry Pis
while laptops keep the x86_64 default:

```ini
[servers]
laptop-srv.lan

[raspberrypis]
pi4.lan
```

```yaml
# group_vars/raspberrypis.yml
opencode_supported_arch: aarch64
opencode_arch: arm64
```

The alternative is one role with `when: ansible_facts['architecture'] == 'aarch64'`
branches. That works for one difference and tangles at the third, because every
host type's behaviour ends up spread across every role.
