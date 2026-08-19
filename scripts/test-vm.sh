#!/usr/bin/env bash
#
# Run this repository's playbooks against a throwaway Ubuntu 26.04 VM.
#
# Everything here has otherwise only been tested on one fully provisioned
# machine, where every "creates:" guard, keyring and apt source already exists —
# so the first-install paths never execute. A clean VM is the only place they do.
#
# It is a VM rather than a container because the desktop role installs snaps,
# and snapd is unreliable in an unprivileged container. Those snaps are also
# what sets the disk size: they need well over 15GiB once the apt packages are
# there too.
#
# This repository is shared into the VM live, over virtiofs, rather than copied:
# edit here, run there, with no step in between. Runs inside the VM therefore
# write their logs straight into this repository's logs/ directory alongside
# local ones — the "# host:" line in each log header says which machine it came
# from.
#
# Usage:
#   scripts/test-vm.sh create              # launch, provision and share the repo
#   scripts/test-vm.sh run <playbook>      # run a playbook inside it
#   scripts/test-vm.sh shell               # interactive shell in the VM
#   scripts/test-vm.sh status              # is it running?
#   scripts/test-vm.sh destroy             # delete it
#
# Typical session:
#   scripts/test-vm.sh create
#   scripts/test-vm.sh run python
#   scripts/test-vm.sh run python              # second run must report changed=0
#   scripts/test-vm.sh destroy
#
# The VM's default user has passwordless sudo, so plays run unattended there;
# scripts/run-playbook.sh detects that and skips its password prompt.

# Must be executed, not sourced. Sourcing applies the "set -euo pipefail" below
# to the interactive shell itself: nounset then kills that shell on the first
# unset variable it meets, which for a shell with a themed prompt is usually
# immediate. Any "exit" below would close it outright too.
if [[ ${BASH_SOURCE[0]} != "${0}" ]]; then
  echo "Run this script, do not source it:  ./${BASH_SOURCE[0]}" >&2
  return 1
fi

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# The sa4 project holds a lab of VMs that must not be touched, so every lxc
# call below pins the project explicitly rather than relying on the current one.
readonly PROJECT=default
readonly VM=ansible-test
readonly IMAGE=ubuntu:26.04
# Resources are declared here rather than taken from a named profile, so this
# works on any machine with LXD rather than only one that happens to have a
# particular profile defined.
#
# 25GiB because the desktop role is the sizing constraint: its ten snaps plus
# the apt packages reached 12GB, which filled a 15GiB disk to 90% and left no
# room for the bootstrap role's upgrade. ZFS is sparse, so this is a ceiling and
# not a reservation.
readonly VM_CPU=2
readonly VM_MEMORY=4GiB
readonly VM_DISK=25GiB
readonly VM_REPO=/home/ubuntu/ansible-homelab
readonly SHARE_DEV=repo

die() {
  printf 'test-vm: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() {
  awk 'NR > 1 && /^#/ { sub(/^#[[:space:]]?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

# --project must come BEFORE the subcommand, never after the arguments. For
# "lxc exec" everything past -- is the guest's command line, so a trailing
# --project would be handed to the guest as a stray argument while lxc itself
# quietly used whatever project happens to be current.
lxc_() { lxc --project "$PROJECT" "$@"; }

# Root shell in the VM. lxc exec runs as root already.
vm_root() { lxc_ exec "$VM" -- "$@"; }

# Login shell as the unprivileged user, which is how a real run happens — and,
# because the repository is shared rather than copied, also what keeps files the
# run creates in it owned by the invoking user on the host rather than by root.
vm_user() { lxc_ exec "$VM" -- sudo -iu ubuntu -- "$@"; }

vm_exists() { lxc_ info "$VM" >/dev/null 2>&1; }

require_vm() {
  vm_exists || die "$VM does not exist. Run: scripts/test-vm.sh create"
}

cmd_create() {
  command -v lxc >/dev/null || die "lxc not found"
  if vm_exists; then
    echo "$VM already exists; nothing to do. Use 'destroy' first to start over."
    return 0
  fi

  echo "==> Launching $VM ($IMAGE, ${VM_CPU} cpu, ${VM_MEMORY} ram, ${VM_DISK} disk)"
  # The default profile supplies the network and the storage pool, which every
  # LXD install has; only the sizing is overridden on top of it.
  # stdin from /dev/null: "lxc launch" blocks indefinitely reading stdin when it
  # inherits a pipe that never delivers, which is what happens when this script
  # runs from a non-interactive parent such as CI or a background job. It waits
  # on the socket with no timeout of its own, so the symptom is a create that
  # never returns rather than an error. "lxc exec" is unaffected.
  lxc_ launch "$IMAGE" "$VM" --vm \
    --config "limits.cpu=${VM_CPU}" \
    --config "limits.memory=${VM_MEMORY}" \
    --device "root,size=${VM_DISK}" </dev/null

  echo "==> Waiting for cloud-init"
  # The agent needs a moment before exec works at all.
  for _ in {1..60}; do
    lxc_ exec "$VM" -- true 2>/dev/null && break
    sleep 2
  done
  vm_root cloud-init status --wait

  echo "==> Installing ansible"
  vm_root apt-get update -qq
  vm_root apt-get install -y -qq ansible git

  # The syncthing role enables a *user* systemd service, which needs a
  # persistent user manager. Without lingering there is no session for a
  # non-login exec to talk to and the task fails for reasons unrelated to it.
  echo "==> Enabling lingering for the ubuntu user"
  vm_root loginctl enable-linger ubuntu

  cmd_share
  echo "==> Ready. Run a playbook with: scripts/test-vm.sh run python"
}

cmd_share() {
  if lxc_ config device show "$VM" 2>/dev/null | grep -q "^${SHARE_DEV}:"; then
    echo "==> Repository already shared at $VM_REPO"
  else
    echo "==> Sharing $repo_root -> $VM:$VM_REPO"
    # No shift= here: that is a userns idmap concept and applies to containers
    # only. A VM gets the directory over virtiofs, which maps uids straight
    # through, so files this user owns here are owned by the matching uid there.
    lxc_ config device add "$VM" "$SHARE_DEV" disk \
      source="$repo_root" path="$VM_REPO"
  fi

  # The device being listed does not mean the guest mounted it; in a VM that is
  # lxd-agent's job and a failure leaves an empty directory rather than an error.
  vm_root findmnt -rno TARGET "$VM_REPO" >/dev/null 2>&1 ||
    die "the share was added but nothing is mounted at $VM_REPO inside the VM.
Check lxd-agent:  lxc exec $VM --project $PROJECT -- systemctl status lxd-agent"
}

cmd_run() {
  require_vm
  [[ $# -gt 0 ]] || die "run needs a playbook, e.g. scripts/test-vm.sh run python"
  vm_user bash -lc "cd '$VM_REPO' && scripts/run-playbook.sh $*"
}

cmd_shell() {
  require_vm
  lxc_ exec "$VM" -- sudo -iu ubuntu
}

cmd_status() {
  vm_exists || { echo "$VM does not exist"; return 0; }
  lxc_ list "^$VM\$"
}

cmd_destroy() {
  vm_exists || { echo "$VM does not exist; nothing to destroy."; return 0; }
  # Named explicitly, never a pattern: ta-metrics-db also lives in this project.
  echo "==> Deleting $VM from project $PROJECT"
  lxc_ delete "$VM" --force
  echo "==> Deleted"
}

[[ $# -gt 0 ]] || usage 1
command=$1
shift

case "$command" in
  create) cmd_create "$@" ;;
  share) cmd_share "$@" ;;
  run) cmd_run "$@" ;;
  shell) cmd_shell "$@" ;;
  status) cmd_status "$@" ;;
  destroy) cmd_destroy "$@" ;;
  -h | --help) usage 0 ;;
  *) die "unknown command '$command' (try --help)" ;;
esac
