# Testing against a clean machine

Every guard these playbooks rely on (`creates:`, "does the keyring exist", "is
the package installed") is permanently satisfied on a machine that is already
provisioned. The first-install paths never run there, and they are the paths a
new machine takes. `scripts/test-vm.sh` runs them against a throwaway Ubuntu
26.04 LXD VM.

```sh
scripts/test-vm.sh create
scripts/test-vm.sh run python
scripts/test-vm.sh run python    # second run must report changed=0
scripts/test-vm.sh destroy
```

Run each playbook twice: the first run proves the install path works, the
second proves it converges.

- The repository is shared into the VM live over virtiofs, so there is nothing
  to re-sync after an edit. Logs from VM runs land in this repo's `logs/`; the
  `# host:` line at the top of each says which machine produced it.
- The share is read-write onto this working tree, so a run inside the VM can
  modify tracked files. Check `git status` after a session.
- The VM lives in LXD's `default` project, and every command pins `--project`.
- It is a VM, not a container, because the `desktop` role installs snaps and
  snapd is unreliable in an unprivileged container.
- Sizing (2 CPUs, 4 GiB RAM, 25 GiB disk) and the reasons for it are in the
  header of `scripts/test-vm.sh`.

**What it cannot test:** anything needing a desktop session. Leave
`playbooks/gnome.yml` and `installers/gnome-keybindings.sh` to a real machine.

The VM does not exercise unattended mode. It runs the interactive path as its
own `ubuntu` user.
