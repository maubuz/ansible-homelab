#!/usr/bin/env bash
#
# Single entry point for running the playbooks in this repository.
#
# Every run is captured to logs/<playbook>-<timestamp>.log and mirrored to
# logs/latest.log, so a run can be reviewed — or handed to an agent to
# troubleshoot — after the fact instead of only being watched live.
#
# Usage:
#   scripts/run-playbook.sh [--check] <playbook> [extra ansible-playbook args]
#
# Examples:
#   scripts/run-playbook.sh workstation/4_workstation-wezterm.yml
#   scripts/run-playbook.sh --check wezterm      # substring match, dry run
#   scripts/run-playbook.sh local.yml --tags install
#   scripts/run-playbook.sh npm -vv              # extra verbosity
#
# A playbook that escalates is prompted for with --ask-become-pass and therefore
# needs a terminal; without one the script exits 2 rather than hanging. The sudo
# password is never read from, or written to, a file. Playbooks that do not
# escalate (become: false) need no credentials and run unattended.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

die() {
  printf 'run-playbook: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  # Print the header comment block, minus the shebang.
  awk 'NR > 1 && /^#/ { sub(/^#[[:space:]]?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

# ── Arguments ─────────────────────────────────────────────────────────────────
playbook=""
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage 0 ;;
    -C | --check) extra+=(--check) ;;
    --) shift; extra+=("$@"); break ;;
    -*) extra+=("$1") ;;
    # Exactly one playbook per run. A second bare word is almost always a typo,
    # and forwarding it would make ansible-playbook treat it as another playbook
    # to run — so "run-playbook.sh npm local" would also run local.yml, which
    # upgrades every package on the machine. Flag values still pass through
    # above; use -- for the rare positional that is genuinely meant for ansible.
    *)
      [[ -z $playbook ]] ||
        die "unexpected argument '$1': only one playbook per run (use -- to pass positionals through to ansible-playbook)"
      playbook=$1
      ;;
  esac
  shift
done

[[ -n $playbook ]] || usage 1

# ── Resolve the playbook path ─────────────────────────────────────────────────
# Accepts a full path, or any substring unique among the repo's playbooks.
if [[ ! -f $playbook ]]; then
  mapfile -t matches < <(ls workstation/*.yml ./*.yml 2>/dev/null | grep -i -- "$playbook" || true)
  case ${#matches[@]} in
    1) playbook=${matches[0]} ;;
    0) die "no playbook matching '$playbook'" ;;
    *) die "'$playbook' is ambiguous: ${matches[*]}" ;;
  esac
fi

# ── Become credentials ────────────────────────────────────────────────────────
# Flags that only inspect the playbook never escalate, so they need no password.
inspect_only=false
for arg in "${extra[@]}"; do
  case "$arg" in
    --syntax-check | --list-tasks | --list-tags | --list-hosts) inspect_only=true ;;
  esac
done

# True when sudo needs no password as a matter of policy: running as root, or a
# NOPASSWD grant such as the ansiblebot sudoers rule on a server or the default
# user of an Ubuntu cloud image in the test VM.
#
# Deliberately not "sudo -n true", which also succeeds for a few minutes after
# any sudo because of the timestamp cache. That would skip the prompt on a
# workstation and then fail part-way through the run when the cache expired.
# "sudo -n -l" prints the rule itself, and only a real grant contains NOPASSWD;
# a merely-cached password lists the rule without it.
sudo_is_passwordless() {
  [[ $EUID -eq 0 ]] && return 0
  sudo -n -l 2>/dev/null | grep -q 'NOPASSWD: ALL'
}

become_args=()
if ! $inspect_only && grep -qE '^[[:space:]]*become:[[:space:]]*(true|yes)' "$playbook"; then
  if sudo_is_passwordless; then
    : # nothing to prompt for, so the run works unattended
  elif [[ -t 0 ]]; then
    become_args=(--ask-become-pass)
  else
    die "$playbook needs sudo but there is no terminal to prompt on.
Run it yourself:  scripts/run-playbook.sh $playbook
then share the log it writes under logs/." 2
  fi
fi

# ── Run ───────────────────────────────────────────────────────────────────────
mkdir -p logs
slug=$(basename "$playbook" .yml)
log="logs/${slug}-$(date +%Y%m%d-%H%M%S).log"
cmd=(ansible-playbook "${become_args[@]}" "${extra[@]}" "$playbook")

{
  echo "# playbook: $playbook"
  echo "# command:  ${cmd[*]}"
  echo "# host:     $(hostname)   user: $USER"
  echo "# started:  $(date -Is)"
  echo
} | tee "$log"

set +e
"${cmd[@]}" 2>&1 | tee -a "$log"
rc=${PIPESTATUS[0]}
set -e

{
  echo
  echo "# finished: $(date -Is)   exit=$rc"
} | tee -a "$log"

ln -sfn "$(basename "$log")" logs/latest.log
echo "log: $log"
exit "$rc"
