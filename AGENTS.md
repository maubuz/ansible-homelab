# AGENTS.md

Ansible for a personal homelab. Targets Ubuntu 24.04+ only (26.04 preferred), across several host types: desktop laptop, laptop server, GPU workstation, Raspberry Pi. Each host type is an inventory group plus `group_vars/<group>.yml`; roles read the values and do not branch on machine kind. Human docs are in `README.md` and `docs/`.

## Execution modes
- **Interactive** (workstations): a person runs `scripts/run-playbook.sh` and types the sudo password. `node`, `opencode` and `gnome_extensions` install into the connecting user's `$HOME`.
- **Unattended** (servers): connects as `ansiblebot` with passwordless sudo, either via `ansible-pull local-server.yml` on the host or from a controller over SSH (`scripts/run-playbook.sh --unattended servers`). Both apply `bootstrap` + `ansiblebot` and nothing else. A playbook joins this mode only after it escalates explicitly or takes its target user from an inventory variable.
- Plays set `become: false`; roles set `become: true` per task. Play-level become turns `ansible_facts.env.HOME` into `/root`. Write the literal `become: true` (or `yes`), because the wrapper greps for it to decide whether to prompt for sudo.
- The `ansiblebot` account (root-equivalent) belongs only in `servers.yml` and `local-server.yml`, never in `local.yml` or a workstation playbook; `local.yml` is what desktops pull. The role fails unless `ansiblebot_keys` (group_vars/all.yml) is non-empty; its `authorized_key` is exclusive, so removing an entry revokes that key. Only public keys belong in the repo.
- From a controller, target `playbooks/servers.yml`; `local*.yml` use `hosts: all` and would also match `localhost`.
→ Before changing escalation, `$HOME` paths or the unattended set, read `docs/execution-model.md`.

## Running
- Run playbooks through `scripts/run-playbook.sh <substring>`: one playbook per run, ansible args after `--`. Flags with values need `--` or `--flag=value`.
- Agent-runnable without a human: inspection flags (`--syntax-check`, `--list-*`), `--check`, `--unattended` runs against reachable servers, and playbooks that never escalate (e.g. `node`). `--check` skips `command`/`shell` tasks.
- An interactive playbook that escalates needs a TTY and the user's password, so ask the user to run it, then read `logs/latest.log`.
→ Failed run, tags, credentials: `docs/running.md`.

## Done means
1. `ansible-lint playbooks/ roles/ local.yml local-server.yml site.yml` is clean (from the repo root).
2. `--syntax-check` passes and `--check` is clean for module tasks.
3. A changed first-install path: `scripts/test-vm.sh run <playbook>` twice, and the second run converges (`changed=0`). The script pins LXD project `default`; use only the script. See `docs/testing.md`.
4. Verify on the machine (`dpkg -S`, `apt-cache policy`, `systemctl status`); `ok` only means the module was satisfied.
5. `git status` shows only intended changes (the VM share is read-write).

GNOME and desktop-session playbooks (`gnome.yml`, `installers/gnome-keybindings.sh`) cannot be VM-tested; leave them for a real machine.

## Authoring
- Every third-party APT repo goes through the `apt_source` role. Use `apt_source_legacy_files` for leftover `.list.disabled`/`.migrate` files, since the 26.04 upgrade disables hand-rolled sources.
- Install with `state: present`. Only `bootstrap` upgrades the whole system. Mark intentional `latest` with `# noqa: package-latest`.
- `workstation.yml` order matters only for `python` (pipx) before `ansible-tools` and `gnome_extensions`.
- `opencode` supports one architecture (`opencode_supported_arch`); override it per group before targeting a Raspberry Pi.
- Commits use Conventional Commits.
