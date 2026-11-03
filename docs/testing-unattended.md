# Testing unattended mode in the VM

The `ansiblebot` role, `playbooks/servers.yml`, `local.yml` and `local-server.yml`
decide who gets a root-equivalent account. Test them in the VM as described in
`docs/testing.md`; this file adds the fixtures and the scenarios. Every row below
runs twice and must converge, and every scenario needs *red* where marked red.

## Fixtures

Throwaway keys are made inside the VM, and only their public halves reach `logs/`:

```sh
t=scripts/test-vm.sh
$t exec ssh-keygen -q -t ed25519 -N '' -f /home/ubuntu/test_a -C test-a
$t exec ssh-keygen -q -t ed25519 -N '' -f /home/ubuntu/test_b -C test-b
printf 'ansiblebot_keys:\n  - "%s"\n' "$($t exec cat /home/ubuntu/test_a.pub)" > logs/vm-keys-a.yml
printf 'ansiblebot_keys:\n  - "%s"\n  - "%s"\n' "$($t exec cat /home/ubuntu/test_a.pub)" \
  "$($t exec cat /home/ubuntu/test_b.pub)" > logs/vm-keys-ab.yml
```

`ansiblebot_keys` is empty in `group_vars/all.yml`, so it is supplied with
`-e @logs/<file>` on each run. Between scenarios, reset the account:

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
| B | An empty key list is *red* | `local-server -- -i localhost, -c local` | Exits 2 at the `Check the required variables are set` task; no account exists afterwards |
| C | A pull creates the account | `local-server -- -i localhost, -c local -e @logs/vm-keys-a.yml` | Converges. `passwd -S ansiblebot` shows `L`, shell `/bin/bash`, `id` lists only its own group, `authorized_keys` holds exactly key A, `visudo -c` is clean, `sudo -l -U ansiblebot` shows `NOPASSWD: ALL`, the sudoers file is `440 root:root` |
| D | Keys are exclusive | C with `vm-keys-ab.yml`, then with `vm-keys-a.yml` | After the first, A and B are authorized; after the second only A |
| E | A legacy account is repaired | `exec --root useradd -r -m -G root -s /bin/sh ansiblebot` plus a stale key in its `authorized_keys`, then C | The root group is gone from `id`, the shell is `/bin/bash`, only key A remains |
| F | The controller path | see below | Converges as `ansiblebot`; `sshd` logs `Accepted publickey for ansiblebot` |
| P | A real pull (after a commit) | `exec ansible-pull -U file:///home/ubuntu/ansible-homelab -d /home/ubuntu/pull-checkout <local.yml or local-server.yml> [-e @/home/ubuntu/ansible-homelab/logs/vm-keys-a.yml]` | `local.yml` creates no account; `local-server.yml` with keys converges; without keys it is red as in B |

## F: controller path

The VM is both controller and target, over SSH to `127.0.0.1`. Key B plays the
admin's key, key A the `ansiblebot` key.

```sh
$t exec bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat ~/test_b.pub >> ~/.ssh/authorized_keys \
  && ssh -i ~/test_b -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new ubuntu@127.0.0.1 true'
printf '[servers]\n127.0.0.1\n' > logs/vm-inventory.ini
printf 'ansible_ssh_private_key_file: /home/ubuntu/test_b\n' > logs/vm-admin.yml
printf 'ansible_ssh_private_key_file: /home/ubuntu/test_a\n' > logs/vm-bot.yml
inv="-i inventory.ini -i logs/vm-inventory.ini -e @logs/vm-keys-a.yml"

# 1. First bootstrap as the admin (README step 4)
$t run servers -- $inv -e ansible_user=ubuntu -e @logs/vm-admin.yml
# 2. README step 5: the bot logs in, and the admin key is refused
$t exec ssh -i /home/ubuntu/test_a -o IdentitiesOnly=yes ansiblebot@127.0.0.1 sudo -n true
$t exec ssh -i /home/ubuntu/test_b -o IdentitiesOnly=yes -o BatchMode=yes ansiblebot@127.0.0.1 true   # must exit 255
# 3. Unattended, twice (second run changed=0)
$t run --unattended servers -- $inv -e @logs/vm-bot.yml
```

`-i inventory.ini` stays first so `group_vars/` keeps loading; `ansible_user:
ansiblebot` then comes from `group_vars/servers.yml`.

## Cleanup

`rm logs/vm-*.yml logs/vm-inventory.ini`, then `scripts/test-vm.sh destroy`.
