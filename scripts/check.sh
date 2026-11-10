#!/usr/bin/env bash
#
# The repository's static checks, in one command: what AGENTS.md "Done means" 1
# and 2 ask for. The pre-commit hook (.githooks/pre-commit) runs it, so a commit
# cannot carry what it finds. Every step runs even after a failure, so one run
# lists everything.
#
#   ansible-lint     the whole tree (collections come from ansible.cfg)
#   syntax check     every playbook
#   shell syntax     every shell script
#   become           plays set "become: false" and tasks write the literal
#                    "become: true" (scripts/run-playbook.sh greps for it to decide
#                    whether to prompt for a sudo password)
#
# Hook setup, once per clone: git config core.hooksPath .githooks

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

failed=0
step() { printf '==> %s\n' "$1"; }
fail() { failed=1; }

step "ansible-lint"
ansible-lint playbooks/ roles/ local.yml local-server.yml site.yml || fail

step "playbook syntax"
for f in playbooks/*.yml local.yml local-server.yml site.yml; do
  ansible-playbook --syntax-check "$f" > /dev/null || { echo "syntax error in $f"; fail; }
done

step "shell syntax"
while IFS= read -r f; do
  bash -n "$f" || fail
done < <(find . -name '*.sh' -not -path './.git/*' -not -path './logs/*' -not -path './workspace/*')

step "become"
# A play-level "become: true" turns ansible_facts.env.HOME into /root.
if grep -nE '^  become:[[:space:]]*(true|yes)' playbooks/*.yml local.yml local-server.yml site.yml; then
  echo "play-level become: set it on the tasks that need root instead"; fail
fi
# A templated become cannot be found by the wrapper's grep.
if grep -rnE 'become:[[:space:]]*["'"'"'{]' playbooks roles local.yml local-server.yml site.yml; then
  echo "write the literal become: true"; fail
fi

if [[ $failed -eq 0 ]]; then echo "All checks passed."; else echo "Checks failed."; fi
exit "$failed"
