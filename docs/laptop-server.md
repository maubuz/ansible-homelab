# Laptop servers

A **laptop server** is a server whose hardware is a laptop, kept running with the
lid closed on mains power. It is a server first: it gets the `server` role like
any other, then the `server_laptop` role on top.

The role sets the **lid action** to `ignore` and masks the sleep targets. Console
blanking is not part of it yet.

## How a host becomes one

Put it under `[laptop_servers]` in `inventory.ini`. The group is a child of
`servers`, so the host gets the `server` role in the first play of
`playbooks/servers.yml` and `ansible_user: ansiblebot` from `group_vars/servers.yml`.
The second play (`hosts: laptop_servers`) then applies `server_laptop`. Group
membership is the only switch: there is no chassis check, so a VM can be a laptop
server for testing.

```sh
scripts/run-playbook.sh --unattended servers -- --limit x230.lan
```

Laptop servers are managed by push only. `local-server.yml` (the pull entry
point) does not apply `server_laptop`, and `ansible-pull` never reads
`group_vars/laptop_servers.yml`.

## Assumptions

- Debian-family with systemd (asserted). Tested on Ubuntu 26.04.
- Running on mains power. Battery health, heat and Wi-Fi are out of scope.

## Manual prerequisites

- **BIOS power-on**: enable the option that powers the machine on when AC
  returns, or a power cut leaves it off.
- Airflow around the closed laptop, and a wired network connection.

## Tunables

In `group_vars/laptop_servers.yml` (defaults in `roles/server_laptop/defaults/main.yml`):

| Variable | Default | Meaning |
| --- | --- | --- |
| `server_laptop_lid_action` | `ignore` | logind action for the lid on battery, AC and docked |
| `server_laptop_sleep_targets` | `sleep`, `suspend`, `hibernate`, `hybrid-sleep` `.target` | Units that are masked |
| `server_laptop_logind_dropin` | `/etc/systemd/logind.conf.d/90-server-laptop.conf` | The drop-in the role owns |

Changing the lid action and rerunning changes only the drop-in and restarts
`systemd-logind`.

## Verification

The role checks itself at the end of a run (tag `server_laptop_verify`). By hand:

```sh
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target   # masked x4
```

`HandleLidSwitchExternalPower` and `HandleLidSwitchDocked` should read `s "ignore"`
too. Closing the lid on the real machine and watching it stay up is a hand test
(see [testing.md](testing.md)).

## Rollback

```sh
sudo rm /etc/systemd/logind.conf.d/90-server-laptop.conf
sudo systemctl restart systemd-logind
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Also remove the host from `[laptop_servers]`, or the next run puts it all back.

## No battery test

The design assumes the battery is removed. Nothing here tests how the machine
behaves on a failing or low battery.
