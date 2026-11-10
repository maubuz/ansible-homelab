# Running playbooks

Use the wrapper, not `ansible-playbook` directly:

```sh
scripts/run-playbook.sh wezterm           # any substring matching exactly one playbook
scripts/run-playbook.sh playbooks/wezterm.yml
scripts/run-playbook.sh --check wezterm
scripts/run-playbook.sh wezterm -- --limit localhost
```

It takes exactly one playbook per run and rejects a second bare word, because
`ansible-playbook` would treat it as another playbook to run. Pass anything
meant for ansible after `--`. It forwards flags and exits with the playbook's
exit code. `scripts/run-playbook.sh --help` lists the options.

## Why the wrapper

Running `ansible-playbook` by hand leaves no trace once the scrollback is gone.
Every wrapped run is recorded:

| Path | Contents |
| --- | --- |
| `logs/<playbook>-<timestamp>.log` | Full console transcript of one run, plus the exact command, host, start and finish times, and exit code |
| `logs/latest.log` | Symlink to the most recent run |
| `logs/ansible.log` | Rolling log of every run ever made from this repo |

`logs/` is gitignored and recreated on the next run. `ansible.cfg` also turns on
per-task timings and `diff` output, so the transcript shows what changed and
where time went.

## Credentials

The sudo password is prompted for interactively and never read from or written to
a file. A playbook that escalates needs a terminal, and without one the wrapper
exits 2 rather than hanging.

The prompt is skipped when running as root or when the local account has a
`NOPASSWD: ALL` sudo rule. Pass `--unattended` when the targets, not this
machine, are what grants passwordless sudo (see `docs/execution-model.md`).
Playbooks whose roles never escalate (for example `playbooks/node.yml`) need no
credentials.

## Dry runs

`--check` predicts changes without making any. `command` and `shell` tasks
cannot be simulated and report as skipped, so a clean check says nothing about
them.

## Troubleshooting

The transcript holds the failing task, its module arguments and the module's
`stdout` and `stderr`. Raise verbosity with `-vv` for each task's full return
value. To re-run only part of a role, use tags (`scripts/run-playbook.sh <pb>
--list-tags` shows which roles define them):

```sh
scripts/run-playbook.sh wezterm --tags setup
```

Inspection flags (`--syntax-check`, `--list-tasks`, `--list-tags`,
`--list-hosts`) never escalate, so they work unattended on any playbook.

Hand `logs/latest.log` to whoever is helping. It is the complete record.

After a run, verify against the machine (`dpkg -S`, `apt-cache policy`,
`systemctl status`) rather than trusting the recap. An `ok` task only means the
module was satisfied.

## Linting

```sh
scripts/run-playbook.sh ansible-tools   # installs ansible-lint; needs pipx from the python role
scripts/check.sh                        # lint, syntax and become rules
```

Enable the pre-commit hook once per clone: `git config core.hooksPath .githooks`.

The script runs from the repository root, where `ansible.cfg` supplies the
collections path that `ansible-lint`'s own virtualenv lacks.
