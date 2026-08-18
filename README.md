# ansible-homelab
Automated configuration of workstations, servers and containers in my home lab using Ansible.

## Bootstrap Requirements

In order to run `local.yml` for the first time, the following packages are required:

- git
- ansible

## Installation

1. Install required packages with:

   1. APT distro:

   ```sh
   sudo apt update -y && sudo apt install git ansible -y
   ```
   2. DNF distro:

     ```sh
     sudo dnf upgrade -y && sudo dnf install git ansible -y
     ```

 2. Use `ansible-pull` to run the default playbook `local.yml` directly from this repository:
    ```sh
    ansible-pull -U https://github.com/maubuz/ansible-homelab.git
    ```
    or run a specific playbook:
    ```sh
    ansible-pull -U https://github.com/maubuz/ansible-homelab.git workstation/1_workstation.yml
    ```

## Running playbooks locally

Clone the repository, `cd` into it, and use the wrapper — not `ansible-playbook`
directly:

```sh
scripts/run-playbook.sh workstation/4_workstation-wezterm.yml
```

The playbook argument can be any substring that matches exactly one playbook, so
these are equivalent:

```sh
scripts/run-playbook.sh wezterm
scripts/run-playbook.sh 4_
```

The wrapper prompts for the sudo password only when the playbook actually
escalates, forwards any flags through to `ansible-playbook`, and exits with the
playbook's own exit code.

It takes exactly one playbook per run and rejects a second bare word, since
`ansible-playbook` would otherwise treat it as another playbook to run. Use `--`
for the rare positional genuinely meant for ansible:

```sh
scripts/run-playbook.sh wezterm -- --limit localhost
```

### Why the wrapper

Running `ansible-playbook` by hand leaves no trace once the terminal scrollback
is gone, which makes a failed run impossible to review — and impossible to hand
to someone (or something) else to diagnose. Every run through the wrapper is
recorded:

| Path | Contents |
| --- | --- |
| `logs/<playbook>-<timestamp>.log` | Full console transcript of one run, plus the exact command, host, start/finish times and exit code |
| `logs/latest.log` | Symlink to the most recent run |
| `logs/ansible.log` | Rolling, timestamped log of every run ever made from this repo |

`logs/` is gitignored. Delete it whenever it gets noisy; it is recreated on the
next run.

Two repo-level config files support this and apply to any run started from the
repository root:

- `ansible.cfg` — enables the log, the `profile_tasks`/`timer` callbacks (per-task
  durations, so a slow or hung task is obvious in a log read after the fact), and
  `diff` output so file changes are visible in the transcript.
- `inventory.ini` — declares `localhost` with a local connection, which keeps
  "no inventory was parsed" warnings out of every log.

### Dry runs

`--check` predicts changes without making any. Do this first on an unfamiliar or
edited playbook:

```sh
scripts/run-playbook.sh --check wezterm
```

Note that `command`/`shell` tasks cannot be simulated and report as *skipped*, so
a clean check run is evidence about the module-based tasks only.

### Troubleshooting a run

The transcript is self-contained — the failing task, its module arguments, and
the module's `stdout`/`stderr` are all in it. When more detail is needed, raise
verbosity; `-vv` shows each task's full return value:

```sh
scripts/run-playbook.sh wezterm -vv
```

To narrow a re-run to the part that failed, use tags where a playbook defines
them — currently only `4_workstation-wezterm.yml`, with `setup` / `install` /
`cleanup`:

```sh
scripts/run-playbook.sh wezterm --tags setup
```

Inspection flags (`--syntax-check`, `--list-tasks`, `--list-tags`,
`--list-hosts`) never escalate, so the wrapper skips the password entirely for
them — they work unattended even on a playbook that uses `become`.

Then hand `logs/latest.log` to whoever is helping — it is the complete record of
what happened.

### Credentials

The sudo password is prompted for interactively and is never read from, or
written to, a file.

Where a password is actually needed, a playbook that escalates needs a terminal:
started without one, the wrapper exits 2 immediately rather than hanging on a
prompt nobody can answer. The wrapper skips the prompt only where sudo needs no
password as a matter of policy — running as root, or a `NOPASSWD` grant such as
the `ansiblebot` sudoers rule on a server or the default user of a cloud image
in the test VM.

That check reads the sudoers policy (`sudo -n -l`), not `sudo -n true`, which
would also succeed for a few minutes after any sudo because of the timestamp
cache — skipping the prompt on a workstation and then failing part-way through
the run once the cache expired.

Playbooks that do not escalate (for example `workstation/3_workstation-npm.yml`,
which runs `become: false`) need no credentials and run unattended.

### Testing against a clean machine

Every guard these playbooks rely on — `creates:`, "does the keyring exist", "is
the package installed" — is permanently satisfied on a machine that is already
provisioned. The first-install paths therefore never run here, which is exactly
backwards: they are the paths a new machine takes. `scripts/test-vm.sh` runs
them against a throwaway Ubuntu 26.04 LXD VM instead.

```sh
scripts/test-vm.sh create
scripts/test-vm.sh run 2b
scripts/test-vm.sh run 2b        # second run must report changed=0
scripts/test-vm.sh destroy
```

Run each playbook twice: the first run proves the install path works, the second
proves it converges.

The repository is shared into the VM live over virtiofs rather than copied, so
there is nothing to re-sync after an edit. Runs inside the VM write their logs
straight into `logs/` here, next to local ones; the `# host:` line at the top of
each log says which machine produced it.

Because the share is read-write onto this working tree, a run inside the VM can
in principle modify tracked files. `git status` after a session is the check.

A VM rather than a container, because `1_workstation.yml` installs snaps and
snapd is unreliable in an unprivileged container. It is created in LXD's
`default` project, and every command pins `--project` explicitly so no other
project is touched.

The VM's resources are declared in the script rather than taken from a named
profile, so it works on any machine with LXD: 2 CPUs, 4 GiB of RAM and a
**25 GiB disk**. Size that disk generously — `1_workstation.yml` is the
constraint. Its ten snaps plus the apt packages reach about 12 GB, which filled
a 15 GiB disk to 90% and left no headroom for `local.yml`'s system upgrade. The
pool is thin-provisioned, so 25 GiB is a ceiling rather than space reserved up
front.

The share behaves like a local directory in the guest — ownership maps both
ways, executable bits are honoured, throughput matches the VM's own disk — with
one measured exception: edits made on the host do not fire `inotify` inside the
VM, so file watchers running there will not see them.

What it cannot test: anything needing a desktop session. Leave
`5_workstation-gnome.yml` and `6_gnome-no-hotkey.sh` to a real machine.

### Linting

```sh
scripts/run-playbook.sh 2c     # installs ansible-lint; needs pipx from 2b
ansible-lint workstation/ local.yml
```

Catches the failure modes that are easy to miss by hand: tasks that always
report `changed`, `become_user` on a task that does not escalate, deprecated
module names, missing play names.

Ubuntu ships `community.general` and `ansible.posix` inside the ansible
package's own tree rather than on the default collections search path. The
system `ansible-playbook` finds them regardless, but `ansible-lint` runs from
its own virtualenv and does not — it reports every `community.general` task as
an unresolvable module. `ansible.cfg` sets `collections_path` to cover this, so
run the linter from the repository root.

### Execution model: interactive vs unattended

The `workstation/` playbooks are **interactive-only**. They are meant to be run
by the person sitting at the machine, via the wrapper, entering their own sudo
password. Two of them (`2b_workstation-python.yml`, `5_workstation-gnome.yml`)
deliberately run `become: false` and resolve paths from
`ansible_facts.env.HOME`, so they install into the home directory of whoever
invokes them — correct for a workstation, wrong for a daemon.

Unattended execution is reserved for **server** machines, using the `ansiblebot`
system account that `local.yml` provisions (passwordless sudo via
`/etc/sudoers.d/ansiblebot`, plus an authorized SSH key) and driven by
`ansible-pull`. Nothing in `workstation/` is currently designed for that path:
run under `ansible-pull` as `ansiblebot`, the two `become: false` playbooks would
resolve `HOME` to `/home/ansiblebot` and provision the wrong user's desktop.

Before adding a playbook to the unattended set, make sure it either escalates
explicitly or takes its target user from an inventory variable rather than from
the invoking user's environment.

### Working with an AI agent

You run the playbook, the agent reads the log:

```sh
scripts/run-playbook.sh wezterm     # you, in a terminal, entering your password
```

Then point the agent at `logs/latest.log`. It contains the full output, the
diffs, the per-task timings and the exit code, so the agent can diagnose a
failure it never watched — with nothing stored and no standing access granted.

The agent can start unattended runs only for playbooks that never escalate, and
can always use the inspection flags above on any playbook.

After a run, the agent should verify against the machine (`dpkg -S`,
`apt-cache policy`, `systemctl status`) rather than trusting the recap alone — a
task reporting `ok` only means the module was satisfied.

