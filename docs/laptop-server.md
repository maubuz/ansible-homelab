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
scripts/run-playbook.sh --unattended servers -- --limit x230server.local
```

Laptop servers are managed by push only. `local-server.yml` (the pull entry
point) does not apply `server_laptop`, and `ansible-pull` never reads
`group_vars/laptop_servers.yml`.

## Before the first apply

A read-only preflight shows what the role will do before it first changes the
machine. Run it after the `server` role, so the host has the `ansiblebot` account
(root, passwordless):

```sh
scripts/run-playbook.sh --unattended preflight-laptop-server -- --limit <host>
```

It does four things, and stops with a message at the first problem:

1. Runs the role's own early checks: GRUB is the bootloader, the base GRUB defaults
   do not set `consoleblank`, and the value is a whole number. Another drop-in that
   sets it only warns.
2. Checks that `/boot` has room for `update-grub` (`server_laptop_preflight_min_boot_mib`).
3. **Dry-runs the GRUB change.** It renders the role's own drop-in, asks
   `grub-mkconfig` what it would generate without it (an already installed copy, with
   any value, is left out) and with it, and requires that
   the only difference is one added `consoleblank=<n>` on each normal-boot `linux`
   line and that `grub-script-check` accepts the result. It prints a warning when
   today's `grub.cfg` is out of date (a hand edit, a new kernel): `update-grub`
   would apply that too.
4. Saves a recovery baseline on the controller in
   `logs/preflight-<host>-<timestamp>/`: `grub-dry-run.txt` (the diffs) and
   `files/` with `/etc/default/grub`, its drop-ins and `grub.cfg` as they are now.

Nothing on the host is changed. The dry run happens in a private mount namespace
(`unshare -m`) with a temporary copy of `/etc/default/grub.d`, `grub-mkconfig`
prints to stdout, and `os-prober` is switched off inside it so no other disk is
probed. Only temporary files (in `/tmp` and `~/.ansible/tmp`) are written, and the
GRUB files are left byte-identical. To see what the rest of the role would change,
run the push with `--check --diff` as usual.

What it cannot check: the BIOS power-on option, airflow, the physical lid, and the
panel going dark. Those are the hand tests below.

## Assumptions

- Debian-family with systemd (asserted). Tested on Ubuntu 26.04.
- GRUB is the bootloader (asserted before anything is changed: `/etc/default/grub`
  and `update-grub` must exist). `/etc/default/grub` itself must not set
  `consoleblank`, or the run stops; another file in `/etc/default/grub.d/` that
  sets it only draws a warning, because the winner then depends on file order.
- Running on mains power, on Wi-Fi or wired. Battery health and heat are out of scope.
- The `server` role has run first, so the host has the `ansiblebot` account (root,
  passwordless). Everything that needs root, the preflight included, relies on it.
- Read-only means no change to configuration or state. Temporary files in `/tmp`
  and `~/.ansible/tmp` do not count, which is what lets a dry run write its work
  files.

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
| `server_laptop_grub_config_pattern` | a `linux` line with `consoleblank=<n>` as a whole word | The regex that tells whether the generated GRUB config has the wanted value, so `6` does not satisfy `60`. Derived from `server_laptop_consoleblank`; there is no reason to change it |
| `server_laptop_preflight_min_boot_mib` | `1` | Free MiB the preflight requires on `/boot`. `grub-mkconfig` writes the new config next to `grub.cfg` before copying it over, so the peak extra use is one `grub.cfg` (about 10 KiB); `df -m` cannot express less than 1 |

Changing the lid action and rerunning changes only the drop-in and restarts
`systemd-logind`. The restart also happens when logind does not use the configured
action, so a run that failed after writing the drop-in heals on the next run. Changing `server_laptop_consoleblank` changes only the GRUB
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

The paths in the commands below, and in Rollback, are the defaults of the variables above.
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
