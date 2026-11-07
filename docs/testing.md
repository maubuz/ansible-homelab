# Testing against a clean machine

Every guard these playbooks rely on (`creates:`, "does the keyring exist", "is
the package installed") is permanently satisfied on a machine that is already
provisioned, so the first-install paths never run there, and a new machine takes
exactly those paths. `scripts/test-vm.sh` runs them on a *clean* throwaway Ubuntu
26.04 LXD VM. Use only the script: it pins LXD project `default`, where other
VMs live.

## Procedure

1. `scripts/test-vm.sh status`, then `create` if it reports no VM. `create`
   applies pending updates and restarts once, so a later run's session is not
   killed by a systemd or `lxd-agent` restart mid-playbook. Any command starts a
   stopped VM by itself.
2. `scripts/test-vm.sh run <playbook>`. Ansible arguments go after `--`, and each
   argument reaches the wrapper whole (`-- -e 'x=a b'`, `'$HOME'` and all).
3. Run it again and *converge*: read the recap with
   `grep -E '^\S+ +:' logs/latest.log`. Run 1 shows `failed=0`; run 2 shows
   `changed=0 failed=0`. A non-zero `changed` on run 2 is red, and the task
   named in the log is the bug.
4. Verify the machine, not the recap (`ok` only means the module was satisfied):
   `scripts/test-vm.sh exec [--root] <command>` runs one command from the
   repository directory, as `ubuntu` or as root, and returns its exit code
   (`exec getent passwd ansiblebot`, `exec --root visudo -c`).
5. `git status`: the share is read-write, so a run can modify tracked files.
6. `scripts/test-vm.sh reboot` restarts the VM and waits until it is back, for
   what only a new boot applies (a kernel parameter such as `consoleblank`).
7. `scripts/test-vm.sh destroy` when the session is done.

Done means green on steps 1 to 5 for every playbook the change touches. Step 6
is only for a change that needs a new boot to take effect.

## Facts the script does not tell you

- The repository is shared live over virtiofs, so uncommitted edits are what
  runs: edit here, run there. VM logs land in this repo's `logs/`; the `# host:`
  line at the top of each says which machine wrote it.
- Keep test inputs (vars files, inventories) in `logs/`, which is gitignored and
  visible inside the VM at `/home/ubuntu/ansible-homelab/logs/`. Delete them
  after the session. Private keys are generated inside the VM and stay there.
- The `ubuntu` user has passwordless sudo, so the wrapper never prompts. The
  `--ask-become-pass` path and the wrapper's no-terminal exit 2 cannot be
  exercised here; test those on the host with `--check`.
- `ansible-pull` clones from git, so it sees only committed work. Before a
  commit, emulate a pull with `scripts/test-vm.sh run local.yml -- -i localhost, -c local`
  (the same generated-inventory shape), or run the real thing from a throwaway
  repository built inside the VM (`docs/testing-unattended.md`, scenario P).
  After a commit, `scripts/test-vm.sh exec ansible-pull -U file:///home/ubuntu/ansible-homelab -d /home/ubuntu/pull-checkout local.yml`
  works directly.
- `local` matches two playbooks and the wrapper rejects it as ambiguous; name
  `local.yml` or `local-server`.
- It is a VM, not a container, because the `desktop` role installs snaps and
  snapd is unreliable in an unprivileged container. Sizing and its reasons are in
  the header of `scripts/test-vm.sh`.

## Cannot be tested here

The lid switch itself: the VM can show logind reporting `ignore` and the sleep
targets masked, not that closing a real lid keeps the machine up. Likewise it can
show the kernel running with `consoleblank=60` after a reboot, not that the panel
goes dark (`docs/laptop-server.md`).

Anything needing a desktop session: `playbooks/gnome.yml` and
`installers/gnome-keybindings.sh` wait for a real machine.

## Touching `ansiblebot`, `servers.yml` or `local*.yml`

→ Read `docs/testing-unattended.md`; it holds the scenarios for accounts, keys
and the pull and controller entry points.
