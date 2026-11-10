# AGENTS.md

Ansible for a personal homelab. Targets Ubuntu 24.04+ only (26.04 preferred), across several host types: desktop laptop, laptop server, GPU workstation, Raspberry Pi. Each host type is an inventory group plus `group_vars/<group>.yml`; roles read the values and do not branch on machine kind. Human docs are in `README.md` and `docs/`.

## Execution modes
- **Interactive** (workstations): a person runs `scripts/run-playbook.sh` and types the sudo password. `node`, `opencode` and `gnome_extensions` install into the connecting user's `$HOME`.
- **Unattended** (servers): connects as `ansiblebot` with passwordless sudo, either via `ansible-pull local-server.yml` on the host or from a controller over SSH (`scripts/run-playbook.sh --unattended servers`). Both apply the `server` role (a list of dependencies in `roles/server/meta/main.yml`: `bootstrap`, `ansiblebot`, the `server_*` roles, `wezterm`, `tailscale`) and nothing else. Add a server role there, not to the two playbooks. A playbook or role joins this mode only after it escalates explicitly or takes its target user from an inventory variable.
- Plays set `become: false`; roles set `become: true` per task. Play-level become turns `ansible_facts.env.HOME` into `/root`. Write the literal `become: true` (or `yes`), because the wrapper greps for it to decide whether to prompt for sudo.
- Workstation roles (`desktop`, `node`, `python`, `syncthing`) and server roles (`server_*`) are separate on purpose and never share variable names; only `baseline_*` (group_vars/all.yml) is shared. `ansible-pull` ignores `group_vars/servers.yml`, so a value a server role needs on a pull belongs in `all.yml` or the role's defaults.
- The `ansiblebot` account (root-equivalent) belongs only in `servers.yml` and `local-server.yml`, never in `local.yml` or a workstation playbook; `local.yml` is what desktops pull. The role fails unless `ansiblebot_keys` (group_vars/all.yml) is non-empty; its `authorized_key` is exclusive, so removing an entry revokes that key. Only public keys belong in the repo.
- From a controller, target `playbooks/servers.yml`; `local*.yml` use `hosts: all` and would also match `localhost`.
→ Before changing escalation, `$HOME` paths or the unattended set, read `docs/execution-model.md`.
- `server_syncthing` manages only the OS side: a `syncthing` service account running the system instance, one `syncthing@<user>` per `server_syncthing_users`, and every GUI on a Unix socket, never a TCP port. Devices and folders are set by hand in each GUI, not in Ansible. Admin is exclusive membership of group `syncthing` (`server_admin_user`).
- Exception: `playbooks/servers.yml` has a second play, `hosts: laptop_servers`, for `server_laptop` (push only, not in `local-server.yml`).
→ Laptop servers (lid action, sleep masking, console blanking and its pending reboot, BIOS prerequisite): `docs/laptop-server.md`.
→ Before the first apply on a real laptop server, run the read-only preflight (`playbooks/preflight-laptop-server.yml`, after the `server` role): "Before the first apply" in that doc. An agent may run it.
→ Syncthing on servers (system instance, personal instances, socket GUIs): `docs/syncthing-server.md`.

## Running
- Run playbooks through `scripts/run-playbook.sh <substring>`: one playbook per run, ansible args after `--`. Flags with values need `--` or `--flag=value`.
- Agent-runnable without a human: inspection flags (`--syntax-check`, `--list-*`), `--check`, `--unattended` runs against reachable servers, and playbooks that never escalate (e.g. `node`). `--check` skips `command`/`shell` tasks.
- An interactive playbook that escalates needs a TTY and the user's password, so ask the user to run it, then read `logs/latest.log`.
→ Failed run, tags, credentials: `docs/running.md`.

## Done means
1. `scripts/check.sh` passes (lint, syntax, the `become` rules); the pre-commit hook runs it (`git config core.hooksPath .githooks`, once per clone).
2. `--check` is clean for module tasks.
3. A changed first-install path (a `creates:` guard, keyring, new role): `scripts/test-vm.sh run <playbook>` twice, and the second run converges (`changed=0`); verify with `scripts/test-vm.sh exec`. Use only the script. → `docs/testing.md`; touching `ansiblebot`, `servers.yml` or `local*.yml` → `docs/testing-unattended.md`.
4. Verify on the machine (`dpkg -S`, `apt-cache policy`, `systemctl status`); `ok` only means the module was satisfied.
5. `git status` shows only intended changes (the VM share is read-write).

GNOME and desktop-session playbooks (`gnome.yml`, `installers/gnome-keybindings.sh`) cannot be VM-tested; leave them for a real machine.

## Authoring
- Every third-party APT repo goes through the `apt_source` role. Use `apt_source_legacy_files` for leftover `.list.disabled`/`.migrate` files, since the 26.04 upgrade disables hand-rolled sources.
- Install with `state: present`. Only `bootstrap` upgrades the whole system. Mark intentional `latest` with `# noqa: package-latest`.
- `workstation.yml` order matters only for `python` (pipx) before `ansible-tools` and `gnome_extensions`.
- `opencode` supports one architecture (`opencode_supported_arch`); override it per group before targeting a Raspberry Pi.
- Commits use Conventional Commits.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `maubuz/ansible-homelab` (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
