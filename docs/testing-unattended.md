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
```

`group_vars/all.yml` holds the real controller key, so the scenarios override it
with `-e @logs/<file>` to get a key whose private half is in the VM.
`server_admin_user` is empty there too, and every `local-server` or `servers` run
needs `-e @logs/vm-admin-user.yml`. Between scenarios, reset the account:

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
| H | A missing or unknown admin user is *red*, and early | `local-server -- -i localhost, -c local` with no `server_admin_user`, then `-e server_admin_user=nosuchuser` | Exits 2 at `server_syncthing`, before NodeSource is touched (`grep -c nodesource` of the log is 0) |
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
- `systemctl is-active syncthing@ubuntu` is `active`; its process runs as `ubuntu`.
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

## Cleanup

`rm logs/vm-*.yml logs/vm-inventory.ini`, then `scripts/test-vm.sh destroy`.
