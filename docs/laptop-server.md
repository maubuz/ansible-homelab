# Laptop servers

A **laptop server** is a server whose hardware is a laptop, kept running with the
lid closed on mains power. It is a server first: it gets the `server` role like
any other, then the `server_laptop` role on top.

The role sets the **lid action** to `ignore`, masks the sleep targets, and turns
on **console blanking**: after 60 s (the default) without input the text console blanks and the
panel goes dark. Blanking is a kernel boot parameter, so it needs a reboot, which
the role reports but never does (see [Pending reboot](#pending-reboot)).

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
- GRUB is the bootloader (asserted before anything is changed: `/etc/default/grub`
  and `update-grub` must exist). `/etc/default/grub` itself must not set
  `consoleblank`, or the run stops; another file in `/etc/default/grub.d/` that
  sets it only draws a warning, because the winner then depends on file order.
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
| `server_laptop_consoleblank` | `60` | Seconds without input before the console blanks (whole number; `0` turns blanking off) |
| `server_laptop_grub_dropin` | `/etc/default/grub.d/90-server-laptop.cfg` | The GRUB drop-in the role owns |
| `server_laptop_grub_defaults`, `_grub_dropin_dir`, `_grub_config`, `_consoleblank_running` | `/etc/default/grub`, `/etc/default/grub.d`, `/boot/grub/grub.cfg`, the sysfs `consoleblank` file | Paths the role reads; there is no reason to change them |

Changing the lid action and rerunning changes only the drop-in and restarts
`systemd-logind`. Changing `server_laptop_consoleblank` changes only the GRUB
drop-in, runs `update-grub` and reports a pending reboot.

## Pending reboot

The drop-in appends `consoleblank=<n>` to `GRUB_CMDLINE_LINUX_DEFAULT`, so the
setting reaches the kernel only at the next boot. Every run ends this part with
one of two messages, by comparing `/sys/module/kernel/parameters/consoleblank`
(what the running kernel uses) with the wanted value:

- `PENDING REBOOT: the running kernel has consoleblank=0, GRUB is set to 60. ...` (with the default)
- `OK: the running kernel already uses consoleblank=60.`

Because it reads the running kernel, the report is the same on the second run as
on the run that changed the file, until you reboot. It never reboots: pick the
moment yourself with `sudo reboot`. The parameter goes on the normal boot entries
only, so a host booted into a recovery entry keeps reporting a pending reboot.

`update-grub` runs when the drop-in changes, and also whenever the generated
`/boot/grub/grub.cfg` lacks the wanted value. So a run that wrote the drop-in and
then failed heals itself on the next run, with no template change needed.

## Verification

The role checks itself at the end of a run (tag `server_laptop_verify`). By hand:

```sh
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target   # masked x4
grep -c consoleblank=60 /boot/grub/grub.cfg                  # generated config has it (non-zero)
cat /sys/module/kernel/parameters/consoleblank               # 60 once rebooted
```

`HandleLidSwitchExternalPower` and `HandleLidSwitchDocked` should read `s "ignore"`
too. Closing the lid on the real machine and watching it stay up, and the panel
going fully dark when idle, are hand tests (see [testing.md](testing.md)). The X230
passes the second: its backlight (`/sys/class/backlight/intel_backlight`) goes off
under `consoleblank`, so no `bl_power` hook is needed.

## Rollback

```sh
sudo rm /etc/systemd/logind.conf.d/90-server-laptop.conf
sudo systemctl restart systemd-logind
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo rm /etc/default/grub.d/90-server-laptop.cfg
sudo update-grub
grep -c consoleblank /boot/grub/grub.cfg    # 0 once it is gone
```

Console blanking stays in effect until the next reboot after that.

Also remove the host from `[laptop_servers]`, or the next run puts it all back.

## No battery test

The design assumes the battery is removed. Nothing here tests how the machine
behaves on a failing or low battery.
