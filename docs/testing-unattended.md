# Testing unattended mode in the VM

The `ansiblebot` role, `playbooks/servers.yml`, `local.yml` and `local-server.yml`
decide who gets a root-equivalent account, and the `server` role they apply
(`roles/server/meta/main.yml`) installs the server tooling too, so a green run
takes several minutes. Test them in the VM as described in `docs/testing.md`; this
file adds the fixtures and the scenarios. Every row below runs twice and must
converge, and every scenario needs *red* where marked red.

## Fixtures

Throwaway keys are made inside the VM, and only their public halves reach `logs/`:

```sh
t=scripts/test-vm.sh
$t exec ssh-keygen -q -t ed25519 -N '' -f /home/ubuntu/test_a -C test-a
$t exec ssh-keygen -q -t ed25519 -N '' -f /home/ubuntu/test_b -C test-b
printf 'ansiblebot_keys:\n  - "%s"\n' "$($t exec cat /home/ubuntu/test_a.pub)" > logs/vm-keys-a.yml
printf 'ansiblebot_keys:\n  - "%s"\n  - "%s"\n' "$($t exec cat /home/ubuntu/test_a.pub)" \
  "$($t exec cat /home/ubuntu/test_b.pub)" > logs/vm-keys-ab.yml
printf 'server_admin_user: ubuntu\n' > logs/vm-admin-user.yml
printf 'server_syncthing_users:\n  - alice\n  - bob\n' > logs/vm-syncthing.yml
for u in alice bob carol; do $t exec --root useradd -m $u; done
```

`group_vars/all.yml` holds the real controller key, so the scenarios override it
with `-e @logs/<file>` to get a key whose private half is in the VM.
`server_admin_user` is `mau` there, which does not exist in the VM, so every
`local-server` or `servers` run needs `-e @logs/vm-admin-user.yml`. Add
`-e @logs/vm-syncthing.yml` to get the personal instances. Between scenarios, reset the account:

```sh
$t exec --root userdel -r ansiblebot; $t exec --root groupdel ansiblebot
$t exec --root rm -f /etc/sudoers.d/ansiblebot
```

Pull-style runs point the playbook at a generated one-host inventory, as
`ansible-pull` does: `-- -i localhost, -c local`.

## Scenarios

Run `$t run <playbook> -- <args>`; check with `$t exec`.

| # | Scenario | Playbook and args | Green when |
| --- | --- | --- | --- |
| A | A desktop's pull never creates the account | `local.yml -- -i localhost, -c local` | Converges. `getent passwd ansiblebot` exits 2; `/etc/sudoers.d/ansiblebot` is absent |
| B | An empty key list is *red* | `local-server -- -i localhost, -c local -e '{"ansiblebot_keys": []}' -e @logs/vm-admin-user.yml` (JSON: `-e ansiblebot_keys=[]` passes the string `[]`) | Exits 2 at `ansiblebot : Check the required variables are set`; existing keys untouched |
| H | A missing or unknown admin user, or an unknown user in `server_syncthing_users`, is *red*, and early | `local-server -- -i localhost, -c local` with `-e server_admin_user=` (empty), then `-e server_admin_user=nosuchuser`, then `-e @logs/vm-admin-user.yml -e '{"server_syncthing_users": ["nosuchuser"]}'` | Exits 2 at `server_syncthing`, naming the user, before NodeSource is touched (`grep -c nodesource` of the log is 0) |
| C | A pull creates the account and the server tooling | `local-server -- -i localhost, -c local -e @logs/vm-keys-a.yml -e @logs/vm-admin-user.yml` | Converges, and the machine check below passes. `passwd -S ansiblebot` shows `L`, shell `/bin/bash`, `id` lists only its own group, `authorized_keys` holds exactly key A, `visudo -c` is clean, `sudo -l -U ansiblebot` shows `NOPASSWD: ALL`, the sudoers file is `440 root:root` |
| D | Keys are exclusive | C with `vm-keys-ab.yml`, then with `vm-keys-a.yml` | After the first, A and B are authorized; after the second only A |
| E | A legacy account is repaired | `exec --root useradd -r -m -G root -s /bin/sh ansiblebot` plus a stale key in its `authorized_keys`, then C | The root group is gone from `id`, the shell is `/bin/bash`, only key A remains |
| F | The controller path | see below | Converges as `ansiblebot`; `sshd` logs `Accepted publickey for ansiblebot` |
| P | A real pull | see below | `local.yml` creates no account; `local-server.yml` with keys and admin user converges; without the admin user, or with an empty key list, it is red as in H and B |

## C: machine check

The recap is not enough. As a fresh user with no profile (`$t exec --root useradd
-m probe`), `su - probe -c '<cmd>'` must find `node`, `npm`, `tsc`, `uv`, `rustc`,
`cargo`, `wezterm` and `tailscale`. Also check:

- `dpkg -S $(command -v node)` is `nodejs`, and `apt-cache policy nodejs` shows
  the `nodesource` candidate.
- `uv` is `/usr/local/bin/uv`, and `/opt/pipx` is root-owned and world-readable.
- `snap list nordvpn nvim` shows both, `nvim` as `classic`.
- `systemctl is-active syncthing@syncthing` is `active` and its process runs as `syncthing`; with `vm-syncthing.yml`, `syncthing@alice` and `@bob` run as themselves (`ps -o user= -C syncthing`). Details are in "S: Syncthing" below.
- `/etc/apt/sources.list.d/` holds `nodesource`, `wezterm` and `tailscale`
  `.sources` files.

Then run the `desktop` playbook twice (`$t run desktop`): it shares the baseline
snaps with the server role and must still converge.

## P: a real pull

`ansible-pull` clones from git and sees only commits. Before committing, build a
throwaway repository from the working tree inside the VM; your own repository is
untouched:

```sh
$t exec bash -c 'rm -rf ~/pullsrc ~/pull-checkout && mkdir ~/pullsrc \
  && tar -C ~/ansible-homelab --exclude=.git --exclude=./logs -cf - . | tar -C ~/pullsrc -xf - \
  && cd ~/pullsrc && git init -q -b main && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm test'
v=/home/ubuntu/ansible-homelab/logs
$t exec ansible-pull -U file:///home/ubuntu/pullsrc -d /home/ubuntu/pull-checkout local.yml
$t exec ansible-pull -U file:///home/ubuntu/pullsrc -d /home/ubuntu/pull-checkout local-server.yml \
  -e @$v/vm-keys-a.yml -e @$v/vm-admin-user.yml    # twice; the second shows changed=0
```

After a commit, `-U file:///home/ubuntu/ansible-homelab` works the same way.

## F: controller path

The VM is both controller and target, over SSH to `127.0.0.1`. Key B plays the
admin's key, key A the `ansiblebot` key.

```sh
$t exec bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat ~/test_b.pub >> ~/.ssh/authorized_keys \
  && ssh -i ~/test_b -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new ubuntu@127.0.0.1 true'
printf '[servers]\n127.0.0.1\n' > logs/vm-inventory.ini
printf 'ansible_ssh_private_key_file: /home/ubuntu/test_b\n' > logs/vm-admin.yml
printf 'ansible_ssh_private_key_file: /home/ubuntu/test_a\n' > logs/vm-bot.yml
inv="-i inventory.ini -i logs/vm-inventory.ini -e @logs/vm-keys-a.yml -e @logs/vm-admin-user.yml"

# 1. First bootstrap as the admin (README step 4)
$t run servers -- $inv -e ansible_user=ubuntu -e @logs/vm-admin.yml
# 2. README step 5: the bot logs in, and the admin key is refused
$t exec ssh -i /home/ubuntu/test_a -o IdentitiesOnly=yes ansiblebot@127.0.0.1 sudo -n true
$t exec ssh -i /home/ubuntu/test_b -o IdentitiesOnly=yes -o BatchMode=yes ansiblebot@127.0.0.1 true   # must exit 255
# 3. Unattended, twice (second run changed=0)
$t run --unattended servers -- $inv -e @logs/vm-bot.yml
```

`-i inventory.ini` stays first so `group_vars/` keeps loading; `ansible_user:
ansiblebot` then comes from `group_vars/servers.yml`. On the host, the wrapper
must still exit 2 for `servers` with no terminal and no `--unattended`:
`scripts/run-playbook.sh servers --check -- --limit nomatch </dev/null`.

## S: Syncthing

The `server_syncthing` role has its own scenarios. To iterate on it without the
whole `server` role, put `- hosts: all` / `become: false` / `roles: [server_syncthing]`
in `logs/vm-st.yml` and run it inside the VM:
`$t exec ansible-playbook -i localhost, -c local logs/vm-st.yml -e @logs/vm-admin-user.yml -e @logs/vm-syncthing.yml`.
Always finish with the full C run, twice.

| # | Scenario | Green when |
| --- | --- | --- |
| S1 | Converge, twice | Run 1 `failed=0`; run 2 `changed=0`, including the `cli` get-then-set tasks and group membership |
| S2 | Accounts and units | `syncthing` is a system uid with shell `nologin` and `passwd -S` `L`. The system instance runs as `syncthing`, `@alice` and `@bob` as themselves. `syncthing@ubuntu` and `@carol` are not enabled |
| S3 | Sandbox | `systemctl show syncthing@syncthing -p ProtectHome,ProtectSystem,ReadWritePaths,UMask`; with `nsenter -t <pid> -m`, `touch /etc/x` fails and a write under `/srv/syncthing` works. `systemd-analyze security` gives about 2.8 (system) and 8.3 (personal) |
| S4 | Data privacy | `/srv/syncthing` is `0750 syncthing:syncthing`; `alice` and `carol` cannot list it, `ubuntu` can |
| S5 | Sockets | Each instance has `/run/syncthing-<name>/gui.sock`. `alice` reaches her own socket (200) and gets `000` on `bob`'s and the system's; a fresh login of `ubuntu` reaches the system socket. `ss -ltn` shows no `8384`. `ssh -L 18384:/run/syncthing-syncthing/gui.sock ubuntu@127.0.0.1` makes `curl http://localhost:18384/` work. Do not `pkill -f` the forward with the same pattern inside `bash -c` (it kills the shell) |
| S6 | Temporary admin | `sudo gpasswd -a carol syncthing`; a login of `carol` reaches the socket. Re-run: `carol` is gone, `ubuntu` stays, and the next run is `changed=0` |
| S7 | Network settings | On the system instance `global-ann-enabled`, `relays-enabled` and `natenabled` are `false` and `local-ann-enabled` is `true`; personal instances still have defaults (`cli` calls as `runuser -u <user> -- env STGUIADDRESS=unix:///run/syncthing-<user>/gui.sock syncthing cli config options <name> get`) |
| S8 | End to end | Pair `alice` with the system instance over `cli`. A file created in the shared folder reaches her; a local edit in her Receive Only folder does not flow back; `bob` never gets the folder; with trash-can versioning, a deletion from a Send & Receive share lands in `.stversions` |
| S9 | Ports and reboot | Personal instances got ports other than `22000`. After `lxc restart ansible-test`, every instance is active and `journalctl -b -u 'syncthing@*' \| grep -ci 'address already in use'` is 0 |
| S10 | Removal and legacy | `systemctl enable --now syncthing@ubuntu`, then run with only `bob` listed: `@ubuntu` and `@alice` are stopped and disabled, `~alice/.local/state/syncthing` is intact (check as root), and the next run is `changed=0` |
| S11 | Fresh install | Purge `syncthing`, delete the `syncthing` user, group, `/srv/syncthing` and the drop-ins, then run C twice: the first-install path converges, `/var/lib/syncthing` has no `Sync` folder |

## Cleanup

`rm logs/vm-*.yml logs/vm-inventory.ini`, then `scripts/test-vm.sh destroy`.
